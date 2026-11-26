### AnyKernel3 Ramdisk Mod Script - BluedMC @VER@ for Redmi Note 14 Pro+ 5G (amethyst)
### kernel: @REL@
properties() { '
kernel.string=BluedMC @VER@ (amethyst, android14-6.1 GKI, KernelSU-Next + SUSFS)
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=amethyst
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### GKI: kernel lives in boot, ramdisk in init_boot -> only swap the kernel
BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

# device check: HyperOS build props say miproduct/mivendor/missi, so check what the bootloader
# reports (ro.boot.hwname) first, then the usual product props
amethyst_ok=0;
for p in ro.boot.hwname ro.product.device ro.product.odm.device ro.build.product ro.product.vendor.device; do
  case "$(file_getprop /system/build.prop $p 2>/dev/null; getprop $p 2>/dev/null)" in
    *amethyst*) amethyst_ok=1; ui_print "Device: amethyst ($p)"; break;;
  esac;
done;
[ "$amethyst_ok" = 1 ] || abort "This kernel is only for the Redmi Note 14 Pro+ 5G (amethyst). Aborting...";

split_boot;
flash_boot;
