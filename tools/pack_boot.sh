#!/bin/bash
# BluedMC boot.img packer (no stock image needed).
# Builds a GKI boot.img the way amethyst expects it: boot header v4, raw arm64 Image, empty ramdisk,
# empty cmdline, 100663296-byte partition with an AVB hash footer.
#
# usage: pack_boot.sh <Image> <out boot.img> [template boot.img]
#   template: if given, os_version / os_patch_level, AVB props, rollback index and algorithm are taken
#             from it (e.g. the boot.img of the ROM you run), so the new image matches it exactly.
# env:
#   MKBOOTIMG_DIR  dir with mkbootimg.py + unpack_bootimg.py   (default: $TOP/tools/mkbootimg)
#   AVBTOOL        avbtool                                      (default: $TOP/prebuilts/kernel-build-tools/linux-x86/bin/avbtool)
#   AVB_KEY        key to sign the footer with. "testkey" = AOSP external/avb test key, which is what
#                  LineageOS/EvolutionX-style amethyst ROMs sign boot with. Empty = unsigned footer
#                  (like stock-style TechAmethyst images; fine on an unlocked bootloader).
#   OS_VERSION / OS_PATCH_LEVEL   header fields if no template (default 14.0.0 / 2026-06)
#   PART_SIZE      boot partition size (default 100663296)
#   SALT           auto = sha256 of the image (byte-reproducible), <hex>, or unset (random)
set -euo pipefail
IMG=$1; OUTIMG=$2; TPL=${3:-}
TOP=${TOP:-$HOME/AmethystGKI/ws}
MKB=${MKBOOTIMG_DIR:-$TOP/tools/mkbootimg}
AVB=${AVBTOOL:-$TOP/prebuilts/kernel-build-tools/linux-x86/bin/avbtool}
PART_SIZE=${PART_SIZE:-100663296}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

file -b "$IMG" | grep -q 'ARM64 boot executable' || { echo "not a raw arm64 Image: $IMG"; exit 1; }
osv=${OS_VERSION:-14.0.0}; ospl=${OS_PATCH_LEVEL:-2026-06}
avbargs=()
if [ -n "$TPL" ]; then
  python3 "$MKB/unpack_bootimg.py" --boot_img "$TPL" --out "$W/tpl" --format=mkbootimg > "$W/args.txt"
  grep -q -- '--header_version 4' "$W/args.txt" || { echo "template is not boot header v4"; exit 1; }
  [ ! -s "$W/tpl/ramdisk" ] || echo "note: template has a non-empty ramdisk; BluedMC boot.img keeps it empty (ramdisk is in init_boot)"
  osv=$(sed -n 's/.*--os_version \([^ ]*\).*/\1/p' "$W/args.txt"); ospl=$(sed -n 's/.*--os_patch_level \([^ ]*\).*/\1/p' "$W/args.txt")
  PART_SIZE=$(stat -c%s "$TPL")
  "$AVB" info_image --image "$TPL" > "$W/tpl_avb.txt"
  while IFS= read -r l; do avbargs+=(--prop "$l"); done < <(sed -n "s/^ *Prop: \(.*\) -> '\(.*\)'\s*$/\1:\2/p" "$W/tpl_avb.txt")
  ri=$(sed -n 's/^Rollback Index: *//p' "$W/tpl_avb.txt"); [ -n "$ri" ] && [ "$ri" != 0 ] && avbargs+=(--rollback_index "$ri")
  if [ -z "${AVB_KEY+x}" ] && grep -q '^Algorithm: *SHA256_RSA2048' "$W/tpl_avb.txt"; then
    AVB_KEY=testkey; echo "template is signed (SHA256_RSA2048) -> signing with the AOSP test key; set AVB_KEY= to disable"
  fi
fi
: > "$W/ramdisk"
python3 "$MKB/mkbootimg.py" --header_version 4 --os_version "$osv" --os_patch_level "$ospl" \
  --kernel "$IMG" --ramdisk "$W/ramdisk" --cmdline '' --output "$W/boot.img"
python3 "$MKB/unpack_bootimg.py" --boot_img "$W/boot.img" --out "$W/verify" >/dev/null
cmp -s "$W/verify/kernel" "$IMG" || { echo "kernel in boot.img != Image"; exit 1; }

case "${AVB_KEY:-}" in
  "") ;;
  testkey) k=$(find "$TOP/external/avb" "$MKB" -name testkey_rsa2048.pem -print -quit 2>/dev/null)
           [ -n "$k" ] || { echo "testkey_rsa2048.pem not found"; exit 1; }
           avbargs+=(--algorithm SHA256_RSA2048 --key "$k");;
  *) avbargs+=(--algorithm SHA256_RSA2048 --key "$AVB_KEY");;
esac
case "${SALT:-}" in
  "") ;; auto) avbargs+=(--salt "$(sha256sum "$W/boot.img" | cut -d' ' -f1)");; *) avbargs+=(--salt "$SALT");;
esac
"$AVB" add_hash_footer --image "$W/boot.img" --partition_name boot --partition_size "$PART_SIZE" \
  --hash_algorithm sha256 "${avbargs[@]}"
[ "$(stat -c%s "$W/boot.img")" = "$PART_SIZE" ] || { echo "footer size mismatch"; exit 1; }
"$AVB" info_image --image "$W/boot.img" | grep -E 'Algorithm|Rollback Index:|Partition Name|Prop' || true
mkdir -p "$(dirname "$OUTIMG")"; cp "$W/boot.img" "$OUTIMG"
echo "boot.img: $OUTIMG (header v4, os $osv / $ospl, ${PART_SIZE} bytes)"
