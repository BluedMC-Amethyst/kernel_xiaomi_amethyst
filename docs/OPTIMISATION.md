# How far can BluedMC be optimised on amethyst?

Research notes, 2026-11-26. Context: BluedMC v1.1 (6.1.138 GKI, KernelSU-Next + SUSFS, BBRv3, WildKernels perf patches, `-O3`, full LTO), running on HyperOS 3.0.306.

## The hard limit: what the kernel image actually controls
On amethyst, almost everything that decides speed, smoothness and battery life is a **prebuilt Xiaomi/Qualcomm module**, not code in our `Image`:

| Area | Owned by (stock .ko) | Can BluedMC change it? |
|---|---|---|
| Task placement / scheduler policy | `sched-walt`, `mi_schedule`, `sched-penalty` (via vendor hooks) | No. CFS patches in our kernel are mostly bypassed by WALT. |
| CPU frequency / DCVS | `qcom-cpufreq-hw`, `c1dcvs_scmi_v2`, `qcom_cpucp` (firmware via SCMI) | No |
| CPU idle | `qcom_lpm` | No |
| Thermal / throttling | `thermal_*`, `bcl_*`, `mi_thermal_interface` | No |
| GPU, display | `msm_kgsl`, `msm_drm` | No (the 6.1.172 flicker showed how sensitive `msm_drm` is) |
| zram / zsmalloc | `zram.ko`, `zsmalloc.ko` (stock system_dlkm) | Partly: the **compressor** (lz4) is built into our kernel |
| Memory reclaim extras | `mi_async_reclaim`, `mi_mempool`, `mi_memory` | No |
| Undervolting | CPUCP firmware via SCMI | No. There are no voltage tables in the kernel. |

Also fixed by the prebuilt modules, and dangerous to change:
- **HZ** (250). Vendor modules have `msecs_to_jiffies()` inlined for HZ=250.
- **CFI / shadow call stack / DEBUG_LIST.** Vendor modules are compiled to expect them (KCFI hashes, `__list_add_valid` imports).
- **Sublevel.** Anything other than 6.1.138 makes the HyperOS display flicker (v1.0, WildKernels #140/#283).

So the kernel-image headroom left after v1.1 is in **codegen** and **a few hot core-kernel paths** (syscalls, page allocation, compression, networking, filesystem). Expect single-digit-percent gains there. The bigger visible wins are in **userspace tuning** (section 4).

## 1. Cheap, low-risk kernel changes (good candidates for v1.2)
None of these touch genksyms input, so the KMI gate should stay clean. Each still gets built, gated and device-tested.

| Change | Expected gain | Trade-off |
|---|---|---|
| `CONFIG_INIT_ON_ALLOC_DEFAULT_ON=n` | <1% typical, ~3% in syscall/alloc-heavy loads (upstream hackbench numbers) | Loses zero-on-alloc hardening that Android's CDD recommends; uninitialised-memory leaks become possible again |
| `CONFIG_RANDOMIZE_KSTACK_OFFSET_DEFAULT=n` | Small per-syscall saving | Weaker stack-layout randomisation |
| `CONFIG_KFENCE_SAMPLE_INTERVAL=0` | Negligible | Loses sampled memory-error detection |

Proposal: ship these as an opt-in `lean` stage, so the default build keeps Google's hardening.

## 2. Medium effort, real gains
**a) Faster LZ4 for zram.** HyperOS sets `echo lz4 > /sys/block/zram0/comp_algorithm` (`init.kernel.post_boot-memory.sh`). The LZ4 code it runs is **built into our kernel** (`lib/lz4`, `CONFIG_CRYPTO_LZ4=y`).
- Backporting a newer `lib/lz4`, and the arm64-optimised decompressor several OEM kernels carry, speeds up swap-in. App switching on a 12 GB phone that swaps heavily benefits directly.
- KMI: `LZ4_*` exports keep their prototypes, so CRCs are unchanged; the gate verifies it.

**b) Newer AOSP clang (18/19 instead of 17.0.2).**
- It gets a real **Cortex-A720 scheduling model**. Clang 17 has none, which is why we tune for A710, and why TechAmethyst's `-mtune=cortex-a720` silently did nothing.
- Better codegen and LTO overall.
- Symbol CRCs come from genksyms (source-level), and KCFI type hashes are stable across clang versions, so vendor modules should still load. Still, this is a toolchain change, so it gets its own experimental build and a boot test before a release.

**c) Polly** (`-mllvm -polly`, supported by the pinned clang). The kernel is built `-mgeneral-regs-only` (no SIMD), so polyhedral loop optimisation has little to work on. Low priority; only worth it with a benchmark showing a gain.

