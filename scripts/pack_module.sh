#!/usr/bin/env bash
# Pack the BluedMC Tuning KernelSU/Magisk module: scripts/pack_module.sh [out dir]
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd); OUTD=${1:-$REPO/dist}
v=$(sed -n 's/^version=//p' "$REPO/module/module.prop")
mkdir -p "$OUTD"; z="$OUTD/BluedMC-Tuning-$v.zip"; rm -f "$z"
( cd "$REPO/module" && zip -qr9 "$z" . -x '.*' )
echo "$z"
