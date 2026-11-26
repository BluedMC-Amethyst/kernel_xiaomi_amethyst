#!/usr/bin/env bash
# build.sh - build, KMI-gate and package the BluedMC kernel (local WSL and GitHub Actions)
#
#   scripts/build.sh setup     repo init/sync the Kleaf workspace + clone the BluedMC kernel source as common/
#   scripts/build.sh build     bazel build //common:kernel_aarch64_dist
#   scripts/build.sh gate      KMI gate: every stock module import vs the new Module.symvers  (bootloop gate)
#   scripts/build.sh pack      AnyKernel3 zip + SHA256SUMS  (BOOT_IMG=1 also makes a fastboot boot.img)
#   scripts/build.sh all       build gate pack     (setup is separate)
#
# env: TOP=~/AmethystGKI/ws  OUT=$TOP/out/bluedmc  DIST=$REPO/dist  JOBS=$(nproc)  LTO=full|thin|default
#      KERNEL_REPO / KERNEL_REF  (source for setup; default this repo's `kernel` branch)
#      GATE=@gate/stock-hyperos3  (or "vendor_boot=<dir> vendor_dlkm=<dir> system_dlkm=<dir>")
#      BOOT_TEMPLATE=<boot.img of your ROM> (optional; copies its AVB props / patch level / signing)
#      AVB_KEY=testkey|<pem>|""   (see tools/pack_boot.sh)
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
TOP=${TOP:-$HOME/AmethystGKI/ws}
OUT=${OUT:-$TOP/out/bluedmc}
DIST=${DIST:-$REPO/dist}
JOBS=${JOBS:-$(nproc)}
LTO=${LTO:-full}
MANIFEST_BRANCH=${MANIFEST_BRANCH:-common-android14-6.1-2026-06}
KERNEL_REPO=${KERNEL_REPO:-https://github.com/BluedMC-Amethyst/kernel_xiaomi_amethyst}
KERNEL_REF=${KERNEL_REF:-kernel}
GATE=${GATE:-@$REPO/gate/stock-hyperos3}
say(){ printf '\n\033[1;36m[BluedMC] %s\033[0m\n' "$*"; }
die(){ printf '\n\033[1;31m[ERROR] %s\033[0m\n' "$*"; exit 1; }

stage_setup(){
  say "setup Kleaf workspace $TOP ($MANIFEST_BRANCH)"
  mkdir -p "$TOP"; cd "$TOP"
  [ -d .repo ] || repo init -u https://android.googlesource.com/kernel/manifest -b "$MANIFEST_BRANCH" --depth=1
  # common/ is replaced by the BluedMC tree; drop it from the sync to save ~2 GB
  mkdir -p .repo/local_manifests
  cat > .repo/local_manifests/bluedmc.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest><remove-project name="kernel/common" /></manifest>
EOF
  repo sync -c --no-tags --no-clone-bundle -j"$JOBS"
  if [ ! -d common/.git ]; then
    git clone --depth 1 -b "$KERNEL_REF" "$KERNEL_REPO" common
  else
    git -C common fetch --depth 1 origin "$KERNEL_REF" && git -C common checkout -q -f FETCH_HEAD
  fi
  # Kleaf stamp: no "-maybe-dirty" in uname -r (same one-line edit TechAmethyst uses)
  sed -i "/stable_scmversion_cmd/s/-maybe-dirty//g" build/kernel/kleaf/impl/stamp.bzl
  say "source: $(git -C common log -1 --format='%h %s')"
}

stage_build(){
  say "build (lto=$LTO, jobs=$JOBS) -> $OUT"
  cd "$TOP"
  local lto=(); [ "$LTO" = default ] || lto=(--lto="$LTO")
  env -u BUILD_NUMBER tools/bazel run --config=stamp "${lto[@]}" --jobs="$JOBS" \
      //common:kernel_aarch64_dist -- --dist_dir="$OUT"
  [ -f "$OUT/Image" ] || die "no Image"; strings "$OUT/Image" | grep '^Linux version [0-9]' | head -1 || true
}

stage_gate(){
  say "KMI gate vs stock modules ($GATE)"
  # shellcheck disable=SC2086
  bash "$REPO/tools/kmi_gate.sh" "$OUT/kernel_aarch64_Module.symvers" "$OUT/gate" $GATE \
    || die "KMI gate FAILED - vendor modules would not load. Do NOT flash. See $OUT/gate/mismatch.txt"
  say "KMI gate passed"
}

stage_pack(){
  local rel; rel=$(strings "$OUT/Image" | sed -n '/^Linux version [0-9]/{s/^Linux version \([^ ]*\) .*/\1/p;q}' || true)
  local ver; ver=$(echo "$rel" | sed -n 's/.*-BluedMC-\(v[0-9.]*\).*/\1/p'); ver=${ver:-dev}
  say "pack $rel"
  rm -rf "$DIST"; mkdir -p "$DIST"
  if [ "${BOOT_IMG:-0}" = 1 ]; then
    TOP=$TOP bash "$REPO/tools/pack_boot.sh" "$OUT/Image" "$DIST/boot.img" ${BOOT_TEMPLATE:-}
  fi

  local A=$TOP/out/AnyKernel3 Z=$TOP/out/ak3
  [ -d "$A/.git" ] || git clone -q --depth 1 https://github.com/osm0sis/AnyKernel3 "$A"
  rm -rf "$Z"; mkdir -p "$Z"; cp -r "$A"/. "$Z"/
  rm -rf "$Z/.git" "$Z/.github" "$Z/README.md" "$Z/ramdisk" "$Z/patch" "$Z/modules"
  sed "s/@VER@/$ver/; s/@REL@/$rel/" "$REPO/anykernel/anykernel.sh" > "$Z/anykernel.sh"
  cp "$OUT/Image" "$Z/Image"
  local zip="BluedMC-$ver-amethyst-$(date -u +%Y%m%d).zip"
  ( cd "$Z" && zip -qr9 "$DIST/$zip" . -x '.git*' )
  cp "$OUT/.config" "$DIST/config.txt" 2>/dev/null || "$TOP/common/scripts/extract-ikconfig" "$OUT/Image" > "$DIST/config.txt" 2>/dev/null || true
  echo "$rel" > "$DIST/uname.txt"
  ( cd "$DIST" && sha256sum "$zip" $( [ -f boot.img ] && echo boot.img ) > SHA256SUMS )
  ls -la "$DIST"; cat "$DIST/SHA256SUMS"
}

[ $# -gt 0 ] || set -- all
for s in "$@"; do
  case $s in
    setup|build|gate|pack) "stage_$s";;
    all) stage_build; stage_gate; stage_pack;;
    *) die "usage: $0 [setup|build|gate|pack|all]";;
  esac
done
