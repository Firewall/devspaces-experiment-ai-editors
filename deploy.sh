#!/bin/bash
set -e

# Load config
if [ ! -f config.env ]; then
  echo "config.env not found. Copy from config.env.example and fill in your values:"
  echo "  cp config.env.example config.env"
  exit 1
fi
source config.env

NAMESPACE="${NAMESPACE:-rh-ee-mdemytte-dev}"

echo "=== Deploying T3 Code to namespace: $NAMESPACE ==="

# Step 1: Build and push image
echo "Building image for linux/amd64..."
podman build --platform linux/amd64 -t "$IMAGE" .
echo "Pushing image..."
podman push "$IMAGE"

# Step 2: Create DevWorkspaceTemplate
echo "Creating editor template..."
cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspaceTemplate
metadata:
  name: t3-code-editor
spec:
  components:
    - name: t3-code-injector
      container:
        image: ${IMAGE}
        command:
          - /entrypoint-init-container.sh
        volumeMounts:
          - name: t3code
            path: /t3code
        memoryLimit: 256Mi
        memoryRequest: 32Mi
        cpuLimit: 500m
        cpuRequest: 30m
    - name: t3-code-runtime
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
          - name: t3code
            path: /t3code
        memoryLimit: 2048Mi
        memoryRequest: 512Mi
        cpuLimit: 1000m
        cpuRequest: 100m
        endpoints:
          - name: t3-code
            targetPort: 3773
            exposure: public
            protocol: https
            secure: true
            attributes:
              cookiesAuthEnabled: true
              discoverable: false
              urlRewriteSupported: true
      attributes:
        controller.devfile.io/container-contribution: true
    - name: t3code
      volume: {}
  commands:
    - id: init-t3-code-injector
      apply:
        component: t3-code-injector
    - id: init-t3-code-start
      exec:
        component: t3-code-runtime
        commandLine: >-
          nohup /t3code/entrypoint.sh > /t3code/entrypoint-logs.txt 2>&1 &
  events:
    preStart:
      - init-t3-code-injector
    postStart:
      - init-t3-code-start
EOF

# Step 3: Create DevWorkspace
echo "Creating workspace..."
cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: t3-code-workspace
  labels:
    che.eclipse.org/devworkspace: "true"
spec:
  started: true
  routingClass: che
  contributions:
    - name: editor
      kubernetes:
        name: t3-code-editor
  template:
    projects:
      - name: dev-spaces-t3code
        git:
          remotes:
            origin: https://github.com/Firewall/dev-spaces-t3code.git
EOF

# Step 4: Wait for pod
echo "Waiting for workspace pod..."
for i in $(seq 1 60); do
  POD=$(oc get pods -n "$NAMESPACE" -l controller.devfile.io/devworkspace_name=t3-code-workspace --no-headers 2>/dev/null | grep -v cleanup | grep -v Completed | awk '{print $1}')
  if [ -n "$POD" ]; then
    echo "Pod: $POD"
    break
  fi
  sleep 3
done

echo "Waiting for containers to start..."
oc wait --for=condition=Ready "pod/$POD" -n "$NAMESPACE" --timeout=180s

# Step 5: Create direct route (bypasses Che gateway subpath routing)
echo "Creating direct route..."
WS_ID=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.controller\.devfile\.io/devworkspace_id}')
cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Service
metadata:
  name: t3-code-direct
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
  name: t3-code-direct
spec:
  to:
    kind: Service
    name: t3-code-direct
  port:
    targetPort: 3773
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

# Step 6: Get pairing token
echo "Waiting for T3 Code to start..."
sleep 15
PAIRING_TOKEN=$(oc exec "$POD" -c t3-code-runtime -n "$NAMESPACE" -- cat /projects/.devspaces-t3code/pairing-token.txt 2>/dev/null)
if [ -z "$PAIRING_TOKEN" ]; then
  sleep 10
  PAIRING_TOKEN=$(oc exec "$POD" -c t3-code-runtime -n "$NAMESPACE" -- cat /projects/.devspaces-t3code/pairing-token.txt 2>/dev/null)
fi

ROUTE_HOST=$(oc get route t3-code-direct -n "$NAMESPACE" -o jsonpath='{.spec.host}')

echo ""
echo "=== T3 Code is ready ==="
echo ""
echo "URL:   https://${ROUTE_HOST}/"
if [ -n "$PAIRING_TOKEN" ]; then
  echo "Pair:  https://${ROUTE_HOST}/pair#token=${PAIRING_TOKEN}"
else
  echo "Pair:  Token not ready yet. Run:"
  echo "       oc exec \$(oc get pods -n $NAMESPACE -l controller.devfile.io/devworkspace_name=t3-code-workspace --no-headers | grep -v cleanup | awk '{print \$1}') -c t3-code-runtime -n $NAMESPACE -- cat /projects/.devspaces-t3code/pairing-token.txt"
fi
echo ""
echo "Shell: oc exec -it $POD -c t3-code-runtime -n $NAMESPACE -- bash"
echo ""
echo "To authenticate gcloud (required for Claude):"
echo "  oc exec -it $POD -c t3-code-runtime -n $NAMESPACE -- bash"
echo "  export PATH=/t3code/npm-global/bin:/t3code/google-cloud-sdk/bin:\$PATH"
echo "  gcloud auth application-default login --no-launch-browser"
