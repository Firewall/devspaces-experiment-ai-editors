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

render_devfile() (
  export T3_IMAGE OPENCHAMBER_IMAGE ORCA_IMAGE AGENT_HOST_IMAGE \
    GOOGLE_CLOUD_PROJECT CLOUD_ML_REGION OPENCHAMBER_UI_PASSWORD \
    ORCA_PAIRING_ADDRESS REDHAT_AI_NAMESPACE
  python3 "$REPO_ROOT/shared/render-devfile.py" "$@"
)

create_editor_template() {
  local devfile="$1" editor="$2" manifest
  manifest=$(render_devfile "$devfile" --template "$editor") || return 1
  echo "Creating editor template..."
  printf '%s\n' "$manifest" | oc apply -n "$NAMESPACE" -f -
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
  local timeout_seconds="${timeout%s}" deadline remaining pods selection pod ready last_pod=""
  if [[ ! "$timeout_seconds" =~ ^[0-9]+$ ]] || [ "$timeout_seconds" -eq 0 ]; then
    echo "Workspace timeout must be a positive number of seconds: $timeout" >&2
    return 1
  fi
  deadline=$((SECONDS + 10#$timeout_seconds))
  POD=""
  echo "Waiting for workspace pod..."
  while [ "$SECONDS" -lt "$deadline" ]; do
    remaining=$((deadline - SECONDS))
    if [ "$remaining" -le 0 ]; then break; fi
    pods=$(oc get pods -n "$NAMESPACE" -l "controller.devfile.io/devworkspace_name=$workspace" \
      -o json --request-timeout="${remaining}s") || return 1
    # Re-select on every poll: applying a template can replace the previous pod.
    selection=$(printf '%s\n' "$pods" | python3 -c '
import json, sys
pods = [pod for pod in json.load(sys.stdin)["items"]
        if not pod["metadata"].get("deletionTimestamp")
        and "cleanup" not in pod["metadata"]["name"]
        and pod.get("status", {}).get("phase") not in ("Succeeded", "Failed")]
if pods:
    pod = max(pods, key=lambda pod: pod["metadata"].get("creationTimestamp", ""))
    ready = any(condition.get("type") == "Ready" and condition.get("status") == "True"
                for condition in pod.get("status", {}).get("conditions", []))
    print(pod["metadata"]["name"], "ready" if ready else "pending")
') || return 1
    read -r pod ready <<< "$selection"
    if [ -n "$pod" ] && [ "$pod" != "$last_pod" ]; then
      echo "Pod: $pod"
      echo "Waiting for containers to start..."
      last_pod="$pod"
    fi
    if [ "$ready" = ready ]; then
      POD="$pod"
      echo "Pod ready: $POD"
      return 0
    fi
    remaining=$((deadline - SECONDS))
    if [ "$remaining" -gt 0 ]; then
      if [ "$remaining" -gt 3 ]; then remaining=3; fi
      sleep "$remaining"
    fi
  done
  echo "Workspace $workspace was not ready within $timeout. Check: oc get devworkspace $workspace -n $NAMESPACE" >&2
  return 1
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
