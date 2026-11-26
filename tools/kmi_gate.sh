#!/bin/bash
# KMI gate (from TechAmethyst tools_ta/kmi_gate.sh): every symbol imported by the stock prebuilt .ko files
# must exist in the new kernel (vmlinux + GKI modules, from Module.symvers) with the CRC recorded in the
# module's __versions table, or be exported by another module in the checked sets.
#
# usage: kmi_gate.sh <new Module.symvers> <workdir> <label>=<dir-of-.ko> ...     scan .ko files
#        kmi_gate.sh <new Module.symvers> <workdir> @<dir>                         use a saved import list
#        kmi_gate.sh --save <dir> <label>=<dir-of-.ko> ...                         write imports.tsv + mod_exports.txt
# The saved list holds only symbol names, CRCs and module names (no vendor code), so CI can gate without
# the stock images. gate/stock-hyperos3/ in this repo was made from the HyperOS 3.0 amethyst modules.
set -uo pipefail

scan(){   # scan <W> <label>=<dir> ...
  local W=$1; shift; mkdir -p "$W"; : > "$W/imports.tsv"; : > "$W/mod_exports.txt"; : > "$W/modules.txt"
  for set in "$@"; do
    local label=${set%%=*} dir=${set#*=}
    while IFS= read -r ko; do
      local m; m=$(basename "$ko" .ko); echo -e "$label\t$m" >> "$W/modules.txt"
      modprobe --dump-modversions "$ko" 2>/dev/null | awk -v l="$label" -v m="$m" '{print l"\t"m"\t"$2"\t"$1}' >> "$W/imports.tsv"
      nm "$ko" 2>/dev/null | awk -v l="$label" -v m="$m" '$3 ~ /^__ksymtab_/ {s=$3; sub(/^__ksymtab_/,"",s); print s"\t"l":"m}' >> "$W/mod_exports.txt"
    done < <(find "$dir" -name '*.ko' | sort)
  done
  sort -o "$W/imports.tsv" "$W/imports.tsv"; sort -o "$W/mod_exports.txt" "$W/mod_exports.txt"
}

if [ "${1:-}" = --save ]; then D=$2; shift 2; scan "$D" "$@"; cut -f1 "$D/modules.txt" | sort | uniq -c; wc -l "$D/imports.tsv"; exit 0; fi

SYMVERS=$1; W=$2; shift 2
mkdir -p "$W"
if [ $# -eq 1 ] && [ "${1:0:1}" = @ ]; then
  cp "${1:1}/imports.tsv" "${1:1}/mod_exports.txt" "$W/"; cp "${1:1}/modules.txt" "$W/" 2>/dev/null || : > "$W/modules.txt"
else
  scan "$W" "$@"
fi
: > "$W/mismatch.txt"
awk -F'\t' -v W="$W" '
  FILENAME==ARGV[1] { crc[$2]=$1; next }               # Module.symvers: crc sym owner type
  FILENAME==ARGV[2] { prov[$1]=$2; next }              # module exports
  {
    lab=$1; mod=$2; sym=$3; want=$4; n[lab]++
    if (sym in crc) {
      if (tolower(crc[sym]) != tolower(want)) { bad[lab]++; print lab"\t"mod"\t"sym"\twant "want"\thave "crc[sym] > W"/mismatch.txt" }
    } else if (sym in prov) {
      viamod[lab]++
    } else { miss[lab]++; print lab"\t"mod"\t"sym"\twant "want"\tMISSING" > W"/mismatch.txt" }
  }
  END {
    printf "%-12s %8s %8s %10s %8s %8s\n", "set", "imports", "kernel", "via-module", "CRC-bad", "missing"
    for (l in n) { printf "%-12s %8d %8d %10d %8d %8d\n", l, n[l], n[l]-viamod[l]-miss[l], viamod[l], bad[l]+0, miss[l]+0; tb+=bad[l]; tm+=miss[l] }
    exit (tb+tm) > 0
  }' "$SYMVERS" "$W/mod_exports.txt" "$W/imports.tsv"
rc=$?
cut -f1 "$W/modules.txt" | sort | uniq -c | awk '{print "modules["$2"]="$1}'
echo "mismatch lines: $(wc -l < "$W/mismatch.txt")"
[ $rc -eq 0 ] || head -30 "$W/mismatch.txt"
exit $rc
