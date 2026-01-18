# Resume Context for Observability Project

**Created:** 2026-01-18
**Purpose:** Context dump for resuming after command-center1 VM migration

---

## What We Did

1. Investigated K8s cluster and Proxmox VMs for memory usage
2. Found PVE1 overloaded (~103GB/128GB), PVE2 underutilized (~21GB/128GB)
3. Discovered existing ELK stack at 192.168.1.167 (Elasticsearch, Kibana, Logstash)
4. Created observability plans for metrics + logs collection
5. Decided to use Elasticsearch (existing) instead of Loki (new)

---

## Your Existing Repos (Use These!)

| Repo | Purpose | Use For |
|------|---------|---------|
| `k8s-argocd` | K8s manifests, GitOps | Workstream A - Deploy Prometheus, Filebeat to K8s |
| `ansible-quasarlab` | Ansible playbooks | Workstream B & C - Deploy node_exporter, Filebeat, pve-exporter |
| `terraform-quasarlab` | VM provisioning | Reference for VM configs |
| `cosmic-observability` | Empty/unused | Ignore - nothing there |
| `observability-quasarlab` | New - plans only | Plans are here, implementation goes to other repos |

**Note:** `cosmic-observability` repo is empty/unused - ignore it.

---

## Infrastructure Summary

### Proxmox Cluster
| Host | IP | RAM Total | RAM Used | Status |
|------|-----|-----------|----------|--------|
| pve | 192.168.1.10 | 128 GB | ~103 GB | Overloaded |
| pve2 | 192.168.1.11 | 128 GB | ~21 GB | Underutilized |

### VM IP Reference
| VM | VMID | IP | Host | RAM |
|----|------|-----|------|-----|
| npm | 100 | 192.168.1.150 | pve | 6 GB |
| elastic | 102 | 192.168.1.167 | pve | 64 GB |
| grafana | 103 | 192.168.1.121 | pve | 8 GB |
| timescaleDB | 104 | 192.168.1.122 | pve | 6 GB |
| command-center1 | 105 | 192.168.1.88 | pve | 16 GB |
| ad | 108 | 192.168.1.67 | pve | 8 GB |
| k8cluster1 | 110 | 192.168.1.90 | pve | 16 GB |
| k8cluster2 | 109 | 192.168.1.89 | pve2 | 16 GB |
| k8cluster3 | 111 | 192.168.1.91 | pve | 16 GB |
| nginx1 | 112 | 192.168.1.92 | pve | 4 GB |
| nginx2 | 113 | 192.168.1.93 | pve | 4 GB |

### Services
| Service | IP:Port | Notes |
|---------|---------|-------|
| Elasticsearch | 192.168.1.167:9200 | Auth enabled |
| Kibana | 192.168.1.167:5601 | Running |
| Logstash | 192.168.1.167:5044 | Running |
| Grafana | 192.168.1.121:3000 | v12.1.1 |
| K8s API | 192.168.1.90:6443 | Via VIP at 192.168.1.20 |

### K8s Namespaces
- argocd - GitOps
- media - Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent (8GB!)
- metallb-system - Load balancer
- nfs - Storage provisioner
- trading - Scaled to 0

---

## Workstreams

### A: K8s Monitoring
- **Repo:** `k8s-argocd`
- **Plan:** `~/code/observability-quasarlab/plans/A-k8s-monitoring.md`
- **Deploy:** Prometheus + kube-state-metrics + Filebeat via ArgoCD
- **Dependencies:** None (can run parallel with C)

### B: VM Monitoring
- **Repo:** `ansible-quasarlab`
- **Plan:** `~/code/observability-quasarlab/plans/B-vm-monitoring.md`
- **Deploy:** node_exporter + Filebeat on all Linux VMs
- **Dependencies:** Needs Prometheus endpoint from A

### C: Proxmox Metrics
- **Repo:** `ansible-quasarlab`
- **Plan:** `~/code/observability-quasarlab/plans/C-proxmox-metrics.md`
- **Deploy:** pve-exporter on PVE hosts
- **Dependencies:** None (can run parallel with A)

### D: Grafana Dashboards
- **Repo:** `observability-quasarlab` (or merge into `cosmic-observability`)
- **Plan:** `~/code/observability-quasarlab/plans/D-grafana-dashboards.md`
- **Deploy:** Datasources + dashboards as code
- **Dependencies:** Needs A, B, C complete

---

## Architecture (Final)

