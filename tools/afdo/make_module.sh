#!/usr/bin/env bash
# Build the BluedMC AutoFDO KernelSU module zip: tools/afdo/make_module.sh [out.zip]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
V=$(sed -n 's/^version=//p' "$HERE/ksu-module/module.prop")
OUTZ=$(realpath -m "${1:-$HERE/../../dist/BluedMC-AutoFDO-module-$V.zip}")
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
cp -r "$HERE/ksu-module/." "$S/"
cp "$HERE/afdo_record.sh" "$HERE/afdo_workload.sh" "$S/"
mkdir -p "$(dirname "$OUTZ")"; rm -f "$OUTZ"
(cd "$S" && python3 -c 'import os,sys,zipfile
z=zipfile.ZipFile(sys.argv[1],"w",zipfile.ZIP_DEFLATED)
for r,_,fs in os.walk("."):
    for f in sorted(fs): z.write(os.path.join(r,f), os.path.relpath(os.path.join(r,f),"."))' "$OUTZ")
echo "$OUTZ"; unzip -l "$OUTZ" | tail -n +2
