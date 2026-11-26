#!/bin/bash
# Build, then (re)start Emper.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
pkill -x Emper 2>/dev/null || true
open build/Emper.app
