#!/bin/bash

# OpenShift arbitrary UID — containers run as a random UID in GID 0
if ! whoami &> /dev/null; then
  if [ -w /etc/passwd ]; then
    echo "default:x:$(id -u):0:default user:${HOME}:/sbin/nologin" >> /etc/passwd
  fi
fi

export PATH="/openchamber/npm-global/bin:/openchamber/google-cloud-sdk/bin:${PATH}"

if [ -f /openchamber/bashrc.sh ] && ! grep -q 'openchamber/bashrc.sh' "$HOME/.bashrc" 2>/dev/null; then
  echo 'source /openchamber/bashrc.sh' >> "$HOME/.bashrc"
fi

SA_CA=/run/secrets/kubernetes.io/serviceaccount/service-ca.crt
[ -f "$SA_CA" ] && export NODE_EXTRA_CA_CERTS="$SA_CA"

# Pin OpenCode port so it doesn't conflict with other services in the pod
export OPENCODE_PORT=4096

PERSIST="${PROJECTS_ROOT:-/projects}/.devspaces-openchamber"
mkdir -p "$PERSIST/gcloud" \
         "$PERSIST/opencode-config" \
         "$PERSIST/opencode-share" \
         "$PERSIST/opencode-state" \
         "$PERSIST/openchamber-config"

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
  if [ -f "$PERSIST/ui-password.txt" ]; then
    OPENCHAMBER_UI_PASSWORD=$(cat "$PERSIST/ui-password.txt")
  else
    OPENCHAMBER_UI_PASSWORD=$(head -c 32 /dev/urandom | base64 | tr -d '=/+' | head -c 16)
    echo "$OPENCHAMBER_UI_PASSWORD" > "$PERSIST/ui-password.txt"
  fi
  export OPENCHAMBER_UI_PASSWORD
fi

echo ""
echo "=== OpenChamber ==="
echo "UI password: $OPENCHAMBER_UI_PASSWORD"
echo ""

