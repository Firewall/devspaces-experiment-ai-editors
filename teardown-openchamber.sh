#!/bin/bash

source config.env 2>/dev/null
NAMESPACE="${NAMESPACE:-rh-ee-mdemytte-dev}"

echo "=== Tearing down OpenChamber from namespace: $NAMESPACE ==="

oc delete devworkspace openchamber-workspace -n "$NAMESPACE" 2>/dev/null
oc delete devworkspacetemplate openchamber-editor -n "$NAMESPACE" 2>/dev/null
oc delete service openchamber-direct -n "$NAMESPACE" 2>/dev/null
oc delete route openchamber-direct -n "$NAMESPACE" 2>/dev/null

echo "Done."
