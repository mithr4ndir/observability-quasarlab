# Workstream B: VM Monitoring via Ansible

## Objective
Deploy node_exporter (metrics) and Filebeat (logs) on all VMs, managed via Ansible. Logs ship to existing Elasticsearch cluster.

## Target Repository
`~/code/ansible-quasarlab`

## Prerequisites
- Ansible inventory already configured with all hosts
- SSH access to all VMs
- Elasticsearch running at 192.168.1.167:9200

## Target VMs
| Host | IP | Group |
|------|-----|-------|
| k8cluster1 | 192.168.1.90 | k8s |
| k8cluster2 | 192.168.1.89 | k8s |
| k8cluster3 | 192.168.1.91 | k8s |
| nginx1 | 192.168.1.92 | lb |
| nginx2 | 192.168.1.93 | lb |
| cmd_center1 | 192.168.1.88 | cmd_center |
| grafana | 192.168.1.121 | monitoring |
| elastic | 192.168.1.167 | databases |
| timescaledb | 192.168.1.122 | databases |
| npm | 192.168.1.150 | services |

**Note:** AD (192.168.1.67) is Windows - skip for now.

## Implementation Steps

### Step 1: Update Ansible inventory
Update `inventory.ini` with correct IPs:

```ini
[k8s]
k8cluster1 ansible_host=192.168.1.90
k8cluster2 ansible_host=192.168.1.89
k8cluster3 ansible_host=192.168.1.91

[lb]
nginx1 ansible_host=192.168.1.92
nginx2 ansible_host=192.168.1.93

[cmd_center]
cmd_center1 ansible_host=192.168.1.88

[monitoring]
grafana ansible_host=192.168.1.121

[databases]
elastic ansible_host=192.168.1.167
timescaledb ansible_host=192.168.1.122

[services]
npm ansible_host=192.168.1.150

[linux:children]
k8s
lb
cmd_center
monitoring
databases
services
```

### Step 2: Create node_exporter role
**Directory structure:**
```
roles/
└── node_exporter/
    ├── tasks/
    │   └── main.yml
    ├── handlers/
    │   └── main.yml
    ├── templates/
    │   └── node_exporter.service.j2
    └── defaults/
        └── main.yml
```

**tasks/main.yml:**
```yaml
---
- name: Create node_exporter user
  user:
    name: node_exporter
    shell: /usr/sbin/nologin
    system: yes
    create_home: no

- name: Download node_exporter
  get_url:
    url: "https://github.com/prometheus/node_exporter/releases/download/v{{ node_exporter_version }}/node_exporter-{{ node_exporter_version }}.linux-amd64.tar.gz"
    dest: /tmp/node_exporter.tar.gz

- name: Extract node_exporter
  unarchive:
    src: /tmp/node_exporter.tar.gz
    dest: /tmp
    remote_src: yes

- name: Install node_exporter binary
  copy:
    src: "/tmp/node_exporter-{{ node_exporter_version }}.linux-amd64/node_exporter"
    dest: /usr/local/bin/node_exporter
    mode: '0755'
    owner: root
    group: root
    remote_src: yes

- name: Create systemd service
  template:
    src: node_exporter.service.j2
    dest: /etc/systemd/system/node_exporter.service
  notify: Restart node_exporter

- name: Enable and start node_exporter
  systemd:
    name: node_exporter
    enabled: yes
    state: started
    daemon_reload: yes
```

**handlers/main.yml:**
```yaml
---
- name: Restart node_exporter
  systemd:
    name: node_exporter
    state: restarted
    daemon_reload: yes
```

**defaults/main.yml:**
```yaml
node_exporter_version: "1.7.0"
node_exporter_port: 9100
```

**templates/node_exporter.service.j2:**
```ini
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:{{ node_exporter_port }}

[Install]
WantedBy=multi-user.target
```

### Step 3: Create Filebeat role for log collection
**Directory structure:**
```
roles/
└── filebeat/
    ├── tasks/
    │   └── main.yml
    ├── handlers/
    │   └── main.yml
    ├── templates/
    │   └── filebeat.yml.j2
    └── defaults/
        └── main.yml
```

**tasks/main.yml:**
```yaml
---
- name: Add Elastic GPG key
  apt_key:
    url: https://artifacts.elastic.co/GPG-KEY-elasticsearch
    state: present

- name: Add Elastic repository
  apt_repository:
    repo: "deb https://artifacts.elastic.co/packages/8.x/apt stable main"
    state: present

- name: Install Filebeat
  apt:
    name: filebeat
    state: present
    update_cache: yes

- name: Configure Filebeat
  template:
    src: filebeat.yml.j2
    dest: /etc/filebeat/filebeat.yml
    mode: '0600'
  notify: Restart filebeat

- name: Enable system module
  command: filebeat modules enable system
  args:
    creates: /etc/filebeat/modules.d/system.yml

- name: Enable and start Filebeat
  systemd:
    name: filebeat
    enabled: yes
    state: started
```

