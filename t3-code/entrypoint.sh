#!/bin/bash

if ! whoami &> /dev/null; then
  if [ -w /etc/passwd ]; then
    echo "default:x:$(id -u):0:default user:${HOME}:/sbin/nologin" >> /etc/passwd
  fi
fi

export PATH="/t3code/npm-global/bin:/t3code/google-cloud-sdk/bin:${PATH}"

if [ -f /t3code/bashrc.sh ] && ! grep -q 't3code/bashrc.sh' "$HOME/.bashrc" 2>/dev/null; then
  echo 'source /t3code/bashrc.sh' >> "$HOME/.bashrc"
fi

SA_CA=/run/secrets/kubernetes.io/serviceaccount/service-ca.crt
[ -f "$SA_CA" ] && export NODE_EXTRA_CA_CERTS="$SA_CA"

if [ -f /t3code/discover-models.sh ]; then
  bash /t3code/discover-models.sh "${PROJECTS_ROOT:-/projects}/opencode.json"
fi

PERSIST="${PROJECTS_ROOT:-/projects}/.devspaces-t3code"
mkdir -p "$PERSIST/gcloud" "$PERSIST/t3code-home"

export CLOUDSDK_CONFIG="$PERSIST/gcloud"
export T3CODE_HOME="$PERSIST/t3code-home"
export NODE_OPTIONS="--unhandled-rejections=warn"

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

  if [ ! -f "$PERSIST/pairing-token.txt" ]; then
    TOKEN_JSON=$(t3 auth pairing create --ttl 30d --label "devspaces" --json 2>/dev/null)
    if [ -n "$TOKEN_JSON" ]; then
      CREDENTIAL=$(echo "$TOKEN_JSON" | grep '"credential"' | sed 's/.*: "//;s/".*//')
      echo "$CREDENTIAL" > "$PERSIST/pairing-token.txt"
      echo "Pairing token created and saved to $PERSIST/pairing-token.txt"
    fi
  fi

  if [ -f "$PERSIST/pairing-token.txt" ]; then
    echo "Pairing token: $(cat "$PERSIST/pairing-token.txt")"
  fi

  wait $T3_PID
  echo "T3 Code exited ($?), restarting in 2s..."
  sleep 2
done
