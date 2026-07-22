#!/bin/bash
set -e

if ! whoami &> /dev/null; then
  if [ -w /etc/passwd ]; then
    echo "default:x:$(id -u):0:default user:${HOME}:/sbin/nologin" >> /etc/passwd
  fi
fi

export CLAUDE_CODE_USE_VERTEX=true
export PATH="/t3code/npm-global/bin:/t3code/google-cloud-sdk/bin:${PATH}"

cd ${PROJECTS_ROOT:-/projects}

exec t3 serve \
  --host 0.0.0.0 \
  --port 3773 \
  --no-browser \
  --mode web
