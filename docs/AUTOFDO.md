# AutoFDO for BluedMC (experimental)

AutoFDO compiles the kernel with a profile of how *your phone* actually runs it. Clang then inlines, lays out and optimises the hot paths (syscalls, scheduler, f2fs, networking) based on real use.
Typical gains on kernel-heavy work are a few percent. A bad profile can make things a little slower, but never incorrect. Every AFDO build still goes through the KMI gate.

## Why it's done this way on amethyst
- Normal AutoFDO uses branch traces (Intel LBR / Arm ETM or SPE). amethyst has **no ETM/SPE driver** (only Qualcomm's coresight modules, no `coresight-etm4x`), and LLVM's `llvm-profgen` refuses data without branch records.
- So BluedMC uses **plain CPU-cycle samples**, like Google AutoFDO's sample-only mode. `tools/afdo/afdo_convert.py` maps each sampled kernel address to its function, source line and inline chain with `llvm-symbolizer`. It takes the max count per source line and writes an LLVM sample profile.
- 6.1 has no `CONFIG_AUTOFDO_CLANG` (that's 6.13+). The `autofdo` stage adds the same compiler and linker flags upstream uses (`-fdebug-info-for-profiling -fprofile-sample-use … --lto-sample-profile`), minus `-fsplit-machine-functions`, which 6.1's linker script can't place.

## Sample skid on amethyst (handled by the converter)
- Without pseudo-NMI (`irqchip.gicv3_pseudo_nmi` isn't on the bootloader command line), the PMU interrupt can't fire while the kernel has IRQs masked.
- Samples from IRQs-off code are counted at the instruction that unmasks them. In the first recording (10.4M samples, 10 minutes of normal use), about 45% landed on `finish_task_switch` and `_raw_spin_unlock_irqrestore`/`_irq`, and about 20% on idle (`cpuidle_enter_state`).
- `afdo_convert.py` therefore drops idle samples (`--exclude-funcs`) and caps every address at the 99.9th percentile (`--clamp-pct`), so those few artefact addresses can't dominate the profile.
- After that, the hottest code is what you'd expect from Android: fd lookup, VMA walks, page faults, binder, slab, SELinux AVC, epoll.

## Steps
1. Run a BluedMC build on the phone, and keep its Kleaf dist dir (`vmlinux`, `System.map`).
2. Record on the phone (root), using it normally for 5–10 minutes: apps, scrolling, camera, a game, Wi-Fi/data:
   ```
   adb push tools/afdo/afdo_record.sh /data/local/tmp/
   adb shell 'su -c "sh /data/local/tmp/afdo_record.sh 600"'
   adb pull /sdcard/bluedmc-afdo
   ```
   Only kernel-mode samples (`cpu-cycles:k`) are recorded, with no app data. The script restores `perf_event_paranoid` and `kptr_restrict` afterwards.
3. Make the profile (on the PC):
   ```
   tools/afdo/make_profile.sh bluedmc-afdo ~/AmethystGKI/ws138/out/v1.2
   ```
4. Build the AFDO kernel on an experimental branch:
   ```
   git -C $TOP/common checkout -B kernel-afdo kernel
   AFDO_PROFILE=bluedmc-afdo/bluedmc.afdo scripts/bluedmc_features.sh autofdo
   OUT=$TOP/out/afdo DIST=dist/afdo scripts/build.sh all
   ```
5. Benchmark against the same build without AFDO (see docs/OPTIMISATION.md section 5). Only adopt it if it measures faster.

Refresh the profile when the kernel changes a lot. A stale profile just matches less code, so it's still safe.