## 3. Heavy effort: profile-guided optimisation (AutoFDO)
- Google uses AutoFDO for newer GKI branches. 6.1 has **no** `CONFIG_AUTOFDO_CLANG` (it arrived in 6.13), so the build flags would need a backport. That part is small.
- The hard part is the **profile**. Best-quality AutoFDO needs ETM/SPE branch tracing. amethyst ships Qualcomm coresight modules, but **no `coresight-etm4x` or SPE driver**, and our config has neither.
- Plain `simpleperf` cycle sampling works, but gives weaker profiles.
- Realistic gain: a few percent on kernel-heavy workloads, for significant work (collect profiles on device → convert → rebuild → re-gate).
- Worth doing only after 1 and 2 are done and measured.

## 4. Userspace tuning (biggest visible impact, no kernel risk)
A KernelSU module (`service.sh`) can retune what Xiaomi's vendor scripts set at boot, for example in `init.kernel.post_boot-volcano_default_4_3_1.sh`:
- **WALT** (`/proc/sys/walt/*`):
  - `sched_fmax_cap` (stock writes `1708800 2208000 2147483647`). Correction: Xiaomi's script comment says this caps silver and gold only **"when load is not detected"**; the prime core is uncapped. It's a light-load efficiency cap, not a performance ceiling, so lifting it mostly costs battery.
  - `sched_upmigrate` / `sched_downmigrate`
  - input boost frequency and duration
  - `sched_util_busy_hyst_*`
- **Memory:** zram size, `swappiness`, and MGLRU `min_ttl_ms`.
- **Storage:** block read-ahead on the UFS device. GSMArena found storage, not the CPU, holding amethyst back in AnTuTu.
- **Network:** fq qdisc defaults for BBRv3.

Caveat: HyperOS's own perf and thermal daemons (MIUI/Joyose, `mi_thermal_interface`, the QTI perf HAL) rewrite some of these at runtime. Every knob has to be checked for being overwritten, and higher caps cost heat and battery.

## 5. How to know a change helped
Nothing above should ship on "should be faster". Per candidate build:
- Geekbench 6 (CPU), PCMark Work 3.0 (UI/storage/real tasks), 3DMark Wild Life Extreme stress (sustained GPU and thermals), all 3 runs each, same battery level and temperature
- app-switching time with the same app set (zram path)
- 30-minute screen-off drain, and 1 hour of mixed use
- `dmesg` module-error check (must stay 0)

## Status (2026-11-26)
All four steps below are implemented:
1. **v1.2**: LZ4 v1.10.0 + arm64 NEON decompressor (`lz4` stage), plus the opt-in `lean` stage (zip `-lean`)
2. **clang18**: experimental build with AOSP clang r522817 and `-mtune=cortex-a720` (zip `-clang18`)
3. ~~BluedMC Tuning module~~: dropped (not wanted). Section 4 stays as reference for manual tuning.
4. **AutoFDO** tooling (`tools/afdo/`, `autofdo` stage, docs/AUTOFDO.md). It still needs a recording from the phone.

## Recommended roadmap
1. **v1.2:** faster LZ4 (2a) plus an opt-in `lean` config stage (section 1). Benchmark against v1.1.
2. **Experimental build:** clang 18/19 with `-mtune=cortex-a720` (2b). Boot-test, then benchmark.
3. ~~Tuning module~~: dropped.
4. **Only then:** AutoFDO (section 3).

## Round 2 research (2026-11-27)

### Correction: zram probably doesn't use lz4 on amethyst
- The vendor script only sets `lz4` when `ro.config.low_ram=true`, which a 12 GB phone isn't.
- HyperOS also disables that path (`vendor.zram.disable=1`). Zram is set up by Xiaomi's `system_ext/xbin/system_perf_init` from `perfinit_bdsize_zram.conf`, which sets size (12 GB) and flash writeback (4–6 GB), but **no compressor**.
- So zram most likely runs the stock module default, `lzo-rle`, and v1.2's LZ4/NEON speed-up then only helps f2fs/EROFS/incfs.
- **To verify on device:** `cat /sys/block/zram0/comp_algorithm`
- If it is lzo-rle, switching to lz4 is the biggest remaining win: faster decompression on every swap-in, now with NEON. The compressor must be written before `system_perf_init` sets `disksize` (it runs "after load_persist_props, before zygote"). A one-line `post-fs-data` script would do it.
- zram.ko is a stock module, so the kernel can't change its compiled-in default.

### Lazy RCU is compiled in but probably inactive
- `CONFIG_RCU_LAZY=y` and `CONFIG_RCU_NOCB_CPU=y`, but lazy batching only applies to CPUs offloaded with `rcu_nocbs=`. Neither the device tree nor vendor_boot's bootconfig sets it.
- Upstream patches cite ~5–10% of idle/light-load power going to RCU work; Android and ChromeOS were the intended users.
- The GKI config has `CONFIG_CMDLINE_EXTEND=y`, so BluedMC can append `rcu_nocbs=0-7` to its built-in command line with no vendor change.
- **To verify on device:** `cat /proc/cmdline` (the Qualcomm bootloader may already add it).

### KASAN (MTE hardware tags) is compiled in
- `CONFIG_KASAN_HW_TAGS=y`. The A720/A520 support MTE. If the firmware enables MTE, KASAN tag checking runs on every allocation, at a real cost.
- **To verify on device:** `dmesg | grep -i kasan` and `grep -c mte /proc/cpuinfo`
- If it's active, `kasan=off` on the built-in command line is a sizeable win.

