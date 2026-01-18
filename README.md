# Observability Stack for QuasarLab

This repository contains the observability configuration for the QuasarLab homelab infrastructure, including metrics, logs, and dashboards for both the Kubernetes plane and Proxmox hypervisor plane.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                   GRAFANA (192.168.1.121)                       │
│                   Dashboards & Alerting                         │
└─────────────────────────────────────────────────────────────────┘
                    ▲                         ▲
                    │                         │
        ┌───────────┴───────────┐   ┌────────┴────────────┐
        │     PROMETHEUS        │   │    ELASTICSEARCH    │
        │   (K8s: monitoring)   │   │   (192.168.1.167)   │
        │       metrics         │   │       logs          │
        └───────────────────────┘   └─────────────────────┘
                    ▲                         ▲
    ┌───────────────┼─────────────────────────┼───────────────┐
    │               │                         │               │
┌───┴───┐     ┌─────┴─────┐           ┌───────┴───────┐  ┌────┴────┐
│  PVE  │     │   K8s     │           │  Filebeat     │  │Filebeat │
│Exporter│    │  Metrics  │           │  (VMs)        │  │  (K8s)  │
└───────┘     └───────────┘           └───────────────┘  └─────────┘
    │               │                         │               │
┌───┴───┐     ┌─────┴─────┐           ┌───────┴───────┐  ┌────┴────┐
│Proxmox│     │Kubernetes │           │   All VMs     │  │All Pods │
│Cluster│     │  Cluster  │           │(node_exporter)│  │         │
└───────┘     └───────────┘           └───────────────┘  └─────────┘
```

## Workstreams

| Workstream | Description | Repository | Status |
|------------|-------------|------------|--------|
| [A: K8s Monitoring](plans/A-k8s-monitoring.md) | Prometheus + Loki in K8s via ArgoCD | k8s-argocd | Planned |
| [B: VM Monitoring](plans/B-vm-monitoring.md) | node_exporter + Alloy via Ansible | ansible-quasarlab | Planned |
| [C: Proxmox Metrics](plans/C-proxmox-metrics.md) | pve-exporter on PVE hosts | ansible-quasarlab | Planned |
| [D: Grafana Dashboards](plans/D-grafana-dashboards.md) | Dashboards as code | observability-quasarlab | Planned |

## Quick Start

### Prerequisites
- Kubernetes cluster with ArgoCD
- Ansible configured with inventory
- SSH access to all hosts

### Deployment Order
1. **Workstream A** - Deploy Prometheus and Loki to K8s
2. **Workstream C** - Deploy PVE exporter (can run parallel with A)
3. **Workstream B** - Deploy VM monitoring agents (needs Prometheus endpoint from A)
4. **Workstream D** - Configure Grafana datasources and dashboards (needs all above)

## Infrastructure Summary

### Proxmox Cluster
| Host | IP | RAM | Status |
|------|-----|-----|--------|
| pve | 192.168.1.10 | 128 GB | Primary |
| pve2 | 192.168.1.11 | 128 GB | Secondary |

### Virtual Machines
| VM | VMID | Host | RAM | Purpose |
|----|------|------|-----|---------|
| elastic | 102 | pve | 64 GB | Elasticsearch |
| k8cluster1 | 110 | pve | 16 GB | K8s control-plane |
| k8cluster2 | 109 | pve2 | 16 GB | K8s control-plane |
| k8cluster3 | 111 | pve | 16 GB | K8s control-plane |
| grafana | 103 | pve | 8 GB | Monitoring dashboards |
| timescaleDB | 104 | pve | 6 GB | Time-series DB |
| command-center1 | 105 | pve | 16 GB | Admin workstation |
| ad | 108 | pve | 8 GB | Active Directory |
| npm | 100 | pve | 6 GB | Nginx Proxy Manager |
| nginx1 | 112 | pve | 4 GB | Load balancer |
| nginx2 | 113 | pve | 4 GB | Load balancer |

### Kubernetes Namespaces
| Namespace | Workloads |
|-----------|-----------|
| argocd | GitOps deployment |
| media | Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent |
| metallb-system | Load balancer |
| nfs | Storage provisioner |
| trading | Trading bots (scaled to 0) |

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
│       ├── kubernetes/
│       ├── proxmox/
│       └── vms/
├── alerting/
│   └── rules/
└── ansible/
    └── deploy-grafana-config.yml
```

## Related Repositories

- **ansible-quasarlab** - Ansible playbooks for VM configuration
- **k8s-argocd** - Kubernetes manifests for ArgoCD
- **terraform-quasarlab** - Infrastructure as code for VM provisioning

## Metrics Endpoints (After Deployment)

| Service | Endpoint | Port |
|---------|----------|------|
| Prometheus (K8s) | 192.168.1.230 | 9090 |
| Elasticsearch | 192.168.1.167 | 9200 |
| Kibana | 192.168.1.167 | 5601 |
| Grafana | 192.168.1.121 | 3000 |
| PVE Exporter (pve) | 192.168.1.10 | 9221 |
| PVE Exporter (pve2) | 192.168.1.11 | 9221 |
| node_exporter (all VMs) | <vm-ip> | 9100 |

## VM IP Reference

| VM | VMID | IP |
|----|------|-----|
| npm | 100 | 192.168.1.150 |
| elastic | 102 | 192.168.1.167 |
| grafana | 103 | 192.168.1.121 |
| timescaleDB | 104 | 192.168.1.122 |
| command-center1 | 105 | 192.168.1.88 |
| ad | 108 | 192.168.1.67 |
| k8cluster1 | 110 | 192.168.1.90 |
| k8cluster3 | 111 | 192.168.1.91 |
| nginx1 | 112 | 192.168.1.92 |
| nginx2 | 113 | 192.168.1.93 |
