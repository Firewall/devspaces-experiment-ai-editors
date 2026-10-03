# shellcheck shell=bash

load_config() {
  if [ ! -f "$REPO_ROOT/config.env" ]; then
    echo "config.env not found. Copy from config.env.example and fill in your values:"
    echo "  cp config.env.example config.env"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$REPO_ROOT/config.env"
  NAMESPACE="${NAMESPACE:?Set NAMESPACE to your Dev Spaces user namespace in config.env}"
}

build_and_push_image() {
  local image="$1" editor_dir="$2"
  echo "Building image for linux/amd64..."
  podman build --platform linux/amd64 -f "$editor_dir/Containerfile" -t "$image" "$REPO_ROOT"
  echo "Pushing image..."
  podman push "$image"
}

create_workspace() {
  local workspace="$1" editor="$2"
  echo "Creating workspace..."
  cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: ${workspace}
  labels:
    che.eclipse.org/devworkspace: "true"
spec:
  started: true
  routingClass: che
  contributions:
    - name: editor
      kubernetes:
        name: ${editor}
  template:
    projects: []
EOF
}

wait_for_workspace() {
  local workspace="$1" timeout="${2:-180s}"
  POD=""
  echo "Waiting for workspace pod..."
  for _ in $(seq 1 60); do
    POD=$(oc get pods -n "$NAMESPACE" -l "controller.devfile.io/devworkspace_name=$workspace" --no-headers 2>/dev/null |
      awk '$1 !~ /cleanup/ && $3 != "Completed" {print $1; exit}')
    if [ -n "$POD" ]; then
      echo "Pod: $POD"
      break
    fi
    sleep 3
  done
  if [ -z "$POD" ]; then
    echo "Workspace pod did not appear. Check: oc get devworkspace $workspace -n $NAMESPACE"
    return 1
  fi
  echo "Waiting for containers to start..."
  oc wait --for=condition=Ready "pod/$POD" -n "$NAMESPACE" --timeout="$timeout"
}

create_direct_route() {
  local route="$1" port="$2" selector_key="$3" selector_value="$4"
  echo "Creating direct route..."
  cat <<EOF | oc apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Service
metadata:
  name: ${route}
spec:
  selector:
    ${selector_key}: ${selector_value}
  ports:
    - port: ${port}
      targetPort: ${port}
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ${route}
spec:
  to:
    kind: Service
    name: ${route}
  port:
    targetPort: ${port}
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF
}

teardown_editor() {
  local label="$1" workspace="$2" editor="$3" route="$4"
  echo "=== Tearing down $label from namespace: $NAMESPACE ==="
  oc delete devworkspace "$workspace" -n "$NAMESPACE" --ignore-not-found
  oc delete devworkspacetemplate "$editor" -n "$NAMESPACE" --ignore-not-found
  oc delete service "$route" -n "$NAMESPACE" --ignore-not-found
  oc delete route "$route" -n "$NAMESPACE" --ignore-not-found
  echo "Done."
}
