# BluedMC kernel for amethyst

GKI kernel for the **Redmi Note 14 Pro+ 5G (`amethyst`)**, SM7635 "volcano" (Snapdragon 7s Gen 3).
It's built on [TechAmethyst](https://github.com/TheTechGuy69/techamethyst-kernel) v1.2 (android14-6.1-2025-06_r17, Linux **6.1.138**, the same sublevel as stock), plus the [WildKernels](https://github.com/WildKernels/GKI_KernelSU_SUSFS) feature set and SM7635 compiler tuning.
The KMI stays identical, so Xiaomi's prebuilt vendor modules keep loading. Every build is gated against the imports of the stock `.ko` files.

> ⚠️ **Experimental.** A broken kernel means a boot loop. Keep a copy of the boot.img you run now, and an unlocked bootloader.

## Device
| | |
|---|---|
| Phone | Redmi Note 14 Pro+ 5G, `amethyst` |
| SoC | SM7635 "volcano": 4× Cortex-A520 + 3× A720 + 1× prime A720 (all Armv9.2-A), Adreno 810 |
| Stock kernel | `6.1.138-android14-11-g0c3d559bcd85` (HyperOS 3.0 vendor) |
| BluedMC kernel | android14-6.1 GKI, Linux 6.1.138 (stock sublevel), KMI generation 11 |

## Features
From TechAmethyst v1.2:
- **KernelSU-Next** (pershoot `dev-susfs`) built in, plus **SUSFS v2.x**. Use the **stock** init_boot, not a KSU-patched one.
- TCP BBR, NTFS3, a wakelock blocker (`/sys/module/wakeup/parameters/ta_ws_block`), MGLRU, zram lzo-rle.