**handlers/main.yml:**
```yaml
---
- name: Restart filebeat
  systemd:
    name: filebeat
    state: restarted
```

**defaults/main.yml:**
```yaml
elasticsearch_host: "192.168.1.167:9200"
elasticsearch_username: "elastic"
# elasticsearch_password should be in vault
```

**templates/filebeat.yml.j2:**
```yaml
filebeat.inputs:
  - type: filestream
    id: syslog
    enabled: true
    paths:
      - /var/log/syslog
      - /var/log/auth.log
    fields:
      host: "{{ inventory_hostname }}"
      type: syslog
    fields_under_root: true

  - type: filestream
    id: app-logs
    enabled: true
    paths:
      - /var/log/*.log
    exclude_files:
      - '\.gz$'
    fields:
      host: "{{ inventory_hostname }}"
      type: application
    fields_under_root: true

filebeat.modules:
  - module: system
    syslog:
      enabled: true
    auth:
      enabled: true

processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
  - add_fields:
      target: ''
      fields:
        environment: quasarlab
        plane: hypervisor

output.elasticsearch:
  hosts: ["{{ elasticsearch_host }}"]
  username: "{{ elasticsearch_username }}"
  password: "{{ elasticsearch_password }}"
  index: "vm-logs-%{+yyyy.MM.dd}"

setup.template.name: "vm-logs"
setup.template.pattern: "vm-logs-*"
setup.ilm.enabled: true
setup.ilm.rollover_alias: "vm-logs"
setup.ilm.pattern: "{now/d}-000001"

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
  permissions: 0640
```

### Step 4: Create group_vars for credentials
**group_vars/all.yml** (or use ansible-vault):
```yaml
elasticsearch_password: "{{ vault_elasticsearch_password }}"
```

**group_vars/vault.yml** (encrypted):
```yaml
vault_elasticsearch_password: "your-elastic-password"
```

### Step 5: Create monitoring playbook
**playbooks/monitoring.yml:**
```yaml
---
- name: Deploy monitoring agents to all Linux VMs
  hosts: linux
  become: yes
  roles:
    - node_exporter
    - filebeat
  vars:
    elasticsearch_host: "192.168.1.167:9200"
    elasticsearch_username: "elastic"
```

### Step 6: Update site.yml
Add monitoring playbook to site.yml:
```yaml
---
- import_playbook: playbooks/monitoring.yml
  tags: [monitoring]
```

### Step 7: Add Prometheus scrape config for VMs
Add static targets to Prometheus (in Workstream A values.yaml):
```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'vm-node-exporter'
        static_configs:
          - targets:
            - '192.168.1.88:9100'   # cmd_center1
            - '192.168.1.90:9100'   # k8cluster1
            - '192.168.1.89:9100'   # k8cluster2
            - '192.168.1.91:9100'   # k8cluster3
            - '192.168.1.92:9100'   # nginx1
            - '192.168.1.93:9100'   # nginx2
            - '192.168.1.121:9100'  # grafana
            - '192.168.1.167:9100'  # elastic
            - '192.168.1.122:9100'  # timescaledb
            - '192.168.1.150:9100'  # npm
        relabel_configs:
          - source_labels: [__address__]
            regex: '(.*):\d+'
            target_label: instance
```

## Validation Steps
1. Run playbook in check mode: `ansible-playbook -i inventory.ini playbooks/monitoring.yml --check`
2. Apply: `ansible-playbook -i inventory.ini playbooks/monitoring.yml`
3. Verify node_exporter: `curl http://192.168.1.88:9100/metrics`
4. Verify Filebeat: `systemctl status filebeat`
5. Check Kibana for `vm-logs-*` index
6. Check Prometheus targets show VMs as UP

## Files Summary
```
ansible-quasarlab/
├── inventory.ini (updated)
├── group_vars/
│   ├── all.yml (new)
│   └── vault.yml (new, encrypted)
├── playbooks/
│   └── monitoring.yml (new)
├── roles/
│   ├── node_exporter/ (new)
│   │   ├── tasks/main.yml
│   │   ├── handlers/main.yml
│   │   ├── templates/node_exporter.service.j2
│   │   └── defaults/main.yml
│   └── filebeat/ (new)
│       ├── tasks/main.yml
│       ├── handlers/main.yml
│       ├── templates/filebeat.yml.j2
│       └── defaults/main.yml
└── site.yml (updated)
```

## Estimated Complexity
- Medium
- Standard Ansible role development

## Dependencies
- Elasticsearch credentials needed
- Workstream A provides Prometheus to scrape node_exporter
- Workstream D for Grafana dashboard configuration
