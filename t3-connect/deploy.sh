#!/bin/bash
set -e

# Load config from repo root
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -f "$REPO_ROOT/config.env" ]; then
  echo "config.env not found. Copy from config.env.example and fill in your values:"
  echo "  cp config.env.example config.env"
  exit 1
fi
source "$REPO_ROOT/config.env"

NAMESPACE="${NAMESPACE:-rh-ee-mdemytte-dev}"
T3_CONNECT_IMAGE="${T3_CONNECT_IMAGE:?Set T3_CONNECT_IMAGE in config.env}"

echo "=== Deploying T3 Connect to namespace: $NAMESPACE ==="

# Step 1: Build and push image
echo "Building image for linux/amd64..."
podman build --platform linux/amd64 -t "$T3_CONNECT_IMAGE" "$(dirname "$0")"
echo "Pushing image..."
podman push "$T3_CONNECT_IMAGE"

# Step 2: Create DevWorkspaceTemplate
echo "Creating editor template..."
cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspaceTemplate
metadata:
  name: t3-connect-editor
spec:
  components:
    - name: t3-connect-injector
      container:
        image: ${T3_CONNECT_IMAGE}
        command:
          - /entrypoint-init-container.sh
        volumeMounts:
          - name: t3connect
            path: /t3connect
        memoryLimit: 256Mi
        memoryRequest: 32Mi
        cpuLimit: 500m
        cpuRequest: 30m
    - name: t3-connect-runtime
      container:
        image: quay.io/devfile/universal-developer-image:latest
        env:
          - name: CLAUDE_CODE_USE_VERTEX
            value: "1"
          - name: GOOGLE_CLOUD_PROJECT
            value: "${GOOGLE_CLOUD_PROJECT}"
          - name: CLOUD_ML_REGION
            value: "${CLOUD_ML_REGION}"
        volumeMounts:
          - name: t3connect
            path: /t3connect
        memoryLimit: 2048Mi
        memoryRequest: 512Mi
        cpuLimit: 1000m
        cpuRequest: 100m
        endpoints:
          - name: t3-connect
            targetPort: 3773
            exposure: internal
            protocol: https
      attributes:
        controller.devfile.io/container-contribution: true
    - name: t3connect
      volume: {}
  commands:
    - id: init-t3-connect-injector
      apply:
        component: t3-connect-injector
    - id: init-t3-connect-start
      exec:
        component: t3-connect-runtime
        commandLine: >-
          nohup /t3connect/entrypoint.sh > /t3connect/entrypoint-logs.txt 2>&1 &
  events:
    preStart:
      - init-t3-connect-injector
    postStart:
      - init-t3-connect-start
EOF

# Step 3: Create DevWorkspace
echo "Creating workspace..."
cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: t3-connect-workspace
  labels:
    che.eclipse.org/devworkspace: "true"
spec:
  started: true
  routingClass: che
  contributions:
    - name: editor
      kubernetes:
        name: t3-connect-editor
  template:
    projects:
      - name: devspaces-experiment-ai-editors
        git:
          remotes:
            origin: https://github.com/Firewall/devspaces-experiment-ai-editors.git
EOF

# Step 4: Wait for pod
echo "Waiting for workspace pod..."
for i in $(seq 1 60); do
  POD=$(oc get pods -n "$NAMESPACE" -l controller.devfile.io/devworkspace_name=t3-connect-workspace --no-headers 2>/dev/null | grep -v cleanup | grep -v Completed | awk '{print $1}')
  if [ -n "$POD" ]; then
    echo "Pod: $POD"
    break
  fi
  sleep 3
done

echo "Waiting for containers to start..."
oc wait --for=condition=Ready "pod/$POD" -n "$NAMESPACE" --timeout=180s

# No Service or Route — access is exclusively via T3 Connect tunnel

# Step 5: Print T3 Connect setup instructions
echo ""
echo "=== T3 Connect workspace is running ==="
echo ""
echo "Access is via T3 Connect (Cloudflare Tunnel), not a browser URL."
echo ""
echo "--- One-time setup (two terminals) ---"
echo ""
echo "Terminal 1 — port-forward for OAuth callback:"
echo "  oc port-forward $POD 34338:34338 -n $NAMESPACE"
echo ""
echo "Terminal 2 — login and link:"
echo "  oc exec -it $POD -c t3-connect-runtime -n $NAMESPACE -- bash"
echo "  export PATH=/t3connect/npm-global/bin:/t3connect/google-cloud-sdk/bin:\$PATH"
echo "  t3 connect login      # completes OAuth in your browser via port-forward"
echo "  t3 connect link       # establishes the tunnel (installs cloudflared if needed)"
echo ""
echo "After linking, access via the T3 Code desktop/mobile app."
echo "Subsequent pod restarts will auto-reconnect the tunnel."
echo ""
echo "--- gcloud auth (required for Claude on Vertex AI) ---"
echo "  oc exec -it $POD -c t3-connect-runtime -n $NAMESPACE -- bash"
echo "  export PATH=/t3connect/npm-global/bin:/t3connect/google-cloud-sdk/bin:\$PATH"
echo "  gcloud auth application-default login --no-launch-browser"
echo ""
echo "--- Cleanup ---"
echo "  t3 connect unlink     # remove tunnel"
echo "  t3 connect logout     # remove Clerk auth"
echo ""
echo "Shell: oc exec -it $POD -c t3-connect-runtime -n $NAMESPACE -- bash"
