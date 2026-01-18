# Workstream C: Proxmox Hypervisor Metrics

## Objective
Deploy prometheus-pve-exporter on Proxmox hosts to collect hypervisor-level metrics including VM resource usage, storage, and cluster health.

## Target Repository
`~/code/ansible-quasarlab`

## Prerequisites
- SSH/root access to Proxmox hosts
- Proxmox API token or user credentials
- Prometheus deployed (Workstream A)

## Target Hosts
| Host | IP | Notes |
|------|-----|-------|
| pve | 192.168.1.10 | Primary PVE node |
| pve2 | 192.168.1.11 | Secondary PVE node |

## Metrics Exposed by PVE Exporter
- `pve_up` - PVE cluster health
- `pve_node_info` - Node metadata
- `pve_cpu_usage_ratio` - CPU utilization per VM
- `pve_memory_usage_bytes` - Memory usage per VM
- `pve_disk_read/write_bytes` - Disk I/O per VM
- `pve_network_receive/transmit_bytes` - Network I/O per VM
- `pve_guest_info` - VM metadata (name, vmid, status)
- `pve_storage_*` - Storage pool metrics

## Implementation Steps

### Step 1: Add Proxmox hosts to Ansible inventory
Update `inventory.ini`:
```ini
[proxmox]
pve ansible_host=192.168.1.10 ansible_user=root
pve2 ansible_host=192.168.1.11 ansible_user=root

[proxmox:vars]
ansible_python_interpreter=/usr/bin/python3
```

### Step 2: Create Proxmox API token
This can be done via Ansible or manually first.

**Manual steps (run on one PVE node):**
```bash
# Create user for monitoring
pveum user add prometheus@pve -comment "Prometheus monitoring"

# Create API token
pveum user token add prometheus@pve monitoring -privsep 0

# Grant read-only permissions
pveum aclmod / -user prometheus@pve -role PVEAuditor
```

**Or via Ansible task:**
```yaml
- name: Create Prometheus monitoring user
  command: pveum user add prometheus@pve -comment "Prometheus monitoring"
  ignore_errors: yes  # User may already exist

- name: Create API token
  command: pveum user token add prometheus@pve monitoring -privsep 0
  register: token_output

- name: Grant audit permissions
  command: pveum aclmod / -user prometheus@pve -role PVEAuditor
```

### Step 3: Create pve_exporter role
**Directory structure:**
```
roles/
└── pve_exporter/
    ├── tasks/
    │   └── main.yml
    ├── handlers/
    │   └── main.yml
    ├── templates/
    │   ├── pve_exporter.service.j2
    │   └── pve.yml.j2
    └── defaults/
        └── main.yml
```

**tasks/main.yml:**
```yaml
---
- name: Install pip3
  apt:
    name: python3-pip
    state: present

- name: Install prometheus-pve-exporter
  pip:
    name: prometheus-pve-exporter
    state: present

- name: Create config directory
  file:
    path: /etc/pve_exporter
    state: directory
    mode: '0700'

- name: Create PVE exporter config
  template:
    src: pve.yml.j2
    dest: /etc/pve_exporter/pve.yml
    mode: '0600'
  notify: Restart pve_exporter

- name: Create systemd service
  template:
    src: pve_exporter.service.j2
    dest: /etc/systemd/system/pve_exporter.service
  notify: Restart pve_exporter

- name: Enable and start pve_exporter
  systemd:
    name: pve_exporter
    enabled: yes
    state: started
    daemon_reload: yes
```

**templates/pve.yml.j2:**
```yaml
default:
  user: {{ pve_api_user }}
  token_name: {{ pve_api_token_name }}
  token_value: {{ pve_api_token_value }}
  verify_ssl: false
```

**templates/pve_exporter.service.j2:**
```ini
[Unit]
Description=Prometheus PVE Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/pve_exporter --config.file /etc/pve_exporter/pve.yml --web.listen-address=:{{ pve_exporter_port }}
Restart=always

[Install]
WantedBy=multi-user.target
```

**defaults/main.yml:**
```yaml
pve_exporter_port: 9221
pve_api_user: "prometheus@pve"
pve_api_token_name: "monitoring"
# pve_api_token_value should be in vault or group_vars
```

### Step 4: Create group_vars for Proxmox
**group_vars/proxmox.yml:**
```yaml
# Store token securely - use ansible-vault in production
pve_api_token_value: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### Step 5: Create playbook
**playbooks/proxmox-monitoring.yml:**
```yaml
---
- name: Deploy PVE exporter to Proxmox hosts
  hosts: proxmox
  become: yes
  roles:
    - pve_exporter
```

### Step 6: Add Prometheus scrape config
Add to Prometheus configuration (in Workstream A values.yaml):
```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'proxmox'
        static_configs:
          - targets:
            - '192.168.1.10:9221'
            - '192.168.1.11:9221'
        metrics_path: /pve
        params:
          module: [default]
          cluster: ['1']
          node: ['1']
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: localhost:9221  # PVE exporter address
```

**Alternative: ServiceMonitor for Prometheus Operator**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: Probe
metadata:
  name: proxmox
  namespace: monitoring
spec:
  jobName: proxmox
  prober:
    url: pve-exporter.monitoring.svc:9221
    path: /pve
  targets:
    staticConfig:
      static:
        - 192.168.1.10
        - 192.168.1.11
  scrapeTimeout: 30s
```

## Validation Steps
1. SSH to PVE host: `ssh root@192.168.1.10`
2. Check exporter: `curl http://localhost:9221/pve?target=localhost`
3. Verify metrics include VM data
4. Check Prometheus targets show PVE as UP
5. Query `pve_guest_info` in Prometheus

## Sample Queries
```promql
# Memory usage per VM (percentage)
pve_memory_usage_bytes / pve_memory_size_bytes * 100

# CPU usage per VM
pve_cpu_usage_ratio * 100

# VMs by memory usage (top 10)
topk(10, pve_memory_usage_bytes)

# Total cluster memory utilization
sum(pve_memory_usage_bytes) / sum(pve_memory_size_bytes) * 100
```

## Files Summary
```
ansible-quasarlab/
├── inventory.ini (updated - add proxmox group)
├── group_vars/
│   └── proxmox.yml (new)
├── playbooks/
│   └── proxmox-monitoring.yml (new)
└── roles/
    └── pve_exporter/ (new)
        ├── tasks/main.yml
        ├── handlers/main.yml
        ├── templates/
        │   ├── pve_exporter.service.j2
        │   └── pve.yml.j2
        └── defaults/main.yml
```

## Estimated Complexity
- Low-Medium
- Straightforward Ansible role, main complexity is API token setup

## Dependencies
- Workstream A must be ready to scrape the exporter
- Workstream D for Proxmox dashboard
