#!/bin/bash

# shellcheck source=shared/runtime.sh
source /openchamber/runtime.sh
setup_runtime /openchamber/bashrc.sh || exit 1

export PATH="/openchamber/npm-global/bin:${PATH}"

# Pin OpenCode port so it doesn't conflict with other services in the pod
export OPENCODE_PORT=4096

PERSIST="${PROJECTS_ROOT:-/projects}/.devspaces-openchamber"
mkdir -p "$PERSIST/openchamber-config" || exit 1
chmod 700 "$PERSIST" || exit 1

# Symlink the XDG dir so OpenChamber state survives workspace restarts
mkdir -p "$HOME/.config"
ln -sfn "$PERSIST/openchamber-config" "$HOME/.config/openchamber"

# Generate a stable UI password on first start, persist it
if [ -z "$OPENCHAMBER_UI_PASSWORD" ]; then
  if [ -s "$PERSIST/ui-password.txt" ]; then
    OPENCHAMBER_UI_PASSWORD=$(cat "$PERSIST/ui-password.txt")
  else
    OPENCHAMBER_UI_PASSWORD=$(head -c 32 /dev/urandom | base64 | tr -d '=/+' | head -c 16)
  fi
fi
if [ -z "$OPENCHAMBER_UI_PASSWORD" ]; then
  echo "Unable to create an OpenChamber UI password" >&2
  exit 1
fi
printf '%s\n' "$OPENCHAMBER_UI_PASSWORD" > "$PERSIST/ui-password.txt" || exit 1
chmod 600 "$PERSIST/ui-password.txt" || exit 1
export OPENCHAMBER_UI_PASSWORD

echo ""
echo "=== OpenChamber ==="
echo "UI password saved. Retrieve it with deploy.sh or oc exec."
echo ""

WORKDIR="${PROJECTS_ROOT:-/projects}"
cd "$WORKDIR" || exit 1

# Default OpenChamber's managed OpenCode server to /projects/ as the workspace
# root. OpenCode 2.x dropped the "cwd" config key, so OpenChamber takes it from
# this environment variable instead.
export OPENCHAMBER_OPENCODE_CWD="$WORKDIR"

# Pre-seed Red Hat theme
OC_THEMES="$HOME/.config/openchamber/themes"
if [ ! -f "$OC_THEMES/redhat-dark.json" ]; then
  mkdir -p "$OC_THEMES"
  cp /openchamber/redhat-dark.json "$OC_THEMES/redhat-dark.json" || exit 1
fi

# Restart loop — Che gateway probes can crash Node processes with ECONNRESET
while true; do
  openchamber serve \
    --host 0.0.0.0 \
    --port 3000 \
    --ui-password "$OPENCHAMBER_UI_PASSWORD" \
    --foreground &
  OC_PID=$!

  wait $OC_PID
  echo "OpenChamber exited ($?), restarting in 2s..."
  sleep 2
done
