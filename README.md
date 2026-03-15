# Observability Stack for QuasarLab

This repository contains the observability configuration for the QuasarLab homelab infrastructure, including metrics, logs, alerting, and dashboards for both the Kubernetes plane and Proxmox hypervisor plane.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                   GRAFANA (192.168.1.121)                       │
│                   Dashboards & Visualization                    │
└─────────────────────────────────────────────────────────────────┘
                    ▲                         ▲
                    │                         │
        ┌───────────┴───────────┐   ┌────────┴────────────┐
        │     PROMETHEUS        │   │    ELASTICSEARCH    │
        │   (K8s: monitoring)   │   │   (192.168.1.167)   │
        │       metrics         │   │       logs          │
        └───────────┬───────────┘   └─────────────────────┘
                    │                         ▲
                    ▼                         │
        ┌───────────────────────┐   ┌────────┴────────────┐
        │    ALERTMANAGER       │   │     FILEBEAT        │
        │  (K8s: monitoring)    │   │   (All VMs + K8s)   │
        └───────────┬───────────┘   └─────────────────────┘
                    │
                    ▼
        ┌───────────────────────┐
        │  DISCORD ALERT PROXY  │       ┌──────────────┐
        │  (K8s: monitoring)    │──────▶│   DISCORD    │
        │  LOTR/SW themed       │       │   #alerts    │
        └───────────────────────┘       └──────────────┘
