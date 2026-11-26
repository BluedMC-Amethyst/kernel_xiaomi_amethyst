### AnyKernel3 Ramdisk Mod Script - BluedMC @VER@ for Redmi Note 14 Pro+ 5G (amethyst)
### kernel: @REL@
## osm0sis @ xda-developers; arm64 tools from WildKernels/AnyKernel3 (gki-2.0):
## SM7635 cores (Cortex-A720/A520) are AArch64-only, so upstream's 32-bit busybox cannot run.

### AnyKernel setup
properties() { '
kernel.string=BluedMC @VER@ (amethyst, android14-6.1 GKI, KernelSU-Next + SUSFS)
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
do.check_boot_version=0
device.name1=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
## GKI: kernel lives in boot, ramdisk in init_boot -> only swap the kernel
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

. tools/ak3-core.sh

# device check: HyperOS build props say miproduct/mivendor/missi, so check what the bootloader
# reports (ro.boot.hwname) first, then the usual product props
amethyst_ok=0
for p in ro.boot.hwname ro.product.device ro.product.odm.device ro.build.product ro.product.vendor.device; do
  case "$(getprop $p 2>/dev/null)" in
    *amethyst*) amethyst_ok=1; ui_print "Device: amethyst ($p)"; break;;
  esac
done
[ "$amethyst_ok" = 1 ] || abort "This kernel is only for the Redmi Note 14 Pro+ 5G (amethyst). Aborting..."

# GKI 6.1 check (running kernel)
case "$(uname -r)" in
  6.1.*) ;;
  *) abort "Running kernel $(uname -r) is not android14-6.1 GKI. Aborting...";;
esac

ui_print " " "Installing BluedMC @VER@"
ui_print "  @REL@"

split_boot
if [ -f "$SPLITIMG/ramdisk.cpio" ]; then
  unpack_ramdisk
  write_boot
else
  flash_boot
fi

ui_print " " "Done. Keep your boot backup for rollback (fastboot flash boot boot_backup.img)."
