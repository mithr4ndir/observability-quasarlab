# Workstream A: Kubernetes Monitoring Stack

## Objective
Deploy a complete metrics and logging stack in Kubernetes via ArgoCD, including Prometheus, Loki, and supporting components.

## Target Repository
`~/code/k8s-argocd`

## Prerequisites
- ArgoCD is already running in the cluster
- MetalLB is configured for LoadBalancer services
- NFS provisioner is available for persistent storage

## Architecture Overview
```
Prometheus (metrics) ──┐
                       ├──► Grafana VM (192.168.1.x)
Loki (logs) ──────────┘
     ▲
     │
Promtail (log collector, DaemonSet)
```

## Implementation Steps

### Step 1: Create monitoring namespace and ArgoCD project
Create `infrastructure/monitoring/` directory in k8s-argocd repo.

**Files to create:**
- `infrastructure/monitoring/namespace.yaml`
- `infrastructure/monitoring/argocd-project.yaml`

### Step 2: Deploy kube-prometheus-stack
Use the kube-prometheus-stack Helm chart which includes:
- Prometheus Operator
- Prometheus
- Alertmanager
- kube-state-metrics
- node-exporter (as DaemonSet)
- Grafana (disable - we use external)

**Files to create:**
- `infrastructure/monitoring/kube-prometheus-stack/Chart.yaml`
- `infrastructure/monitoring/kube-prometheus-stack/values.yaml`

**Key values.yaml configuration:**
```yaml
prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: nfs-client
          resources:
            requests:
              storage: 50Gi
    # Remote write to external Grafana/Mimir if desired
    externalLabels:
      cluster: quasarlab-k8s

grafana:
  enabled: false  # Using external Grafana VM

alertmanager:
  enabled: true
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: nfs-client
          resources:
            requests:
              storage: 5Gi

nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true
```

### Step 3: Deploy Loki for log aggregation
**Files to create:**
- `infrastructure/monitoring/loki/Chart.yaml`
- `infrastructure/monitoring/loki/values.yaml`

**Key configuration:**
```yaml
loki:
  auth_enabled: false
  storage:
    type: filesystem
  schemaConfig:
    configs:
      - from: 2024-01-01
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: index_
          period: 24h

singleBinary:
  replicas: 1
  persistence:
    enabled: true
    storageClass: nfs-client
    size: 50Gi
```

### Step 4: Deploy Promtail as DaemonSet
**Files to create:**
- `infrastructure/monitoring/promtail/Chart.yaml`
- `infrastructure/monitoring/promtail/values.yaml`

**Key configuration:**
```yaml
config:
  clients:
    - url: http://loki:3100/loki/api/v1/push

  snippets:
    pipelineStages:
      - cri: {}
    scrapeConfigs: |
      - job_name: kubernetes-pods
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_namespace]
            target_label: namespace
          - source_labels: [__meta_kubernetes_pod_name]
            target_label: pod
          - source_labels: [__meta_kubernetes_pod_container_name]
            target_label: container
```

### Step 5: Create ArgoCD Application manifests
**Files to create:**
- `infrastructure/monitoring/application.yaml` (App of Apps pattern)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring
  namespace: argocd
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/mithr4ndir/k8s-argocd.git
    targetRevision: HEAD
    path: infrastructure/monitoring
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Step 6: Expose services for external Grafana
Create Services/Ingress so the external Grafana VM can scrape Prometheus and query Loki.

**Option A: LoadBalancer services**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: prometheus-external
  namespace: monitoring
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.1.230  # Reserve IP in MetalLB
  ports:
    - port: 9090
  selector:
    app.kubernetes.io/name: prometheus
```

**Option B: Use nginx LB (existing)**
Add upstream configs to nginx1/nginx2.

## Validation Steps
1. `kubectl get pods -n monitoring` - All pods running
2. `kubectl port-forward svc/prometheus 9090:9090 -n monitoring` - Access Prometheus UI
3. Query `up` metric in Prometheus - Should show all targets
4. `kubectl port-forward svc/loki 3100:3100 -n monitoring` - Access Loki
5. Query `{namespace="media"}` in Loki - Should show logs

## Files Summary
```
k8s-argocd/
└── infrastructure/
    └── monitoring/
        ├── namespace.yaml
        ├── application.yaml
        ├── kube-prometheus-stack/
        │   ├── Chart.yaml
        │   └── values.yaml
        ├── loki/
        │   ├── Chart.yaml
        │   └── values.yaml
        └── promtail/
            ├── Chart.yaml
            └── values.yaml
```

## Estimated Complexity
- Medium-High
- Requires understanding of Helm, ArgoCD, and Prometheus ecosystem

## Dependencies
- Workstream D (Grafana datasource configuration) should be coordinated
