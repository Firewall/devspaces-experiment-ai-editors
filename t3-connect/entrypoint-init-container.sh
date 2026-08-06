#!/bin/bash
set -e

cp /usr/local/bin/t3connect-entrypoint.sh /t3connect/entrypoint.sh
cp -r /opt/app-root/src/.npm-global /t3connect/npm-global
cp -r /usr/lib/google-cloud-sdk /t3connect/google-cloud-sdk

echo "T3 Connect injector complete"
