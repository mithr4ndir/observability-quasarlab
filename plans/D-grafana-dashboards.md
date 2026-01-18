# Workstream D: Grafana Dashboards & Configuration

## Objective
Configure Grafana on the existing VM (192.168.1.103) with datasources and dashboards as code, covering both Kubernetes and Proxmox planes.

## Target Repository
`~/code/observability-quasarlab`

## Prerequisites
- Grafana VM running (192.168.1.121)
- Prometheus deployed (Workstream A)
- Elasticsearch running (192.168.1.167)
- PVE exporter running (Workstream C)

## Architecture
```
observability-quasarlab/
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yaml
│   │   └── dashboards/
│   │       └── dashboards.yaml
│   └── dashboards/
│       ├── kubernetes/
│       │   ├── cluster-overview.json
│       │   ├── node-metrics.json
│       │   ├── pod-metrics.json
│       │   └── namespace-resources.json
│       ├── proxmox/
│       │   ├── cluster-overview.json
│       │   ├── vm-metrics.json
│       │   └── storage-metrics.json
│       └── vms/
│           ├── node-exporter-full.json
│           └── elasticsearch-logs.json
├── alerting/
│   └── rules/
│       ├── kubernetes.yaml
│       ├── proxmox.yaml
│       └── infrastructure.yaml
└── ansible/
    └── deploy-grafana-config.yml
```

## Implementation Steps

### Step 1: Create datasources configuration
**grafana/provisioning/datasources/datasources.yaml:**
```yaml
apiVersion: 1

datasources:
  # Kubernetes Prometheus
  - name: Prometheus-K8s
    type: prometheus
    access: proxy
    url: http://192.168.1.230:9090
    isDefault: true
    editable: false
    jsonData:
      httpMethod: POST
      timeInterval: "15s"

  # Elasticsearch for logs
  - name: Elasticsearch
    type: elasticsearch
    access: proxy
    url: http://192.168.1.167:9200
    database: "[k8s-logs-]YYYY.MM.DD,[vm-logs-]YYYY.MM.DD"
    basicAuth: true
    basicAuthUser: elastic
    secureJsonData:
      basicAuthPassword: "${ELASTICSEARCH_PASSWORD}"
    jsonData:
      timeField: "@timestamp"
      esVersion: "8.0.0"
      logMessageField: message
      logLevelField: log.level

  # TimescaleDB (if you want to use it)
  - name: TimescaleDB
    type: postgres
    url: 192.168.1.122:5432
    database: metrics
    user: grafana
    secureJsonData:
      password: "${TIMESCALE_PASSWORD}"
    jsonData:
      sslmode: disable
      postgresVersion: 1500
      timescaledb: true
```

### Step 2: Create dashboard provisioning config
**grafana/provisioning/dashboards/dashboards.yaml:**
```yaml
apiVersion: 1

providers:
  - name: 'Kubernetes'
    orgId: 1
    folder: 'Kubernetes'
    folderUid: 'kubernetes'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 60
    options:
      path: /var/lib/grafana/dashboards/kubernetes

  - name: 'Proxmox'
    orgId: 1
    folder: 'Proxmox'
    folderUid: 'proxmox'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 60
    options:
      path: /var/lib/grafana/dashboards/proxmox

  - name: 'Infrastructure'
    orgId: 1
    folder: 'Infrastructure'
    folderUid: 'infrastructure'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 60
    options:
      path: /var/lib/grafana/dashboards/vms
```

### Step 3: Download/create community dashboards
Use well-tested community dashboards as a starting point:

**Kubernetes dashboards (from Grafana.com):**
- 15760 - Kubernetes Cluster Overview
- 15759 - Kubernetes Node Metrics
- 15758 - Kubernetes Pod Metrics
- 15757 - Kubernetes Namespace Resources

**Proxmox dashboard:**
- 10347 - Proxmox VE (for pve-exporter)

**Node Exporter dashboard:**
- 1860 - Node Exporter Full

**Script to download dashboards:**
```bash
#!/bin/bash
# download-dashboards.sh

DASHBOARDS=(
  "15760:kubernetes/cluster-overview.json"
  "15759:kubernetes/node-metrics.json"
  "15758:kubernetes/pod-metrics.json"
  "10347:proxmox/cluster-overview.json"
  "1860:vms/node-exporter-full.json"
)

for item in "${DASHBOARDS[@]}"; do
  ID="${item%%:*}"
  PATH="${item##*:}"

  echo "Downloading dashboard $ID to $PATH"
  curl -s "https://grafana.com/api/dashboards/$ID/revisions/latest/download" \
    | jq '.id = null | .uid = null' \
    > "grafana/dashboards/$PATH"
done
```

### Step 4: Create custom Proxmox VM dashboard
**grafana/dashboards/proxmox/vm-metrics.json:**
```json
{
  "title": "Proxmox VM Metrics",
  "uid": "proxmox-vms",
  "tags": ["proxmox", "vms"],
  "timezone": "browser",
  "panels": [
    {
      "title": "VM Memory Usage",
      "type": "table",
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 0},
      "targets": [
        {
          "expr": "sort_desc(pve_memory_usage_bytes / 1024 / 1024 / 1024)",
          "legendFormat": "{{name}} ({{node}})",
          "refId": "A"
        }
      ],
      "transformations": [
        {
          "id": "organize",
          "options": {
            "renameByName": {
              "Value": "Memory (GB)",
              "name": "VM Name",
              "node": "Node"
            }
          }
        }
      ]
    },
    {
      "title": "VM CPU Usage %",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
      "targets": [
        {
          "expr": "pve_cpu_usage_ratio * 100",
          "legendFormat": "{{name}}",
          "refId": "A"
        }
      ]
    },
    {
      "title": "VM Network I/O",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "targets": [
        {
          "expr": "rate(pve_network_transmit_bytes[5m])",
          "legendFormat": "{{name}} TX",
          "refId": "A"
        },
        {
          "expr": "rate(pve_network_receive_bytes[5m]) * -1",
          "legendFormat": "{{name}} RX",
          "refId": "B"
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "node",
        "type": "query",
        "query": "label_values(pve_node_info, node)",
        "multi": true,
        "includeAll": true
      }
    ]
  }
}
```

