#!/bin/bash
# OpenClaw gateway entrypoint for a Dev Spaces workspace.

PERSIST="${PROJECTS_ROOT:-/projects}/.devspaces-openclaw"
WORKDIR="${PROJECTS_ROOT:-/projects}"
umask 077

mkdir -p "$PERSIST/state" "$PERSIST/config" "$PERSIST/data" "$PERSIST/cache" || exit 1
chmod 700 "$PERSIST" || exit 1

# OpenShift runs an arbitrary UID, so keep every writable path under /projects.
export HOME="$PERSIST"
export OPENCLAW_HOME="$PERSIST"
export XDG_CONFIG_HOME="$PERSIST/config"
export XDG_DATA_HOME="$PERSIST/data"
export XDG_STATE_HOME="$PERSIST/state"
export XDG_CACHE_HOME="$PERSIST/cache"
export OPENCLAW_STATE_DIR="$PERSIST/state"
export OPENCLAW_CONFIG_PATH="$PERSIST/openclaw.json"
export OPENCLAW_GATEWAY_PORT=18789

# shellcheck source=shared/runtime.sh
source /usr/local/bin/shared-runtime.sh
setup_runtime /usr/local/bin/shared-bashrc.sh || exit 1

# KServe discovery writes a provider fragment that seed-config.sh merges in.
# The OpenCode config it also writes lives in PERSIST because OpenClaw does not
# read it; /projects stays free for the user's repositories.
if [ -f /usr/local/bin/shared-discover-models.sh ]; then
  bash /usr/local/bin/shared-discover-models.sh \
    "$PERSIST/opencode.json" backend "" "$PERSIST/models.json"
fi

# Model providers reference a private copy of the service account token through
# a file SecretRef. /run/secrets is a symlinked projected volume, which the file
# SecretRef rejects, so copy it and refresh the copy as it rotates. OpenShift
# projects short-lived tokens, and OpenClaw re-reads file secrets on reload.
SA_TOKEN=/run/secrets/kubernetes.io/serviceaccount/token
SA_TOKEN_COPY="$PERSIST/kserve-token"
if [ -s "$SA_TOKEN" ]; then
  cat "$SA_TOKEN" > "$SA_TOKEN_COPY.tmp" && \
    chmod 600 "$SA_TOKEN_COPY.tmp" && \
    mv -f "$SA_TOKEN_COPY.tmp" "$SA_TOKEN_COPY" || exit 1
fi

# Generate a stable gateway token on first start and persist it.
if [ -z "$OPENCLAW_GATEWAY_TOKEN" ]; then
  if [ -s "$PERSIST/gateway-token" ]; then
    OPENCLAW_GATEWAY_TOKEN="$(cat "$PERSIST/gateway-token")"
  else
    OPENCLAW_GATEWAY_TOKEN="$(head -c 32 /dev/urandom | base64 | tr -d '=/+' | head -c 32)"
  fi
fi
if [ -z "$OPENCLAW_GATEWAY_TOKEN" ]; then
  echo "Unable to create an OpenClaw gateway token" >&2
  exit 1
fi
printf '%s\n' "$OPENCLAW_GATEWAY_TOKEN" > "$PERSIST/gateway-token" || exit 1
chmod 600 "$PERSIST/gateway-token" || exit 1
export OPENCLAW_GATEWAY_TOKEN

bash /usr/local/bin/openclaw-seed-config.sh \
  "$OPENCLAW_CONFIG_PATH" "$PERSIST/models.json" \
  "$OPENCLAW_PUBLIC_ORIGIN" "$OPENCLAW_TRUSTED_PROXIES" "$WORKDIR" "$SA_TOKEN_COPY" || exit 1

echo ""
echo "=== OpenClaw ==="
echo "Gateway token saved. Retrieve it with deploy.sh or oc exec."
echo ""

cd "$WORKDIR" || exit 1

# The gateway caches resolved secrets, so reload after the token copy changes.
(
  while sleep 600; do
    [ -s "$SA_TOKEN" ] || continue
    cmp -s "$SA_TOKEN" "$SA_TOKEN_COPY" && continue
    if cat "$SA_TOKEN" > "$SA_TOKEN_COPY.tmp" && \
       chmod 600 "$SA_TOKEN_COPY.tmp" && \
       mv -f "$SA_TOKEN_COPY.tmp" "$SA_TOKEN_COPY"; then
      node /app/openclaw.mjs secrets reload >/dev/null 2>&1 || true
    fi
  done
) &

# Restart in place; Che gateway probes have crashed Node processes in the past.
while true; do
  tini -s -- node /app/docker-entrypoint.mjs node /app/openclaw.mjs gateway &
  OC_PID=$!

  wait "$OC_PID"
  echo "OpenClaw gateway exited ($?), restarting in 2s..." >&2
  sleep 2
done
