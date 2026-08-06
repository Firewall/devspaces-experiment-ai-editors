#!/bin/bash

if ! whoami &> /dev/null; then
  if [ -w /etc/passwd ]; then
    echo "default:x:$(id -u):0:default user:${HOME}:/sbin/nologin" >> /etc/passwd
  fi
fi

export CLAUDE_CODE_USE_VERTEX=true
export PATH="/t3connect/npm-global/bin:/t3connect/google-cloud-sdk/bin:${PATH}"

if [ -f /t3connect/bashrc.sh ] && ! grep -q 't3connect/bashrc.sh' "$HOME/.bashrc" 2>/dev/null; then
  echo 'source /t3connect/bashrc.sh' >> "$HOME/.bashrc"
fi

SA_CA=/run/secrets/kubernetes.io/serviceaccount/service-ca.crt
[ -f "$SA_CA" ] && export NODE_EXTRA_CA_CERTS="$SA_CA"

if [ -f /t3connect/discover-models.sh ]; then
  bash /t3connect/discover-models.sh "${PROJECTS_ROOT:-/projects}/opencode.json"
fi

PERSIST="${PROJECTS_ROOT:-/projects}/.devspaces-t3connect"
mkdir -p "$PERSIST/gcloud" "$PERSIST/claude" "$PERSIST/t3-home"

export CLOUDSDK_CONFIG="$PERSIST/gcloud"
export CLAUDE_CONFIG_DIR="$PERSIST/claude"

# Both t3 serve and t3 connect must share the same data directory so the server
# can find the connect link config. Symlink ~/.t3 to persistent storage.
if [ -d "$HOME/.t3" ] && [ ! -L "$HOME/.t3" ]; then
  cp -a "$HOME/.t3/." "$PERSIST/t3-home/" 2>/dev/null || true
  rm -rf "$HOME/.t3"
fi
ln -sfn "$PERSIST/t3-home" "$HOME/.t3"

cd ${PROJECTS_ROOT:-/projects}

while true; do
  t3 serve \
    --host 0.0.0.0 \
    --port 3773 \
    --no-browser \
    --mode web \
    --auto-bootstrap-project-from-cwd \
    "${PROJECTS_ROOT:-/projects}" &
  T3_PID=$!

  sleep 5

  if [ -f "$PERSIST/t3-home/userdata/secrets/cloud-cli-desired-link.bin" ]; then
    echo "T3 Connect: previously configured — tunnel should auto-reconnect via t3 serve"
  else
    echo ""
    echo "=== T3 Connect: one-time setup required ==="
    echo "See deploy.sh output for port-forward and login instructions."
    echo ""
  fi

  wait $T3_PID
  echo "T3 Code exited ($?), restarting in 2s..."
  sleep 2
done
