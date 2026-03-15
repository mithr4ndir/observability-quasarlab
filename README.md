# observability-quasarlab — QuasarLab Monitoring & Dashboards

Grafana dashboards, datasource provisioning, and observability documentation for a Proxmox-based homelab. Covers metrics (Prometheus), logs (Loki + Vector), security (Wazuh), and alerting (Discord).

## Architecture

```
                        ┌──────────────────────────┐
                        │   GRAFANA (192.168.1.121) │
                        │   Dashboards & Explore    │
                        └─────┬──────────┬──────────┘
                              │          │
               ┌──────────────┘          └──────────────┐
               ▼                                        ▼
    ┌─────────────────────┐                  ┌─────────────────────┐
    │     PROMETHEUS      │                  │        LOKI         │
    │  (192.168.1.230)    │                  │   (192.168.1.231)   │
    │     metrics         │                  │       logs          │
    └─────────┬───────────┘                  └──────────┬──────────┘
              │                                         ▲
              ▼                                         │
    ┌─────────────────────┐                  ┌──────────┴──────────┐
    │    ALERTMANAGER     │                  │       VECTOR        │
    │  (K8s: monitoring)  │                  │  DaemonSet + Agents │
    └─────────┬───────────┘                  │  + Aggregator       │
              │                              └─────────────────────┘
              ▼
    ┌─────────────────────┐       ┌──────────────┐
    │  DISCORD ALERT PROXY│──────▶│   DISCORD    │
    │  LOTR/SW themed     │       │   #alerts    │
    └─────────────────────┘       └──────────────┘

    ┌─────────────────────────────────────────────┐
    │              WAZUH (192.168.1.171)           │
    │  Manager + Indexer + Dashboard (SIEM)        │
    │  13 agents across all Linux hosts            │
    └─────────────────────────────────────────────┘
```

## Log Pipeline (Loki + Vector)

Replaced the previous ELK stack (Elasticsearch + Filebeat) as of March 2026.

- **VM logs:** Vector agent on all 14 VMs ships journald + `/var/log/**/*.log` to Loki
- **K8s logs:** Vector DaemonSet collects container logs (excludes kube-system/monitoring)
- **External:** Vector Aggregator (`192.168.1.232`) accepts syslog/agent ingestion
- **Retention:** 30 days, 50Gi storage on k8s-nfs
- **Query:** Grafana Explore with LogQL

## Security (Wazuh SIEM)

- All-in-one VM: Manager + Indexer (OpenSearch) + Dashboard
- 13 agents across linux, kubernetes, and proxmox groups
- Dashboard at `192.168.1.171:5601`

## Alerting

Alerts flow: **Prometheus** (rules) → **Alertmanager** (routing) → **Discord Alert Proxy** (themed embeds) → **Discord**

| Severity | Color | Theme |
|----------|-------|-------|
| Critical | Red | LOTR (Balrog, Mordor) |
| Warning | Orange | Star Wars quotes |
| Info | Blue | LOTR/SW change quotes |
| Resolved | Green | LOTR positive |

### Alert Rules

| Alert | Severity | Trigger |
|-------|----------|---------|
| PveQuorumDegraded | warning | Cluster quorum votes below expected |
| PveQuorumLost | critical | Cluster lost quorum entirely |
| NodeDown | critical | Proxmox node unreachable |
| PveGuestDown | warning | VM with autostart is down |
| PveHighCpu / PveHighMemory | warning | Node resource > 90% |
| ServiceDown / ServiceInactive | warning | Monitored systemd unit offline |
| RebootRequired | warning | Pending reboot after patching |
| SecurityUpdatesPending | warning | Pending security packages |
| AnsiblePlaybookFailed | warning | Playbook returned failure |
| AnsibleRunStale | warning | No Ansible run in > 1 hour |

## Dashboards

| Dashboard | Path | Description |
|-----------|------|-------------|
| QuasarLab Overview | `grafana/dashboards/vms/quasarlab-overview.json` | High-level lab status |
| Jellyfin | `grafana/dashboards/vms/jellyfin.json` | GPU stats, active streams, watchdog, NAS storage |
| VM Log Explorer | `grafana/dashboards/vms/loki-logs.json` | LogQL browser (host/log_type/app filters) |
| Node Exporter Full | `grafana/dashboards/vms/node-exporter-full.json` | Detailed host metrics |
| K8s Cluster Overview | `grafana/dashboards/kubernetes/cluster-overview.json` | Cluster health |
| K8s Node Metrics | `grafana/dashboards/kubernetes/node-metrics.json` | Per-node resources |
| K8s Pod Metrics | `grafana/dashboards/kubernetes/pod-metrics.json` | Per-pod resources |
| K8s Workloads | `grafana/dashboards/kubernetes/workloads.json` | Deployment/StatefulSet status |
| K8s Log Explorer | `grafana/dashboards/kubernetes/k8s-logs.json` | K8s logs via LogQL |
| Proxmox Cluster | `grafana/dashboards/proxmox/cluster-overview.json` | Cluster health |
| Proxmox Nodes | `grafana/dashboards/proxmox/nodes-overview.json` | Per-node metrics |
| Proxmox VMs | `grafana/dashboards/proxmox/vms-overview.json` | VM status overview |
| Proxmox VM Metrics | `grafana/dashboards/proxmox/vm-metrics.json` | Per-VM detail |
| Proxmox Storage | `grafana/dashboards/proxmox/storage-metrics.json` | Pool usage |
| Ansible Runs | `grafana/dashboards/ansible/ansible-runs.json` | Playbook success, drift tracking |

## Infrastructure

### Proxmox Cluster
| Host | IP | RAM |
|------|----|-----|
| pve | 192.168.1.10 | 128 GB |
| pve2 | 192.168.1.11 | 128 GB |

### Virtual Machines
| VM | IP | Purpose |
|----|----|---------|
| jellyfin | 192.168.1.170 | Media server (GPU passthrough) |
| grafana | 192.168.1.121 | Dashboards |
| wazuh | 192.168.1.171 | SIEM |
| npm | 192.168.1.150 | Reverse proxy |
| timescaledb | 192.168.1.122 | Time-series DB |
| command-center1 | 192.168.1.88 | Management |
| k8cluster1-3 | 192.168.1.89-91 | Kubernetes |
| nginx1-2 | 192.168.1.92-93 | Load balancers |
| TrueNAS | 192.168.1.15 | NAS (NFS + iSCSI) |

### Metrics Endpoints
| Service | Endpoint | Port |
|---------|----------|------|
| Prometheus | 192.168.1.230 | 9090 |
| Loki | 192.168.1.231 | 3100 |
| Vector Aggregator | 192.168.1.232 | 5514/6000 |
| Grafana | 192.168.1.121 | 3000 |
| Wazuh Dashboard | 192.168.1.171 | 5601 |
| PVE Exporter | 192.168.1.10-11 | 9221 |
| node_exporter | all VMs | 9100 |

## Related Repos

| Repository | Purpose |
|------------|---------|
| [k8s-argocd](https://github.com/mithr4ndir/k8s-argocd) | Kubernetes manifests — Prometheus stack, Loki, Vector, alert proxy, alert rules |
| [ansible-quasarlab](https://github.com/mithr4ndir/ansible-quasarlab) | VM agents (node_exporter, Vector, Wazuh), Jellyfin, PVE exporters |
| [terraform-quasarlab](https://github.com/mithr4ndir/terraform-quasarlab) | VM provisioning on Proxmox |
