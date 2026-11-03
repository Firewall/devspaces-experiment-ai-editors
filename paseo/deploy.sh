#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=shared/deploy.sh
source "$REPO_ROOT/shared/deploy.sh"
load_config
PASEO_IMAGE="${PASEO_IMAGE:?Set PASEO_IMAGE in config.env}"
render_devfile "$REPO_ROOT/paseo/devfile.yaml" --check

echo "=== Deploying Paseo to namespace: $NAMESPACE ==="

# Step 1: Build and push
build_and_push_image "$PASEO_IMAGE" "$REPO_ROOT/paseo"

# Step 2: Create the direct route before startup. Paseo rejects Host headers
# that are not in its allowlist, and the Route host is only known at deploy time.
create_direct_route "paseo-direct" 6767 controller.devfile.io/devworkspace_name "paseo-workspace" "1h"

ROUTE_HOST=$(oc get route paseo-direct -n "$NAMESPACE" -o jsonpath='{.spec.host}')
PASEO_HOSTNAMES="$ROUTE_HOST"
export PASEO_HOSTNAMES

# Step 3: DevWorkspaceTemplate
create_editor_template "$REPO_ROOT/paseo/devfile.yaml" "paseo-editor"

# Step 4: DevWorkspace
create_workspace "paseo-workspace" "paseo-editor"

# Step 5: Wait for the workspace pod
wait_for_workspace "paseo-workspace" 300s

# Step 6: Wait for the daemon, then read its password.
echo "Waiting for Paseo to start..."
READY=""
for _ in $(seq 1 60); do
  if oc exec "$POD" -c paseo-runtime -n "$NAMESPACE" -- \
    curl -fsS http://127.0.0.1:6767/api/health >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 3
done

PASSWORD=$(oc exec "$POD" -c paseo-runtime -n "$NAMESPACE" -- \
  cat /projects/.devspaces-paseo/password.txt 2>/dev/null || true)

echo ""
echo "=== Paseo is ready ==="
echo ""
echo "URL:      https://${ROUTE_HOST}/"
if [ -n "$PASSWORD" ]; then
  echo "Password: ${PASSWORD}"
else
  echo "Password: Not ready yet. Run:"
  echo "          oc exec $POD -c paseo-runtime -n $NAMESPACE -- cat /projects/.devspaces-paseo/password.txt"
fi
echo ""
echo "Shell:    oc exec -it $POD -c paseo-runtime -n $NAMESPACE -- bash"
echo "Logs:     oc exec $POD -c paseo-runtime -n $NAMESPACE -- tail -n 200 /tmp/paseo-logs.txt"
echo ""
echo "Select a provider in Paseo and authenticate it in a workspace terminal."
if [ -z "$READY" ]; then
  echo ""
  echo "Paseo has not answered its health check yet; check the logs above."
fi
