# Amethyst GKI Kernel

An unofficial Generic Kernel Image (GKI) kernel project for the **Redmi Note 14 Pro+ 5G** (codename **amethyst**).

This repository is intended to document the kernel source, build process, and device-specific releases. It currently contains no kernel source, build scripts, or release images, so there is not yet a build or installation procedure available here.

## Device

| Item | Details |
| --- | --- |
| Device | Redmi Note 14 Pro+ 5G |
| Codename | `amethyst` |
| Kernel type | Android GKI |
| Kernel base and supported firmware | Not documented yet |

Kernel compatibility can depend on the Android release, vendor firmware, and matching GKI modules. Check the compatibility information for a specific release before using it.

## Builds and releases

No prebuilt images or supported release versions are currently published in this repository. A release should include its matching source revision, Android common kernel base, build instructions, supported firmware, required images or partitions, and checksums before it is used.

## Building

There is no build configuration or source tree in this checkout yet, so it cannot produce a kernel image. Once those are added, use the build instructions for the exact Android common kernel branch and toolchain used by that revision; GKI build commands and outputs vary by branch.

## Installation and recovery

There are no installation instructions for this project yet. Do not flash an image unless its release notes explicitly identify it as compatible with your device and firmware and provide installation and recovery steps.

Before installing any future release:

1. Confirm the device codename and firmware version match the release requirements.
2. Keep a verified copy of the stock images needed to restore your device.
3. Read the release notes and verify downloaded files against the published checksums.
4. Follow only the installation and rollback procedure provided for that release.

Unlocking a bootloader or flashing modified images can erase data, prevent the device from booting, or affect warranty coverage. Proceed only if you understand the recovery process.

## Disclaimer

This project is unofficial and is not affiliated with Xiaomi. Use modified kernels at your own risk; no warranty is provided.
