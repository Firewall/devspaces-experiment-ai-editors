#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=shared/deploy.sh
source "$REPO_ROOT/shared/deploy.sh"
load_config
OPENCHAMBER_IMAGE="${OPENCHAMBER_IMAGE:?Set OPENCHAMBER_IMAGE in config.env}"

echo "=== Deploying OpenChamber to namespace: $NAMESPACE ==="

# Step 1: Build and push
build_and_push_image "$OPENCHAMBER_IMAGE" "$REPO_ROOT/openchamber"

# Step 2: DevWorkspaceTemplate
echo "Creating editor template..."
cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspaceTemplate
metadata:
  name: openchamber-editor
spec:
  components:
    - name: openchamber-injector
      container:
        image: ${OPENCHAMBER_IMAGE}
        command:
          - /entrypoint-init-container.sh
        volumeMounts:
          - name: openchamber
            path: /openchamber
        memoryLimit: 256Mi
        memoryRequest: 32Mi
        cpuLimit: 500m
        cpuRequest: 30m
    - name: openchamber-runtime
      container:
        image: quay.io/devfile/universal-developer-image:latest
        env:
          - name: GOOGLE_CLOUD_PROJECT
            value: "${GOOGLE_CLOUD_PROJECT}"
          - name: CLOUD_ML_REGION
            value: "${CLOUD_ML_REGION}"
          - name: OPENCHAMBER_UI_PASSWORD
            value: "${OPENCHAMBER_UI_PASSWORD}"
        volumeMounts:
          - name: openchamber
            path: /openchamber
        memoryLimit: 2048Mi
        memoryRequest: 512Mi
        cpuLimit: 1000m
        cpuRequest: 100m
        endpoints:
          - name: openchamber
            targetPort: 3000
            exposure: public
            protocol: https
            secure: true
            attributes:
              cookiesAuthEnabled: true
              discoverable: false
              urlRewriteSupported: true
      attributes:
        controller.devfile.io/container-contribution: true
    - name: openchamber
      volume: {}
  commands:
    - id: init-openchamber-injector
      apply:
        component: openchamber-injector
    - id: init-openchamber-start
      exec:
        component: openchamber-runtime
        commandLine: >-
          nohup /openchamber/entrypoint.sh > /openchamber/entrypoint-logs.txt 2>&1 &
  events:
    preStart:
      - init-openchamber-injector
    postStart:
      - init-openchamber-start
EOF

# Step 3: DevWorkspace
create_workspace "openchamber-workspace" "openchamber-editor"

# Step 4: Wait for pod
wait_for_workspace "openchamber-workspace" 180s

# Step 5: Direct route (bypasses Che gateway subpath routing — same issue as T3 Code)
WS_ID=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.controller\.devfile\.io/devworkspace_id}')
create_direct_route "openchamber-direct" 3000 controller.devfile.io/devworkspace_id "$WS_ID"

# Step 6: Get UI password
echo "Waiting for OpenChamber to start..."
sleep 15
UI_PASSWORD=$(oc exec "$POD" -c openchamber-runtime -n "$NAMESPACE" -- cat /projects/.devspaces-openchamber/ui-password.txt 2>/dev/null || true)
if [ -z "$UI_PASSWORD" ]; then
  sleep 10
  UI_PASSWORD=$(oc exec "$POD" -c openchamber-runtime -n "$NAMESPACE" -- cat /projects/.devspaces-openchamber/ui-password.txt 2>/dev/null || true)
fi

ROUTE_HOST=$(oc get route openchamber-direct -n "$NAMESPACE" -o jsonpath='{.spec.host}')

echo ""
echo "=== OpenChamber is ready ==="
echo ""
echo "URL:      https://${ROUTE_HOST}/"
if [ -n "$UI_PASSWORD" ]; then
  echo "Password: ${UI_PASSWORD}"
elif [ -n "$OPENCHAMBER_UI_PASSWORD" ]; then
  echo "Password: ${OPENCHAMBER_UI_PASSWORD}  (from config.env)"
else
  echo "Password: Not ready yet. Run:"
  echo "          oc exec \$(oc get pods -n $NAMESPACE -l controller.devfile.io/devworkspace_name=openchamber-workspace --no-headers | grep -v cleanup | awk '{print \$1}') -c openchamber-runtime -n $NAMESPACE -- cat /projects/.devspaces-openchamber/ui-password.txt"
fi
echo ""
echo "Shell:    oc exec -it $POD -c openchamber-runtime -n $NAMESPACE -- bash"
echo ""
echo "To configure your LLM provider, shell in and edit ~/.config/opencode/config.json"
echo "For Vertex AI, also run:"
echo "  export PATH=/openchamber/npm-global/bin:/openchamber/google-cloud-sdk/bin:\$PATH"
echo "  gcloud auth application-default login --no-launch-browser"
