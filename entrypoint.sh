#!/bin/bash

if ! whoami &> /dev/null; then
  if [ -w /etc/passwd ]; then
    echo "default:x:$(id -u):0:default user:${HOME}:/sbin/nologin" >> /etc/passwd
  fi
fi

export CLAUDE_CODE_USE_VERTEX=true
export PATH="/t3code/npm-global/bin:/t3code/google-cloud-sdk/bin:${PATH}"

PERSIST="${PROJECTS_ROOT:-/projects}/.devspaces-t3code"
mkdir -p "$PERSIST/gcloud" "$PERSIST/claude" "$PERSIST/t3code-home"

export CLOUDSDK_CONFIG="$PERSIST/gcloud"
export CLAUDE_CONFIG_DIR="$PERSIST/claude"
export T3CODE_HOME="$PERSIST/t3code-home"

cd ${PROJECTS_ROOT:-/projects}

while true; do
  t3 serve \
    --host 0.0.0.0 \
    --port 3773 \
    --no-browser \
    --mode web \
    --auto-bootstrap-project-from-cwd \
    "${PROJECTS_ROOT:-/projects}"
  echo "T3 Code exited ($?), restarting in 2s..."
  sleep 2
done
