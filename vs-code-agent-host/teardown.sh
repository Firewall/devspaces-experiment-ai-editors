#!/bin/bash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/config.env" 2>/dev/null
NAMESPACE="${NAMESPACE:-rh-ee-mdemytte-dev}"

echo "=== Tearing down VS Code Agent Host from namespace: $NAMESPACE ==="

oc delete devworkspace vs-code-agent-host-workspace -n "$NAMESPACE" 2>/dev/null
oc delete devworkspacetemplate vs-code-agent-host-editor -n "$NAMESPACE" 2>/dev/null
oc delete service agent-host-direct -n "$NAMESPACE" 2>/dev/null
oc delete route agent-host-direct -n "$NAMESPACE" 2>/dev/null

echo "Done."
