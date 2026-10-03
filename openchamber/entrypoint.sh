#!/bin/bash

# shellcheck source=shared/runtime.sh
source /openchamber/runtime.sh
setup_runtime /openchamber/bashrc.sh || exit 1

export PATH="/openchamber/npm-global/bin:/openchamber/google-cloud-sdk/bin:${PATH}"

# Pin OpenCode port so it doesn't conflict with other services in the pod
export OPENCODE_PORT=4096

PERSIST="${PROJECTS_ROOT:-/projects}/.devspaces-openchamber"
mkdir -p "$PERSIST/gcloud" \
         "$PERSIST/opencode-config" \
         "$PERSIST/opencode-share" \
         "$PERSIST/opencode-state" \
         "$PERSIST/openchamber-config" || exit 1
chmod 700 "$PERSIST" || exit 1

# Symlink XDG dirs so OpenCode and OpenChamber state survives workspace restarts
mkdir -p "$HOME/.config" "$HOME/.local/share" "$HOME/.local/state"
ln -sfn "$PERSIST/opencode-config"    "$HOME/.config/opencode"
ln -sfn "$PERSIST/opencode-share"     "$HOME/.local/share/opencode"
ln -sfn "$PERSIST/opencode-state"     "$HOME/.local/state/opencode"
ln -sfn "$PERSIST/openchamber-config" "$HOME/.config/openchamber"

if [ -f /openchamber/discover-models.sh ]; then
  bash /openchamber/discover-models.sh "${PROJECTS_ROOT:-/projects}/opencode.json"
fi

# Vertex AI (if configured)
if [ -n "$GOOGLE_CLOUD_PROJECT" ]; then
  export CLOUDSDK_CONFIG="$PERSIST/gcloud"
  ln -sfn "$PERSIST/gcloud" "$HOME/.config/gcloud"
fi

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

# Pre-seed OpenCode config so it defaults to /projects/ as the workspace root
OPENCODE_CFG="$HOME/.config/opencode/config.json"
if [ ! -f "$OPENCODE_CFG" ]; then
  mkdir -p "$(dirname "$OPENCODE_CFG")"
  cat > "$OPENCODE_CFG" <<EOCFG
{
  "cwd": "$WORKDIR"
}
EOCFG
fi

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
