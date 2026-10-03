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

NAMESPACE="${NAMESPACE:?Set NAMESPACE to your Dev Spaces user namespace in config.env}"
AGENT_HOST_IMAGE="${AGENT_HOST_IMAGE:?Set AGENT_HOST_IMAGE in config.env}"

echo "=== Deploying VS Code Agent Host to namespace: $NAMESPACE ==="

# Step 1: Build and push image
echo "Building image for linux/amd64..."
podman build --platform linux/amd64 -f "$(dirname "$0")/Containerfile" -t "$AGENT_HOST_IMAGE" "$REPO_ROOT"
echo "Pushing image..."
podman push "$AGENT_HOST_IMAGE"

# Step 2: Create DevWorkspaceTemplate
echo "Creating editor template..."
cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspaceTemplate
metadata:
  name: vs-code-agent-host-editor
spec:
  components:
    - name: vs-code-agent-host
      container:
        image: ${AGENT_HOST_IMAGE}
        command:
          - /bin/bash
          - -c
          - /usr/local/bin/agent-host-entrypoint.sh 2>&1 | tee /tmp/agent-host-logs.txt
        memoryLimit: 4096Mi
        memoryRequest: 1024Mi
        cpuLimit: 2000m
        cpuRequest: 200m
        endpoints:
          - name: agent-host
            targetPort: 3773
            exposure: public
            protocol: https
            secure: true
            attributes:
              cookiesAuthEnabled: true
              discoverable: false
              urlRewriteSupported: true
EOF

# Step 3: Create DevWorkspace
echo "Creating workspace..."
cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: vs-code-agent-host-workspace
  labels:
    che.eclipse.org/devworkspace: "true"
spec:
  started: true
  routingClass: che
  contributions:
    - name: editor
      kubernetes:
        name: vs-code-agent-host-editor
  template:
    projects: []
EOF

# Step 4: Wait for pod
echo "Waiting for workspace pod..."
for _ in $(seq 1 60); do
  POD=$(oc get pods -n "$NAMESPACE" -l controller.devfile.io/devworkspace_name=vs-code-agent-host-workspace --no-headers 2>/dev/null | grep -v cleanup | grep -v Completed | awk '{print $1}')
  if [ -n "$POD" ]; then
    echo "Pod: $POD"
    break
  fi
  sleep 3
done

if [ -z "$POD" ]; then
  echo "No VS Code Agent Host workspace pod appeared. Check DevWorkspace status with oc."
  exit 1
fi

echo "Waiting for containers to start..."
oc wait --for=condition=Ready "pod/$POD" -n "$NAMESPACE" --timeout=300s

# Step 5: Create direct route (bypasses Che gateway subpath routing)
echo "Creating direct route..."
WS_ID=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.controller\.devfile\.io/devworkspace_id}')
cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Service
metadata:
  name: agent-host-direct
spec:
  selector:
    controller.devfile.io/devworkspace_id: ${WS_ID}
  ports:
    - port: 3773
      targetPort: 3773
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: agent-host-direct
spec:
  to:
    kind: Service
    name: agent-host-direct
  port:
    targetPort: 3773
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

# Step 6: Wait for Agent Host to initialize
echo "Waiting for Agent Host to start..."
sleep 20

ROUTE_HOST=$(oc get route agent-host-direct -n "$NAMESPACE" -o jsonpath='{.spec.host}')
AGENT_HOST_TOKEN=$(oc exec "$POD" -c vs-code-agent-host -n "$NAMESPACE" -- \
  cat /projects/.devspaces-agent-host/connection-token 2>/dev/null || true)

echo ""
echo "=== VS Code Agent Host is ready ==="
echo ""
if [ -n "$AGENT_HOST_TOKEN" ]; then
  echo "Agent Host: https://${ROUTE_HOST}/?tkn=${AGENT_HOST_TOKEN}"
else
  echo "Agent Host token is not ready yet. Run:"
  echo "  oc exec $POD -c vs-code-agent-host -n $NAMESPACE -- cat /projects/.devspaces-agent-host/connection-token"
fi
echo ""
echo "Shell: oc exec -it $POD -c vs-code-agent-host -n $NAMESPACE -- bash"
echo ""
echo "Logs:  oc exec $POD -c vs-code-agent-host -n $NAMESPACE -- cat /tmp/agent-host-logs.txt"
echo ""
echo "Test:  make vscode-test"