WORKDIR="${PROJECTS_ROOT:-/projects}"
cd "$WORKDIR"

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
  cat > "$OC_THEMES/redhat-dark.json" <<'EOTHEME'
{
  "metadata": {
    "id": "redhat-dark",
    "name": "Red Hat Dark",
    "description": "Dark theme using Red Hat brand colors and PatternFly semantics",
    "version": "1.0.0",
    "variant": "dark",
    "tags": ["dark", "redhat", "brand"]
  },
  "colors": {
    "primary": {
      "base": "#EE0000",
      "hover": "#CC0000",
      "active": "#FF4444",
      "foreground": "#FFFFFF",
      "muted": "#EE000080",
      "emphasis": "#FF4444"
    },
    "surface": {
      "background": "#151515",
      "foreground": "#E0E0E0",
      "muted": "#1F1F1F90",
      "mutedForeground": "#A0A0A0",
      "elevated": "#29292990",
      "elevatedForeground": "#E0E0E0",
      "overlay": "#00000080",
      "subtle": "#1C1C1C"
    },
    "interactive": {
      "border": "#3C3C3C",
      "borderHover": "#4A4A4A",
      "borderFocus": "#EE0000",
      "selection": "#EE000030",
      "selectionForeground": "#E0E0E0",
      "focus": "#EE0000",
      "focusRing": "#EE000050",
      "cursor": "#E0E0E0",
      "hover": "#ffffff14",
      "active": "#ffffff1f"
    },
    "status": {
      "error": "#E54545",
      "errorForeground": "#151515",
      "errorBackground": "#E5454520",
      "errorBorder": "#E5454550",
      "warning": "#F0AB00",
      "warningForeground": "#151515",
      "warningBackground": "#F0AB0020",
      "warningBorder": "#F0AB0050",
      "success": "#5BA352",
      "successForeground": "#151515",
      "successBackground": "#5BA35220",
      "successBorder": "#5BA35250",
      "info": "#2B9AF3",
      "infoForeground": "#151515",
      "infoBackground": "#2B9AF320",
      "infoBorder": "#2B9AF350"
    },
    "pr": {
      "open": "#5BA352",
      "draft": "#A0A0A0",
      "blocked": "#F0AB00",
      "merged": "#A18FFF",
      "closed": "#E54545"
    },
    "syntax": {
      "base": {
        "background": "#1A1A1A",
        "foreground": "#E0E0E0",
        "comment": "#6A6A6A",
        "keyword": "#2B9AF3",
        "string": "#5BA352",
        "number": "#A18FFF",
        "function": "#F0AB00",
        "variable": "#E0E0E0",
        "type": "#EE0000",
        "operator": "#E54545"
      },
      "tokens": {
        "commentDoc": "#555555",
        "stringEscape": "#E0E0E0",
        "keywordImport": "#EE0000",
        "storageModifier": "#2B9AF3",
        "functionCall": "#F0AB00",
        "method": "#5BA352",
        "variableProperty": "#2B9AF3",
        "variableOther": "#5BA352",
        "variableGlobal": "#E54545",
        "variableLocal": "#C8C8C8",
        "parameter": "#E0E0E0",
        "constant": "#A18FFF",
        "class": "#F0AB00",
        "className": "#F0AB00",
        "interface": "#EE0000",
        "struct": "#F0AB00",
        "enum": "#F0AB00",
        "typeParameter": "#F0AB00",
        "namespace": "#EE0000",
        "module": "#E54545",
        "tag": "#2B9AF3",
        "jsxTag": "#EE0000",
        "tagAttribute": "#F0AB00",
        "tagAttributeValue": "#5BA352",
        "boolean": "#A18FFF",
        "decorator": "#F0AB00",
        "label": "#EE0000",
        "punctuation": "#6A6A6A",
        "macro": "#2B9AF3",
        "preprocessor": "#EE0000",
        "regex": "#5BA352",
        "url": "#2B9AF3",
        "key": "#F0AB00",
        "exception": "#E54545"
      },
      "highlights": {
        "diffAdded": "#5BA352",
        "diffAddedBackground": "#5BA35220",
        "diffRemoved": "#E54545",
        "diffRemovedBackground": "#E5454520",
        "diffModified": "#2B9AF3",
        "diffModifiedBackground": "#2B9AF320",
        "lineNumber": "#3C3C3C",
        "lineNumberActive": "#E0E0E0"
      }
    },
    "markdown": {
      "heading1": "#FFFFFF",
      "heading2": "#E0E0E0",
      "heading3": "#C8C8C8",
      "heading4": "#B0B0B0",
      "link": "#2B9AF3",
      "linkHover": "#73BCF7",
      "inlineCode": "#5BA352",
      "inlineCodeBackground": "#1A1A1A",
      "blockquote": "#A0A0A0",
      "blockquoteBorder": "#3C3C3C",
      "listMarker": "#EE000099"
    },
    "chat": {
      "userMessage": "#E0E0E0",
      "userMessageBackground": "#2A1515",
      "assistantMessage": "#E0E0E0",
      "assistantMessageBackground": "#151515",
      "timestamp": "#A0A0A0",
      "divider": "#3C3C3C"
    },
    "tools": {
      "background": "#1A1A1A50",
      "border": "#3C3C3C9d",
      "headerHover": "#3C3C3C50",
      "icon": "#A0A0A0",
      "title": "#E0E0E0",
      "description": "#A0A0A0",
      "edit": {
        "added": "#5BA352",
        "addedBackground": "#5BA35225",
        "removed": "#E54545",
        "removedBackground": "#E5454525",
        "lineNumber": "#3C3C3C"
      }
    }
  },
  "config": {
    "fonts": {
      "sans": "\"Red Hat Display\", \"IBM Plex Sans\", sans-serif",
      "mono": "\"Red Hat Mono\", \"IBM Plex Mono\", monospace",
      "heading": "\"Red Hat Display\", \"IBM Plex Sans\", sans-serif"
    },
    "radius": {
      "none": "0",
      "sm": "0.25rem",
      "md": "0.5rem",
      "lg": "1rem",
      "xl": "1.5rem",
      "full": "9999px"
    },
    "transitions": {
      "fast": "150ms ease",
      "normal": "250ms ease",
      "slow": "350ms ease"
    }
  }
}
EOTHEME
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
