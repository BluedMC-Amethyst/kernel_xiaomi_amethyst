#!/usr/bin/env bash
# Turn a phone recording (adb pull /sdcard/bluedmc-afdo) into bluedmc.afdo for the kernel that was running.
# usage: tools/afdo/make_profile.sh <bluedmc-afdo dir> <kleaf dist dir of THAT kernel> [out.afdo]
set -euo pipefail
REC=$1; DIST=$2; OUTF=${3:-$REC/bluedmc.afdo}
TOP=${TOP:-$HOME/AmethystGKI/ws138}
B=$TOP/prebuilts/clang/host/linux-x86/clang-r487747c/bin
want=$(cat "$REC/uname.txt"); have=$(strings "$DIST/Image" | sed -n '/^Linux version [0-9]/{s/^Linux version \([^ ]*\) .*/\1/p;q}' || true)
[ "$want" = "$have" ] || { echo "recording is from $want but $DIST is $have - use the matching build"; exit 1; }
python3 "$(dirname "$0")/afdo_convert.py" --vmlinux "$DIST/vmlinux" --sysmap "$DIST/System.map" \
  --report "$REC/report_vaddr.txt" --kallsyms "$REC/kallsyms_text.txt" \
  --symbolizer "$B/llvm-symbolizer" --profdata "$B/llvm-profdata" --out "$OUTF"
