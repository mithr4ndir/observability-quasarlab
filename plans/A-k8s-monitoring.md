# Workstream A: Kubernetes Monitoring Stack

## Objective
Deploy Prometheus metrics stack in Kubernetes via ArgoCD, plus Filebeat for shipping pod logs to the existing Elasticsearch cluster.

## Target Repository
`~/code/k8s-argocd`

## Prerequisites
- ArgoCD is already running in the cluster
- MetalLB is configured for LoadBalancer services
- NFS provisioner is available for persistent storage
- Elasticsearch running at 192.168.1.167:9200 (existing)

## Architecture Overview
```
Prometheus (metrics) ──► Grafana (192.168.1.121)
                              ▲
Filebeat ──► Elasticsearch ───┘
             (192.168.1.167)
```

## Implementation Steps

### Step 1: Create monitoring namespace and ArgoCD project
Create `infrastructure/monitoring/` directory in k8s-argocd repo.

**Files to create:**
- `infrastructure/monitoring/namespace.yaml`
- `infrastructure/monitoring/argocd-project.yaml`

**namespace.yaml:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    name: monitoring
```

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

**Chart.yaml:**
```yaml
apiVersion: v2
name: kube-prometheus-stack
version: 1.0.0
dependencies:
  - name: kube-prometheus-stack
    version: "65.x.x"  # Check latest
    repository: https://prometheus-community.github.io/helm-charts
```

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
    externalLabels:
      cluster: quasarlab-k8s
    # Enable remote write if you want to send to external Prometheus/Mimir
    # remoteWrite:
    #   - url: http://external-prometheus:9090/api/v1/write

grafana:
  enabled: false  # Using external Grafana VM at 192.168.1.121

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

# Scrape kubelet metrics
kubelet:
  enabled: true

# Scrape kube-proxy
kubeProxy:
  enabled: true
```

### Step 3: Deploy Filebeat for log shipping to Elasticsearch
**Files to create:**
- `infrastructure/monitoring/filebeat/Chart.yaml`
- `infrastructure/monitoring/filebeat/values.yaml`

**Chart.yaml:**
```yaml
apiVersion: v2
name: filebeat
version: 1.0.0
dependencies:
  - name: filebeat
    version: "8.x.x"  # Match your ES version
    repository: https://helm.elastic.co
```

**values.yaml:**
```yaml
daemonset:
  enabled: true

filebeatConfig:
  filebeat.yml: |
    filebeat.autodiscover:
      providers:
        - type: kubernetes
          node: ${NODE_NAME}
          hints.enabled: true
          hints.default_config:
            type: container
            paths:
              - /var/log/containers/*${data.kubernetes.container.id}.log

    processors:
      - add_kubernetes_metadata:
          host: ${NODE_NAME}
          matchers:
            - logs_path:
                logs_path: "/var/log/containers/"
      - drop_event:
          when:
            or:
              - equals:
                  kubernetes.namespace: "kube-system"
              - equals:
                  kubernetes.namespace: "monitoring"

    output.elasticsearch:
      hosts: ["192.168.1.167:9200"]
      username: "${ELASTICSEARCH_USERNAME}"
      password: "${ELASTICSEARCH_PASSWORD}"
      index: "k8s-logs-%{+yyyy.MM.dd}"

    setup.template.name: "k8s-logs"
    setup.template.pattern: "k8s-logs-*"
    setup.ilm.enabled: true
    setup.ilm.rollover_alias: "k8s-logs"
    setup.ilm.pattern: "{now/d}-000001"

extraEnvs:
  - name: NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: spec.nodeName
  - name: ELASTICSEARCH_USERNAME
    valueFrom:
      secretKeyRef:
        name: elasticsearch-credentials
        key: username
  - name: ELASTICSEARCH_PASSWORD
    valueFrom:
      secretKeyRef:
        name: elasticsearch-credentials
        key: password
```

### Step 4: Create Elasticsearch credentials secret
**Files to create:**
- `infrastructure/monitoring/filebeat/secret.yaml` (use sealed-secrets or external-secrets in production)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: elasticsearch-credentials
  namespace: monitoring
type: Opaque
stringData:
  username: elastic
  password: <your-elastic-password>  # Use sealed-secrets!
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
    syncOptions:
      - CreateNamespace=true
```

### Step 6: Expose Prometheus for external Grafana
Create LoadBalancer service so Grafana (192.168.1.121) can query Prometheus.

**Files to create:**
- `infrastructure/monitoring/prometheus-external-svc.yaml`

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
      targetPort: 9090
  selector:
    app.kubernetes.io/name: prometheus
    prometheus: kube-prometheus-stack-prometheus
```

## Validation Steps
1. `kubectl get pods -n monitoring` - All pods running
2. `kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoring` - Access Prometheus UI
3. Query `up` metric in Prometheus - Should show all targets
4. Check Kibana (192.168.1.167:5601) for `k8s-logs-*` index
5. In Grafana, add Prometheus datasource pointing to 192.168.1.230:9090

## Files Summary
```
k8s-argocd/
└── infrastructure/
    └── monitoring/
        ├── namespace.yaml
        ├── application.yaml
        ├── prometheus-external-svc.yaml
        ├── kube-prometheus-stack/
        │   ├── Chart.yaml
        │   └── values.yaml
        └── filebeat/
            ├── Chart.yaml
            ├── values.yaml
            └── secret.yaml
```

## Estimated Complexity
- Medium
- Requires understanding of Helm, ArgoCD, and Prometheus/Filebeat

## Dependencies
- Elasticsearch credentials needed for Filebeat
- Workstream D (Grafana datasource configuration) should be coordinated
