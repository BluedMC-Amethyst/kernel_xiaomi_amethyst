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

## Sources
- Android zero-initialised memory (GKI defaults): https://source.android.com/docs/security/memory-safety/zero-initialized-memory
- init_on_alloc overhead discussion (upstream): https://lore.kernel.org/linux-mm/201905161714.A53D472D9@keescook/ , https://kernsec.org/pipermail/linux-security-module-archive/2019-June/014813.html
- SM7635 hardware: https://wiki.postmarketos.org/wiki/Qualcomm_Snapdragon_7s_Gen_3_(SM7635)
- amethyst storage bottleneck: https://m.gsmarena.com/xiaomi_redmi_note_14_pro_plus-review-2788p4.php
- Local evidence: stock module list (~/AndroidBuilds/EvolutionX/device/xiaomi/amethyst-kernel/modules), HyperOS `vendor/bin/init.kernel.post_boot-*.sh` and `init.kernel.post_boot-memory.sh`, BluedMC v1.1 `config.txt`, clang r487747c `--print-supported-cpus` (no cortex-a720).
