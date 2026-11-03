#!/bin/bash

# shellcheck source=shared/runtime.sh
source /t3code/runtime.sh
setup_runtime /t3code/bashrc.sh || exit 1

export PATH="/t3code/npm-global/bin:/t3code/google-cloud-sdk/bin:${PATH}"

if [ -f /t3code/discover-models.sh ]; then
  bash /t3code/discover-models.sh "${PROJECTS_ROOT:-/projects}/opencode.json"
fi

PERSIST="${PROJECTS_ROOT:-/projects}/.devspaces-t3code"
mkdir -p "$PERSIST/gcloud" "$PERSIST/t3code-home" || exit 1
chmod 700 "$PERSIST" || exit 1
if [ -f "$PERSIST/pairing-token.txt" ]; then
  chmod 600 "$PERSIST/pairing-token.txt" || exit 1
fi

export CLOUDSDK_CONFIG="$PERSIST/gcloud"
export T3CODE_HOME="$PERSIST/t3code-home"
export NODE_OPTIONS="--unhandled-rejections=warn"

cd "${PROJECTS_ROOT:-/projects}" || exit 1

# T3 Code 0.1.x prints a bootstrap pairing URL for the running server on startup.
# The devfile redirects this script's output to a log file, so keep the credential out of it.
redact_pairing_url() {
  sed -u -E \
    -e 's#(token=)[A-Za-z0-9_-]+#\1[redacted]#g' \
    -e 's#(token%3D)[A-Za-z0-9_-]+#\1[redacted]#g' \
    -e 's#(Token:[[:space:]]*)[A-Za-z0-9_-]+#\1[redacted]#g'
}

while true; do
  # `start` serves the same web UI as `serve`, but it prints one pairing URL line
  # instead of `serve`'s token, app link, and terminal QR code.
  t3 start \
    --host 0.0.0.0 \
    --port 3773 \
    --no-browser \
    --mode web \
    --auto-bootstrap-project-from-cwd \
    "${PROJECTS_ROOT:-/projects}" > >(redact_pairing_url) 2>&1 &
  T3_PID=$!

  sleep 5

  if [ ! -s "$PERSIST/pairing-token.txt" ]; then
    TOKEN_JSON=$(t3 auth pairing create --ttl 30d --label "devspaces" --json 2>/dev/null)
    if [ -n "$TOKEN_JSON" ]; then
      CREDENTIAL=$(printf '%s' "$TOKEN_JSON" | node -e '
        let input = "";
        process.stdin.on("data", chunk => { input += chunk; });
        process.stdin.on("end", () => {
          try {
            const { credential } = JSON.parse(input);
            if (typeof credential !== "string" || !credential.trim()) process.exit(1);
            process.stdout.write(credential);
          } catch { process.exit(1); }
        });
      ')
      if [ -n "$CREDENTIAL" ]; then
        printf '%s\n' "$CREDENTIAL" > "$PERSIST/pairing-token.txt" || exit 1
        chmod 600 "$PERSIST/pairing-token.txt" || exit 1
        echo "Pairing token saved. Retrieve it with deploy.sh or oc exec."
      fi
    fi
  fi

  wait $T3_PID
  echo "T3 Code exited ($?), restarting in 2s..."
  sleep 2
done
