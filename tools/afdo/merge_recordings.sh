#!/usr/bin/env bash
# Merge any number of phone recordings (your own sessions, unplugged sessions, the automated workload,
# recordings made on different BluedMC builds) into one AutoFDO profile.
# usage: tools/afdo/merge_recordings.sh <out.afdo> <recording dir>...
#   a recording dir = one folder from /sdcard/bluedmc-afdo/<timestamp> (uname.txt, kallsyms_text.txt,
#   report_vaddr.txt). Passing the parent folder works too: every recording inside it is used.
# Samples are mapped to source lines with the vmlinux of the kernel that recorded them. That build is
# found among the Kleaf dist dirs in $TOP/out/* by uname -r plus the symbol offsets in kallsyms_text.txt,
# so keep the dist dir of every kernel you record on.
# Weight: each recording counts by how long it ran (4000 / sample rate); WEIGHT_<folder>=N overrides,
# e.g. WEIGHT_20261127_210000=3 to make one session count triple.
set -euo pipefail
OUTF=$1; shift
TOP=${TOP:-$HOME/AmethystGKI/ws138}
B=$TOP/prebuilts/clang/host/linux-x86/clang-r487747c/bin
HERE=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

recs=()
for a in "$@"; do
  [ -f "$a/report_vaddr.txt" ] && recs+=("$a")
  for r in "$a"/*/; do [ -f "$r/report_vaddr.txt" ] && recs+=("${r%/}"); done
done

# pick the dist dir whose Image has the same uname -r and whose System.map has the same symbol offsets
find_dist(){ python3 - "$1" "$TOP"/out/*/ <<'PY'
import sys, os, re, subprocess
rec, dirs = sys.argv[1], sys.argv[2:]
rel = open(os.path.join(rec, "uname.txt")).read().strip()
ks = {}
for l in open(os.path.join(rec, "kallsyms_text.txt")):
    p = l.split()
    if len(p) >= 3: ks.setdefault(p[2], int(p[0], 16))
want = {k: v - ks["_text"] for k, v in ks.items()}
hits = []
for d in dirs:
    img, sm = os.path.join(d, "Image"), os.path.join(d, "System.map")
    if not (os.path.isfile(img) and os.path.isfile(os.path.join(d, "vmlinux")) and os.path.isfile(sm)):
        continue
    m = re.search(rb"Linux version ([0-9][^ ]*) ", open(img, "rb").read())
    if not m or m.group(1).decode() != rel:
        continue
    have = {}
    for l in open(sm):
        p = l.split()
        if len(p) >= 3 and p[2] in want and p[2] not in have: have[p[2]] = int(p[0], 16)
    if all(k in have and have[k] - have["_text"] == v for k, v in want.items()):
        hits.append(d)
if not hits: sys.exit(1)
hits.sort(key=lambda d: -os.path.getmtime(os.path.join(d, "vmlinux")))
if len(hits) > 1: print("note: %s matches %s; using the newest" % (rec, " ".join(hits)), file=sys.stderr)
print(hits[0])
PY
}

inputs=(); n=0
for r in "${recs[@]}"; do
  rel=$(tr -d '\r\n' < "$r/uname.txt")
  d=$(find_dist "$r") || { echo "skip $r: no build of $rel with matching symbols in $TOP/out (need its vmlinux)"; continue; }
  sess=$(cat "$r/session.txt" 2>/dev/null || echo "manual f=4000")
  f=$(echo "$sess" | sed -n 's/.* f=\([0-9]*\).*/\1/p'); f=${f:-4000}
  wv="WEIGHT_$(basename "$r" | tr -c 'A-Za-z0-9\n' _)"
  wgt=${!wv:-$(( 4000 / f ))}; [ "$wgt" -lt 1 ] && wgt=1
  n=$((n+1)); echo "== [$n] $r: $rel ($sess) -> $(basename "$d"), weight $wgt"
  python3 "$HERE/afdo_convert.py" --vmlinux "$d/vmlinux" --sysmap "$d/System.map" \
    --report "$r/report_vaddr.txt" --kallsyms "$r/kallsyms_text.txt" \
    --symbolizer "$B/llvm-symbolizer" --profdata "$B/llvm-profdata" --out "$W/p$n.afdo" \
    | grep -E '^(samples|dropped|functions)' || true
  inputs+=("--weighted-input=$wgt,$W/p$n.afdo")
done
[ $n -gt 0 ] || { echo "no usable recordings"; exit 1; }
"$B/llvm-profdata" merge --sample --extbinary "${inputs[@]}" -o "$OUTF"
echo "merged $n recording(s) -> $OUTF"
"$B/llvm-profdata" show --sample "$OUTF" | tail -4
