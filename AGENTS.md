# DevSpaces T3 Code — Agent Guidelines

## Deploying

Each editor directory (t3-code, openchamber, orca, vs-code-agent-host) contains a `deploy.sh` script that handles the full lifecycle: build, push, register, and workspace creation. Always suggest `deploy.sh` before individual Makefile targets.

Teardown is handled by `teardown.sh` in the same directory.
