#!/bin/bash
set -e

cp /usr/local/bin/t3code-entrypoint.sh /t3code/entrypoint.sh
cp /usr/local/bin/shared-runtime.sh /t3code/runtime.sh
cp /usr/local/bin/shared-bashrc.sh /t3code/bashrc.sh
cp /usr/local/bin/shared-discover-models.sh /t3code/discover-models.sh
cp -r /opt/app-root/src/.npm-global /t3code/npm-global
cp -r /usr/lib/google-cloud-sdk /t3code/google-cloud-sdk

echo "T3 Code injector complete"