```
┌────────────────────────────────────────────────────────────┐
│                GRAFANA (192.168.1.121)                     │
└────────────────────────────────────────────────────────────┘
                ▲                         ▲
                │                         │
    ┌───────────┴───────────┐   ┌────────┴────────────┐
    │     PROMETHEUS        │   │    ELASTICSEARCH    │
    │  (K8s: 192.168.1.230) │   │   (192.168.1.167)   │
    │      metrics          │   │       logs          │
    └───────────────────────┘   └─────────────────────┘
                ▲                         ▲
    ┌───────────┴───────────┐   ┌────────┴────────────┐
    │  • kube-state-metrics │   │  • Filebeat (K8s)   │
    │  • node-exporter (K8s)│   │  • Filebeat (VMs)   │
    │  • node-exporter (VMs)│   │  • Logstash (exist) │
    │  • pve-exporter       │   │                     │
    └───────────────────────┘   └─────────────────────┘
```

---

## Tmux Launcher Script

Save this to `~/bin/claude-observability.sh`:

```bash
#!/bin/bash
# Launches 4 Claude agents for observability workstreams
# Run after command-center1 migration is complete

SESSION="observability"
PLANS_DIR="$HOME/code/observability-quasarlab/plans"

# Kill existing session
tmux kill-session -t $SESSION 2>/dev/null

# Create 2x2 grid
tmux new-session -d -s $SESSION -c ~/code/k8s-argocd -n "agents"
tmux split-window -h -t $SESSION -c ~/code/ansible-quasarlab
tmux select-pane -t $SESSION:0.0
tmux split-window -v -t $SESSION -c ~/code/ansible-quasarlab
tmux select-pane -t $SESSION:0.2
tmux split-window -v -t $SESSION -c ~/code/observability-quasarlab

# Start agents with prompts
# Pane 0: Workstream A (K8s monitoring)
tmux send-keys -t $SESSION:0.0 "claude 'Read $PLANS_DIR/A-k8s-monitoring.md and implement it. This repo (k8s-argocd) is for K8s manifests deployed via ArgoCD. Create the monitoring namespace and deploy kube-prometheus-stack + filebeat. Check ~/code/cosmic-observability for any reusable configs first.'" Enter

# Pane 1: Workstream C (Proxmox metrics) - runs parallel with A
tmux send-keys -t $SESSION:0.2 "claude 'Read $PLANS_DIR/C-proxmox-metrics.md and implement it. This repo (ansible-quasarlab) has existing Ansible roles. Create a pve_exporter role and playbook. PVE hosts are 192.168.1.10 and 192.168.1.11.'" Enter

# Pane 2: Workstream B (VM monitoring) - after A provides prometheus endpoint
tmux send-keys -t $SESSION:0.1 "claude 'Read $PLANS_DIR/B-vm-monitoring.md and implement it. This repo (ansible-quasarlab) has existing roles. Create node_exporter and filebeat roles. Target all Linux VMs. Elasticsearch is at 192.168.1.167:9200.'" Enter

# Pane 3: Workstream D (Grafana dashboards)
tmux send-keys -t $SESSION:0.3 "claude 'Read $PLANS_DIR/D-grafana-dashboards.md and implement it. Check ~/code/cosmic-observability first - it may have existing dashboards to reuse. Create Grafana provisioning configs and dashboards for K8s, Proxmox, and VMs.'" Enter

echo "Tmux session '$SESSION' created. Attach with: tmux attach -t $SESSION"
tmux attach -t $SESSION
```

Make executable:
```bash
chmod +x ~/bin/claude-observability.sh
```

---

## Resume Instructions

After migrating command-center1:

1. **Run the tmux launcher:**
   ```bash
   ~/bin/claude-observability.sh
   ```

2. **Or run workstreams manually in separate terminals:**
   ```bash
   # Terminal 1 - A: K8s monitoring
   cd ~/code/k8s-argocd && claude

   # Terminal 2 - B: VM monitoring
   cd ~/code/ansible-quasarlab && claude

   # Terminal 3 - C: Proxmox metrics
   cd ~/code/ansible-quasarlab && claude

   # Terminal 4 - D: Grafana dashboards
   cd ~/code/observability-quasarlab && claude
   ```

3. **Dependency order:**
   - A + C can run in parallel (no dependencies)
   - B needs Prometheus endpoint from A
   - D needs all three complete

---

## Questions to Resolve After Migration

1. What's the Elasticsearch password? (needed for Filebeat)
2. Which MetalLB IP to reserve for Prometheus? (suggested 192.168.1.230)

---

## GitHub Repos

- https://github.com/mithr4ndir/observability-quasarlab (plans + dashboards)
- https://github.com/mithr4ndir/k8s-argocd (K8s manifests)
- https://github.com/mithr4ndir/ansible-quasarlab (Ansible playbooks)
- https://github.com/mithr4ndir/terraform-quasarlab (VM provisioning)