```

## Alerting Pipeline

Alerts flow through: **Prometheus** (evaluates rules) → **Alertmanager** (routes, groups, deduplicates) → **Discord Alert Proxy** (themed embeds) → **Discord**

### Alert Severity Tiers

| Severity | Color | Theme | Examples |
|----------|-------|-------|----------|
| Critical | Red | LOTR (Balrog, Mordor) + ASCII art | NodeDown, GPU failures |
| Warning | Orange | Star Wars quotes | ServiceDown, PlaybookFailed, RebootRequired |
| Info | Blue | LOTR/SW change quotes | AnsiblePlaybookMadeChanges |
| Resolved | Green | LOTR positive | Auto-sent when alerts clear |

### Alert Rules (managed in k8s-argocd)

| Alert | Severity | Condition |
|-------|----------|-----------|
| AnsiblePlaybookFailed | warning | `ansible_playbook_success == 0` for 5m |
| AnsibleRunStale | warning | Last run > 1 hour ago |
| AnsiblePlaybookMadeChanges | info | `ansible_playbook_changed_tasks > 0` |
| NodeDown | critical | Proxmox node unreachable |
| PveGuestDown | warning | VM not running |
| ServiceDown / ServiceInactive | warning | Monitored service offline |
| RebootRequired | warning | `/var/run/reboot-required` exists |
| SecurityUpdatesPending | warning | Pending security packages |

### Alertmanager Routing

- Default receiver: `discord` (via webhook proxy)
- Watchdog / InfoInhibitor: suppressed (`null` receiver)
- NodeDown: grouped by hypervisor, 1m wait, 1h repeat
- PveGuestDown: grouped by node, 1m wait
- ServiceDown: grouped by instance, 1m wait, 1h repeat
- AnsiblePlaybookMadeChanges: grouped by alertname, 2m wait (batches all playbooks from one cron run), 4h repeat
- Critical: 1h repeat

### Discord Alert Proxy

Runs in K8s (`monitoring` namespace). Converts Alertmanager webhooks into themed Discord embeds with message tracking (edits existing messages on update, cleans up on resolve).

- Webhook URL stored in 1Password, fetched via ExternalSecret
- Source: `k8s-argocd/infrastructure/monitoring/discord-alert-proxy/`

## Workstreams

| Workstream | Description | Repository | Status |
|------------|-------------|------------|--------|
| [A: K8s Monitoring](plans/A-k8s-monitoring.md) | Prometheus + Loki in K8s via ArgoCD | k8s-argocd | Complete |
| [B: VM Monitoring](plans/B-vm-monitoring.md) | node_exporter + Filebeat via Ansible | ansible-quasarlab | Complete |
| [C: Proxmox Metrics](plans/C-proxmox-metrics.md) | pve-exporter on PVE hosts | ansible-quasarlab | Complete |
| [D: Grafana Dashboards](plans/D-grafana-dashboards.md) | Dashboards as code | observability-quasarlab | Complete |

## Infrastructure Summary

### Proxmox Cluster
| Host | IP | RAM | Status |
|------|-----|-----|--------|
| pve | 192.168.1.10 | 128 GB | Primary |
| pve2 | 192.168.1.11 | 128 GB | Secondary |

### Virtual Machines
| VM | VMID | Host | IP | RAM | Purpose |
|----|------|------|----|-----|---------|
| npm | 100 | pve | 192.168.1.150 | 6 GB | Nginx Proxy Manager |
| elastic | 102 | pve | 192.168.1.167 | 64 GB | Elasticsearch |
| grafana | 103 | pve | 192.168.1.121 | 8 GB | Monitoring dashboards |
| timescaleDB | 104 | pve | 192.168.1.122 | 6 GB | Time-series DB |
| command-center1 | 105 | pve2 | 192.168.1.88 | 16 GB | Ansible controller |
| ad | 108 | pve | 192.168.1.67 | 8 GB | Active Directory |
| k8cluster1 | 110 | pve | 192.168.1.90 | 16 GB | K8s control-plane |
| k8cluster2 | 109 | pve2 | 192.168.1.89 | 16 GB | K8s control-plane |
| k8cluster3 | 111 | pve | 192.168.1.91 | 16 GB | K8s control-plane |
| nginx1 | 112 | pve | 192.168.1.92 | 4 GB | Load balancer |
| nginx2 | 113 | pve | 192.168.1.93 | 4 GB | Load balancer |
| jellyfin | 115 | pve2 | 192.168.1.170 | 12 GB | Media server (GPU passthrough) |

### Kubernetes Namespaces
| Namespace | Workloads |
|-----------|-----------|
| argocd | GitOps deployment |
| monitoring | Prometheus, Alertmanager, Discord alert proxy |
| metallb-system | Load balancer |
| nfs | Storage provisioner |

## Dashboards

| Dashboard | Path | Description |
|-----------|------|-------------|
| Ansible Runs | `grafana/dashboards/ansible/ansible-runs.json` | Playbook success/failure, changed tasks, drift tracking |
| Jellyfin | `grafana/dashboards/vms/jellyfin.json` | GPU stats, streams, watchdog, NAS storage |
| Proxmox Cluster | `grafana/dashboards/proxmox/` | Node health, VM status, storage |
| Kubernetes | `grafana/dashboards/kubernetes/` | Pod resources, node metrics |

## Directory Structure

```
observability-quasarlab/
├── README.md
├── plans/                          # Implementation plans
│   ├── A-k8s-monitoring.md
│   ├── B-vm-monitoring.md
│   ├── C-proxmox-metrics.md
│   └── D-grafana-dashboards.md
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yaml
│   │   └── dashboards/
│   │       └── dashboards.yaml
│   └── dashboards/
│       ├── ansible/
│       ├── kubernetes/
│       ├── proxmox/
│       └── vms/
├── alerting/
│   └── rules/
└── ansible/
    └── deploy-grafana-config.yml
```

## Related Repositories

| Repository | Purpose |
|------------|---------|
| **ansible-quasarlab** | Ansible playbooks for VM configuration, monitoring agents, GPU watchdog |
| **k8s-argocd** | Kubernetes manifests — kube-prometheus-stack, Alertmanager config, Discord alert proxy |
| **terraform-quasarlab** | Infrastructure as code for VM provisioning |
| **observability-quasarlab** | This repo — Grafana dashboards and provisioning config |

## Metrics Endpoints

| Service | Endpoint | Port |
|---------|----------|------|
| Prometheus (K8s) | 192.168.1.230 | 9090 |
| Alertmanager (K8s) | Internal | 9093 |
| Discord Alert Proxy (K8s) | Internal | 9095 |
| Elasticsearch | 192.168.1.167 | 9200 |
| Kibana | 192.168.1.167 | 5601 |
| Grafana | 192.168.1.121 | 3000 |
| PVE Exporter (pve) | 192.168.1.10 | 9221 |
| PVE Exporter (pve2) | 192.168.1.11 | 9221 |
| node_exporter (all VMs) | \<vm-ip\> | 9100 |