### Verified on device (v1.2, HyperOS 3.0.306, 2026-11-27)
| Check | Result | Outcome |
|---|---|---|
| `/sys/block/zram0/comp_algorithm` | `lzo [lzo-rle] lz4 zstd` | **zram uses lzo-rle.** Switch it to lz4 (e.g. in a kernel manager app, set on boot) so v1.2's NEON LZ4 is used for swap. After a zram reset, Xiaomi's flash writeback device may not be re-attached. |
| `/proc/cmdline` `rcu_nocbs` | `rcu_nocbs=0-7` from the Qualcomm bootloader | Lazy RCU is **already active**. Nothing to add. |
| KASAN | bootloader passes `kasan=off`; `/proc/cpuinfo` has no `mte` | **Already off.** Nothing to gain. |
| `rcupdate.rcu_expedited=1` | set by the bootloader, never reset by HyperOS/AOSP init | Expedited RCU stays on after boot: lower `synchronize_rcu()` latency, some power cost. Optional experiment only: `echo 0 > /sys/kernel/rcu_expedited` (root) and compare battery and smoothness. |

Other bootloader parameters worth knowing about: `irqaffinity=0-3` (IRQs on the little cores), `kpti=0`, `cgroup.memory=nokmem,nosocket`, `ufshcd-core.use_mcq_mode=n` (the UFS 2.2 chip has no MCQ anyway).

### Checked and rejected
| Idea | Why not |
|---|---|
| f2fs-stable backport | Its 6.1 branch stopped at 6.9-rc1 (March 2024), and the Android tree already has newer f2fs fixes of its own (e.g. `lookup_mode`). f2fs holds userdata, so a swap risks data loss for no proven gain. |
| `mitigations=off` | The A520 is Spectre-BHB safe; the A720 runs a 38-iteration BHB-clearing loop per kernel entry (≈1–2% on syscall-heavy loads). Removing it lets apps attack kernel memory. A worse trade than `lean`. |
| SCHED_CLUSTER, CFS/EEVDF changes | Task placement is WALT's (vendor module), so CFS tuning is bypassed |
| mTHP / CONTPTE / per-VMA-lock backports | Change KMI structs (`mm_struct`, `vm_area_struct`, `zone`), and per-VMA locks are already in this tree |

### Low priority
- **MLGO register allocation** (`-mllvm -regalloc-enable-advisor=release`, works with clang 18): 0.3–1.5% on Google datacenter code, no kernel/arm64 data, and the model was trained on x86. Try only with benchmarks.
- **Newer clang (19/20):** marginal over 18.
- **AutoFDO:** tooling is ready (docs/AUTOFDO.md) and needs one phone recording. Still the largest compiler-side gain available.

## Sources
- Lazy RCU: https://lkml.org/lkml/2022/11/30/945 , https://lpc.events/event/16/contributions/1204/attachments/985/2008/Make%20RCU%20do%20less%20(and%20later)!%20(3).pdf , https://android.googlesource.com/kernel/common/+/refs/heads/android-mainline/kernel/rcu/Kconfig
- MLGO: https://www.research.google/blog/mlgo-a-machine-learning-framework-for-compiler-optimization/ , https://www.llvm.org/devmtg/2025-04/slides/quick_talk/grossman_accurate_runtime.pdf
- f2fs-stable: https://git.kernel.org/pub/scm/linux/kernel/git/jaegeuk/f2fs-stable.git (linux-6.1.y)
- Android zero-initialised memory (GKI defaults): https://source.android.com/docs/security/memory-safety/zero-initialized-memory
- init_on_alloc overhead discussion (upstream): https://lore.kernel.org/linux-mm/201905161714.A53D472D9@keescook/ , https://kernsec.org/pipermail/linux-security-module-archive/2019-June/014813.html
- SM7635 hardware: https://wiki.postmarketos.org/wiki/Qualcomm_Snapdragon_7s_Gen_3_(SM7635)
- amethyst storage bottleneck: https://m.gsmarena.com/xiaomi_redmi_note_14_pro_plus-review-2788p4.php
- Local evidence: stock module list (~/AndroidBuilds/EvolutionX/device/xiaomi/amethyst-kernel/modules), HyperOS `vendor/bin/init.kernel.post_boot-*.sh` and `init.kernel.post_boot-memory.sh`, BluedMC v1.1 `config.txt`, clang r487747c `--print-supported-cpus` (no cortex-a720).

## Tried and dropped: -march=armv9.2-a (2026-11-28)
Built with clang 20 and `-march=armv9.2-a+nopauth`: the generated code is identical to the default target
(7,023,196 instructions, same opcode histogram). The kernel is compiled with `-mgeneral-regs-only` (no
FP/SIMD/SVE), and it already emits LSE atomics, RCpc loads and CRC32 through its own runtime-patched
assembly, so a newer -march has nothing left to change.