### Step 5: Create Ansible playbook to deploy configs
**ansible/deploy-grafana-config.yml:**
```yaml
---
- name: Deploy Grafana configuration
  hosts: grafana
  become: yes
  vars:
    grafana_provisioning_dir: /etc/grafana/provisioning
    grafana_dashboards_dir: /var/lib/grafana/dashboards
    repo_path: /home/ladino/code/observability-quasarlab

  tasks:
    - name: Create dashboard directories
      file:
        path: "{{ grafana_dashboards_dir }}/{{ item }}"
        state: directory
        owner: grafana
        group: grafana
        mode: '0755'
      loop:
        - kubernetes
        - proxmox
        - vms

    - name: Copy datasource configuration
      copy:
        src: "{{ repo_path }}/grafana/provisioning/datasources/"
        dest: "{{ grafana_provisioning_dir }}/datasources/"
        owner: grafana
        group: grafana
      notify: Restart grafana

    - name: Copy dashboard provisioning config
      copy:
        src: "{{ repo_path }}/grafana/provisioning/dashboards/"
        dest: "{{ grafana_provisioning_dir }}/dashboards/"
        owner: grafana
        group: grafana
      notify: Restart grafana

    - name: Copy Kubernetes dashboards
      copy:
        src: "{{ repo_path }}/grafana/dashboards/kubernetes/"
        dest: "{{ grafana_dashboards_dir }}/kubernetes/"
        owner: grafana
        group: grafana
      notify: Restart grafana

    - name: Copy Proxmox dashboards
      copy:
        src: "{{ repo_path }}/grafana/dashboards/proxmox/"
        dest: "{{ grafana_dashboards_dir }}/proxmox/"
        owner: grafana
        group: grafana
      notify: Restart grafana

    - name: Copy VM dashboards
      copy:
        src: "{{ repo_path }}/grafana/dashboards/vms/"
        dest: "{{ grafana_dashboards_dir }}/vms/"
        owner: grafana
        group: grafana
      notify: Restart grafana

  handlers:
    - name: Restart grafana
      systemd:
        name: grafana-server
        state: restarted
```

### Step 6: Create alerting rules
**alerting/rules/infrastructure.yaml:**
```yaml
apiVersion: 1

groups:
  - orgId: 1
    name: Infrastructure
    folder: Alerts
    interval: 1m
    rules:
      - uid: high-memory-vm
        title: High Memory Usage on VM
        condition: C
        data:
          - refId: A
            relativeTimeRange:
              from: 300
              to: 0
            model:
              expr: (1 - (node_memory_AvailableBytes / node_memory_MemTotal_bytes)) * 100
              refId: A
          - refId: C
            relativeTimeRange:
              from: 0
              to: 0
            model:
              conditions:
                - evaluator:
                    params: [85]
                    type: gt
                  operator:
                    type: and
                  query:
                    params: [A]
                  reducer:
                    type: avg
              refId: C
              type: classic_conditions
        for: 5m
        annotations:
          summary: "High memory on {{ $labels.instance }}"
        labels:
          severity: warning

      - uid: vm-down
        title: VM Down
        condition: C
        data:
          - refId: A
            model:
              expr: up{job="node"}
              refId: A
          - refId: C
            model:
              conditions:
                - evaluator:
                    params: [1]
                    type: lt
              type: classic_conditions
        for: 2m
        annotations:
          summary: "VM {{ $labels.instance }} is down"
        labels:
          severity: critical
```

## Validation Steps
1. Deploy configs: `ansible-playbook -i inventory.ini ansible/deploy-grafana-config.yml`
2. Access Grafana: `http://192.168.1.103:3000`
3. Verify datasources: Configuration → Data sources → Test each
4. Verify dashboards appear in folders
5. Check alerts: Alerting → Alert rules

## Files Summary
```
observability-quasarlab/
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yaml
│   │   └── dashboards/
│   │       └── dashboards.yaml
│   └── dashboards/
│       ├── kubernetes/
│       │   ├── cluster-overview.json
│       │   ├── node-metrics.json
│       │   └── pod-metrics.json
│       ├── proxmox/
│       │   ├── cluster-overview.json
│       │   └── vm-metrics.json
│       └── vms/
│           ├── node-exporter-full.json
│           └── elasticsearch-logs.json
├── alerting/
│   └── rules/
│       └── infrastructure.yaml
├── ansible/
│   └── deploy-grafana-config.yml
└── scripts/
    └── download-dashboards.sh
```

## Estimated Complexity
- Low-Medium
- Mainly configuration and JSON editing

## Dependencies
- Workstream A: Prometheus/Loki endpoints must be known
- Workstream B: VM node_exporter must be running for dashboards to show data
- Workstream C: PVE exporter must be running for Proxmox dashboards
