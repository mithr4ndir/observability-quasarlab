# Workstream B: VM Monitoring via Ansible

## Objective
Deploy node_exporter and Grafana Alloy on all VMs for metrics and log collection, managed via Ansible.

## Target Repository
`~/code/ansible-quasarlab`

## Prerequisites
- Ansible inventory already configured with all hosts
- SSH access to all VMs
- Grafana Alloy or Promtail available in package repos

## Target VMs (from inventory)
| Host | IP | Group |
|------|-----|-------|
| k8cluster1 | 192.168.1.90 | k8s |
| k8cluster2 | 192.168.1.89 | k8s |
| k8cluster3 | 192.168.1.91 | k8s |
| nginx1 | 192.168.1.92 | lb |
| nginx2 | 192.168.1.93 | lb |
| cmd_center1 | 192.168.1.88 | cmd_center |

**Additional VMs to add to inventory:**
| Host | IP | Group |
|------|-----|-------|
| grafana | 192.168.1.x | monitoring |
| elastic | 192.168.1.x | databases |
| timescaledb | 192.168.1.x | databases |
| npm | 192.168.1.x | services |
| ad | 192.168.1.x | windows (skip for now) |

## Implementation Steps

### Step 1: Update Ansible inventory
Add new hosts and groups to `inventory.ini`:

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
grafana ansible_host=192.168.1.103

[databases]
elastic ansible_host=192.168.1.x
timescaledb ansible_host=192.168.1.x

[services]
npm ansible_host=192.168.1.x

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

### Step 3: Create Grafana Alloy role for log collection
**Directory structure:**
```
roles/
└── alloy/
    ├── tasks/
    │   └── main.yml
    ├── handlers/
    │   └── main.yml
    ├── templates/
    │   └── config.alloy.j2
    └── defaults/
        └── main.yml
```

**tasks/main.yml:**
```yaml
---
- name: Add Grafana GPG key
  apt_key:
    url: https://apt.grafana.com/gpg.key
    state: present

- name: Add Grafana repository
  apt_repository:
    repo: "deb https://apt.grafana.com stable main"
    state: present

- name: Install Alloy
  apt:
    name: alloy
    state: present
    update_cache: yes

- name: Configure Alloy
  template:
    src: config.alloy.j2
    dest: /etc/alloy/config.alloy
  notify: Restart alloy

- name: Enable and start Alloy
  systemd:
    name: alloy
    enabled: yes
    state: started
```

**templates/config.alloy.j2:**
```hcl
// Scrape local node_exporter
prometheus.scrape "node" {
  targets = [{"__address__" = "localhost:9100"}]
  forward_to = [prometheus.remote_write.default.receiver]

  scrape_interval = "15s"
}

// Remote write to Prometheus
prometheus.remote_write "default" {
  endpoint {
    url = "{{ prometheus_remote_write_url }}"
  }
}

// Collect local logs
local.file_match "logs" {
  path_targets = [
    {"__path__" = "/var/log/*.log"},
    {"__path__" = "/var/log/syslog"},
    {"__path__" = "/var/log/auth.log"},
  ]
}

loki.source.file "logs" {
  targets    = local.file_match.logs.targets
  forward_to = [loki.write.default.receiver]

  tail_from_end = true
}

// Add host label
loki.process "add_labels" {
  stage.static_labels {
    values = {
      host = "{{ inventory_hostname }}",
    }
  }
  forward_to = [loki.write.default.receiver]
}

// Send to Loki
loki.write "default" {
  endpoint {
    url = "{{ loki_push_url }}"
  }
}
```

**defaults/main.yml:**
```yaml
prometheus_remote_write_url: "http://192.168.1.230:9090/api/v1/write"
loki_push_url: "http://192.168.1.231:3100/loki/api/v1/push"
```

### Step 4: Create monitoring playbook
**playbooks/monitoring.yml:**
```yaml
---
- name: Deploy monitoring agents to all Linux VMs
  hosts: linux
  become: yes
  roles:
    - node_exporter
    - alloy
  vars:
    prometheus_remote_write_url: "http://prometheus.quasarlab.local:9090/api/v1/write"
    loki_push_url: "http://loki.quasarlab.local:3100/loki/api/v1/push"
```

### Step 5: Update site.yml
Add monitoring playbook to site.yml:
```yaml
---
- import_playbook: playbooks/monitoring.yml
  tags: [monitoring]
```

## Validation Steps
1. Run playbook: `ansible-playbook -i inventory.ini playbooks/monitoring.yml --check`
2. Apply: `ansible-playbook -i inventory.ini playbooks/monitoring.yml`
3. Verify node_exporter: `curl http://<vm-ip>:9100/metrics`
4. Verify Alloy status: `systemctl status alloy`
5. Check Prometheus targets show VMs as UP
6. Query Loki for `{host="nginx1"}` logs

## Files Summary
```
ansible-quasarlab/
├── inventory.ini (updated)
├── playbooks/
│   └── monitoring.yml (new)
├── roles/
│   ├── node_exporter/ (new)
│   │   ├── tasks/main.yml
│   │   ├── handlers/main.yml
│   │   ├── templates/node_exporter.service.j2
│   │   └── defaults/main.yml
│   └── alloy/ (new)
│       ├── tasks/main.yml
│       ├── handlers/main.yml
│       ├── templates/config.alloy.j2
│       └── defaults/main.yml
└── site.yml (updated)
```

## Estimated Complexity
- Medium
- Standard Ansible role development

## Dependencies
- Workstream A must provide Prometheus/Loki endpoints
- Workstream D for Grafana datasource configuration
