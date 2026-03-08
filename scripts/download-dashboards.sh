#!/bin/bash
# download-dashboards.sh
# Downloads popular community dashboards from Grafana.com
# These can be used as reference or imported directly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DASHBOARDS_DIR="$REPO_ROOT/grafana/dashboards"

# Create directories if they don't exist
mkdir -p "$DASHBOARDS_DIR/kubernetes"
mkdir -p "$DASHBOARDS_DIR/proxmox"
mkdir -p "$DASHBOARDS_DIR/vms"

# Dashboard IDs and their destinations
# Format: "ID:destination_path"
DASHBOARDS=(
  "15760:kubernetes/community-cluster-overview.json"   # Kubernetes Cluster Overview
  "15759:kubernetes/community-node-metrics.json"       # Kubernetes Node Metrics
  "15758:kubernetes/community-pod-metrics.json"        # Kubernetes Pod Metrics
  "15757:kubernetes/community-namespace-resources.json" # Kubernetes Namespace Resources
  "10347:proxmox/community-pve.json"                   # Proxmox VE
  "1860:vms/community-node-exporter-full.json"         # Node Exporter Full
)

echo "Downloading community dashboards from Grafana.com..."
echo ""

for item in "${DASHBOARDS[@]}"; do
  ID="${item%%:*}"
  DEST_PATH="${item##*:}"
  FULL_PATH="$DASHBOARDS_DIR/$DEST_PATH"

  echo "Downloading dashboard $ID to $DEST_PATH..."

  # Download and process the dashboard
  # - Set id to null (required for provisioning)
  # - Set uid to null (Grafana will auto-generate)
  curl -s "https://grafana.com/api/dashboards/$ID/revisions/latest/download" \
    | jq '.id = null | .uid = null' \
    > "$FULL_PATH"

  if [ -s "$FULL_PATH" ]; then
    echo "  ✓ Downloaded successfully"
  else
    echo "  ✗ Failed to download"
    rm -f "$FULL_PATH"
  fi
done

echo ""
echo "Download complete!"
echo ""
echo "Note: Community dashboards are saved with 'community-' prefix."
echo "The custom dashboards in this repo are the primary ones used for provisioning."
echo "Community dashboards can be imported manually through Grafana UI if needed."
