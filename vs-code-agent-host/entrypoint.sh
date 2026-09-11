#!/bin/bash

if ! whoami &> /dev/null; then
  if [ -w /etc/passwd ]; then
    echo "default:x:$(id -u):0:default user:${HOME}:/sbin/nologin" >> /etc/passwd
  fi
fi

export PATH="/usr/lib/google-cloud-sdk/bin:${PATH}"

if [ -f /usr/local/bin/shared-bashrc.sh ] && ! grep -q 'shared-bashrc.sh' "$HOME/.bashrc" 2>/dev/null; then
  echo 'source /usr/local/bin/shared-bashrc.sh' >> "$HOME/.bashrc"
fi

SA_CA=/run/secrets/kubernetes.io/serviceaccount/service-ca.crt
[ -f "$SA_CA" ] && export NODE_EXTRA_CA_CERTS="$SA_CA"

# Discover KServe models
if [ -f /usr/local/bin/shared-discover-models.sh ]; then
  bash /usr/local/bin/shared-discover-models.sh "${PROJECTS_ROOT:-/projects}/opencode.json"
fi
if [ -f /usr/local/bin/discover-models-vscode.sh ]; then
  bash /usr/local/bin/discover-models-vscode.sh "${PROJECTS_ROOT:-/projects}/chatLanguageModels.json"
fi

PERSIST="${PROJECTS_ROOT:-/projects}/.devspaces-agent-host"
mkdir -p "$PERSIST/gcloud" "$PERSIST/vscode-server"

TOKEN_FILE="$PERSIST/connection-token"
if [ ! -s "$TOKEN_FILE" ]; then
  CONNECTION_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '=+/\n')
  if [ -z "$CONNECTION_TOKEN" ]; then
    echo "Unable to create an Agent Host connection token" >&2
    exit 1
  fi
  printf '%s\n' "$CONNECTION_TOKEN" > "$TOKEN_FILE"
fi
chmod 600 "$TOKEN_FILE"

export CLOUDSDK_CONFIG="$PERSIST/gcloud"

cd ${PROJECTS_ROOT:-/projects}

echo "Starting VS Code Agent Host on port 3773..."
code agent host \
  --host 0.0.0.0 \
  --port 3773 \
  --connection-token-file "$TOKEN_FILE" \
  --server-data-dir "$PERSIST/vscode-server"

# The supervisor daemonizes itself. Keep the container alive and
# restart it if it dies.
while true; do
  if ! pgrep -f "code.*agent" > /dev/null 2>&1; then
    echo "Agent Host supervisor died, restarting..."
    code agent host \
      --host 0.0.0.0 \
      --port 3773 \
      --connection-token-file "$TOKEN_FILE" \
      --replace \
      --server-data-dir "$PERSIST/vscode-server"
  fi
  sleep 10
done