Added by BluedMC (one commit each on the `kernel` branch):
| Commit | What |
|---|---|
| `brand` | `uname -r` ends in `-BluedMC-vX.Y`; status node `/sys/kernel/bluedmc/{version,features}` |
| `misc` | tmpfs xattr + POSIX ACL |
| `net` | IP sets, xt_set / addrtype / recent / LOG, IPv6 NAT + MASQUERADE, REJECT, CAKE, TTL/HL, connmark, BIC/Westwood/HTCP, WireGuard |
| `cifs` | SMB/CIFS client |
| `ntsync` | `/dev/ntsync` (Wine/Proton) |
| `bbg` | [Baseband Guard](https://github.com/vc-teahouse/Baseband-guard) LSM: blocks writes to critical partitions (modem, bootloaders, …) |
| `bbrv3` | TCP BBRv3, now the default congestion control (BBR v1 is still available as `bbr`) |
| `perf` | WildKernels performance patches (memcpy/memcmp/clear_page, f2fs/ext4/dcache tuning, log-spam cuts). The wakelock-timeout and freeze-timeout patches are left out. |
| `opt` | `-O3`, full LTO (CPU tuning: see `clang18`) |
| `lz4` | LZ4 v1.10.0 + arm64 NEON decompressor (zram uses lz4 on HyperOS; port by yuhangle) |
| `clang18` | built with AOSP clang 18 (r522817) and `-mtune=cortex-a720`. KCFI type hashes are identical to the clang 17 build, so vendor modules are unaffected. |
| `ksun` | **KernelSU-Next v3.4.2** (pershoot `dev-susfs` 4776e7c, version 33554) + **SUSFS v2.4.0** (susfs4ksu f76b81f): the same pair as WildKernels r23. Adds SUSFS priority-UID filter. Use KernelSU-Next manager v3.4.2 or newer. |

Opt-in variants (separate zips, experimental):
| Stage | What |
|---|---|
| `lean` | turns off `init_on_alloc`, kernel-stack offset randomisation and KFENCE defaults. Slightly faster, less hardened. |
| `autofdo` | profile-guided build from your own phone's kernel samples (docs/AUTOFDO.md) |


About `-mtune`: the AOSP clang 17 that the 6.1 manifest pins has no Cortex-A720 model, so TechAmethyst's `-mtune=cortex-a720` was silently dropped. BluedMC v1.1 tuned for the A710 instead. Since v1.2, BluedMC builds with clang 18, which does have the A720 model. This only changes instruction scheduling, not the instruction set.

## Why 6.1.138 (the stock sublevel)
On HyperOS, Xiaomi's prebuilt display driver (`msm_drm` / `mi_disp`) makes the screen **flicker or pulse** on newer GKI sublevels, even though every module loads cleanly.
BluedMC v1.0 (6.1.172) showed this on amethyst, and WildKernels issues #140 (amethyst, 6.1.141) and #283 (Xiaomi 14, 6.1.176) report the same; building on 6.1.138 fixes it.
A v1.0 test build without the `perf`/`opt` commits still flickered, so the sublevel jump is the cause, not BluedMC's additions.
**Don't move BluedMC off 6.1.138 until Xiaomi ships a newer stock kernel.**

## Installing (HyperOS)
Releases ship **one AnyKernel3 zip**: `BluedMC-vX.Y-amethyst-*.zip`, plus `SHA256SUMS` and `config.txt`.
It only replaces the kernel `Image` in your current `boot` partition. Your HyperOS ramdisk, init_boot, vendor_boot, dtbo and system_dlkm are all left as they are.

You need:
- an unlocked bootloader
- HyperOS with the 6.1.138 GKI kernel. The stock system_dlkm and vendor modules pass the KMI gate against this kernel.
- the **stock init_boot**. KernelSU-Next is built into the kernel; a Magisk/KSU-LKM-patched init_boot conflicts with it.
- a backup of your current boot. With root (single quotes outside, so PowerShell and bash both pass `$(...)` through to the phone):
  ```
  adb shell 'su -c "dd if=/dev/block/by-name/boot$(getprop ro.boot.slot_suffix) of=/sdcard/boot_backup.img"'
  adb pull /sdcard/boot_backup.img
  ```
  The file should be 100,663,296 bytes. Without root, use the `boot.img` from the HyperOS fastboot ROM of the **exact** version you run.

Flash the zip with one of:
- the **KernelSU-Next manager** (or another KSU/Magisk manager): Install → select the zip
- a custom recovery that supports amethyst
- [Kernel Flasher](https://github.com/capntrips/KernelFlasher)

Then reboot.

Developers can also build a fastboot `boot.img` with `BOOT_IMG=1 scripts/build.sh pack`.

**Check after boot**
```
adb shell uname -r                                   # ...-BluedMC-vX.Y
adb shell cat /sys/kernel/bluedmc/features
adb shell "su -c 'dmesg | grep -ciE \"disagrees about version|Unknown symbol|module verification failed\"'"   # 0
adb shell "su -c 'lsmod | wc -l'"                    # about the same as before (≈494)
```
Then check Wi-Fi, mobile data, touch, fingerprint, charging, camera, audio and deep sleep.

**Rollback:** in fastboot (Power + Volume down), run `fastboot flash boot boot_backup.img`, then `fastboot reboot`.

## Building
Local (WSL2/Linux on ext4, ~60 GB free, 16 GB+ RAM; full LTO wants ~24 GB RAM+swap):
```bash
git clone https://github.com/BluedMC-Amethyst/kernel_xiaomi_amethyst bluedmc && cd bluedmc
TOP=~/AmethystGKI/ws138 scripts/build.sh setup          # Kleaf workspace + kernel branch as common/
TOP=~/AmethystGKI/ws138 scripts/build.sh setup_clang18  # AOSP clang 18 (r522817), registered with Kleaf
TOP=~/AmethystGKI/ws138 scripts/build.sh all            # build -> KMI gate -> AnyKernel3 zip in dist/
```
Optional `BOOT_IMG=1` also makes a fastboot boot.img. `BOOT_TEMPLATE=<boot.img of your ROM>` copies that image's patch level and AVB props.
`LTO=thin` builds faster.

GitHub Actions: **Actions → Build BluedMC kernel → Run workflow**. Give it a `release_tag` to publish a pre-release.

### Making a new version
The feature commits are produced by `scripts/bluedmc_features.sh`, starting from TechAmethyst's `v1.3` tag:
```bash
git -C $TOP/common checkout -B kernel v1.2       # TechAmethyst v1.2 (6.1.138)
BMC_VER=v1.2 scripts/bluedmc_features.sh brand   # then build + gate after each stage
scripts/bluedmc_features.sh misc ...              # stages: brand misc net cifs ntsync bbg bbrv3 perf opt lz4 clang18 ksun
```

### KMI gate
`tools/kmi_gate.sh` (from TechAmethyst) checks every symbol that every stock module imports against the new `Module.symvers`.
`gate/stock-hyperos3/` holds the import list of the HyperOS 3.0 amethyst modules: vendor_boot 344, vendor_dlkm 311, system_dlkm 60, 38,942 imports.
It has only symbol names, CRCs and module names, with no vendor code, so CI can gate without the stock images. To regenerate it:
```
tools/kmi_gate.sh --save gate/stock-hyperos3 vendor_boot=<dir> vendor_dlkm=<dir> system_dlkm=<dir>
```

## Repository layout
| Branch | Content |
|---|---|
| `main` | scripts, tools, CI, gate data, changelogs |
| `kernel` | full kernel source: TechAmethyst history + one BluedMC commit per feature |

## Credits
TechAmethyst by TheTechGuy69 · WildKernels (GKI_KernelSU_SUSFS, kernel_patches) · KernelSU-Next (rifsxd) and the pershoot fork · susfs4ksu (simonpunk) · Baseband-guard (vc-teahouse) · AnyKernel3 (osm0sis; arm64 tools from WildKernels/AnyKernel3) · Google's Android Common Kernel and Kleaf.

## License
GPL-2.0. The kernel source of every release is on the `kernel` branch, tagged with the release version.

No warranty. You flash at your own risk.
