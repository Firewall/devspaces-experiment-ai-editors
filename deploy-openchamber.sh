#!/bin/bash
set -e

if [ ! -f config.env ]; then
  echo "config.env not found. Copy from config.env.example and fill in your values:"
  echo "  cp config.env.example config.env"
  exit 1
fi
source config.env

NAMESPACE="${NAMESPACE:-rh-ee-mdemytte-dev}"
OPENCHAMBER_IMAGE="${OPENCHAMBER_IMAGE:?Set OPENCHAMBER_IMAGE in config.env}"

echo "=== Deploying OpenChamber to namespace: $NAMESPACE ==="

# Step 1: Build and push
echo "Building image for linux/amd64..."
podman build --platform linux/amd64 -t "$OPENCHAMBER_IMAGE" -f Dockerfile.openchamber .
echo "Pushing image..."
podman push "$OPENCHAMBER_IMAGE"

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
echo "Creating workspace..."
cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: openchamber-workspace
  labels:
    che.eclipse.org/devworkspace: "true"
spec:
  started: true
  routingClass: che
  contributions:
    - name: editor
      kubernetes:
        name: openchamber-editor
  template:
    projects: []
EOF

# Step 4: Wait for pod
echo "Waiting for workspace pod..."
for i in $(seq 1 60); do
  POD=$(oc get pods -n "$NAMESPACE" -l controller.devfile.io/devworkspace_name=openchamber-workspace --no-headers 2>/dev/null | grep -v cleanup | grep -v Completed | awk '{print $1}')
  if [ -n "$POD" ]; then
    echo "Pod: $POD"
    break
  fi
  sleep 3
done

echo "Waiting for containers to start..."
oc wait --for=condition=Ready "pod/$POD" -n "$NAMESPACE" --timeout=180s

# Step 5: Direct route (bypasses Che gateway subpath routing — same issue as T3 Code)
echo "Creating direct route..."
WS_ID=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.controller\.devfile\.io/devworkspace_id}')
cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Service
metadata:
  name: openchamber-direct
spec:
  selector:
    controller.devfile.io/devworkspace_id: ${WS_ID}
  ports:
    - port: 3000
      targetPort: 3000
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: openchamber-direct
spec:
  to:
    kind: Service
    name: openchamber-direct
  port:
    targetPort: 3000
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

# Step 6: Get UI password
echo "Waiting for OpenChamber to start..."
sleep 15
UI_PASSWORD=$(oc exec "$POD" -c openchamber-runtime -n "$NAMESPACE" -- cat /projects/.devspaces-openchamber/ui-password.txt 2>/dev/null)
if [ -z "$UI_PASSWORD" ]; then
  sleep 10
  UI_PASSWORD=$(oc exec "$POD" -c openchamber-runtime -n "$NAMESPACE" -- cat /projects/.devspaces-openchamber/ui-password.txt 2>/dev/null)
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
