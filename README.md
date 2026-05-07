# CarrotOS

Custom **LineageOS 21 GSI (Android 14)** for the **Rabbit R1**, branded CarrotOS, shipping with a custom kiosk launcher (`com.r1.launcher`).

Built by **khalifa007**.

---

## I just want to flash my R1

Grab the latest flashable zip from **[Releases](../../releases)**.

Each release zip contains `system.img`, `vendor.img`, `vbmeta.img`, `flash.sh` (Linux/macOS), `flash.bat` (Windows), and a per-release `README.md` with full step-by-step flashing instructions and prerequisites.

Quick version:

1. Install [Android platform-tools](https://developer.android.com/studio/releases/platform-tools) (so `fastboot` and `adb` are in your `PATH`).
2. Boot the R1 into fastboot via the official web flasher: <https://rabbit-hmi-oss.github.io/flashing/>.
3. Unzip the release and run `./flash.sh` (or `flash.bat` on Windows).

Read the per-release README inside the zip before flashing — it covers the unlock step, the `vbmeta` flags rationale, and recovery back to stock.

---

## What's in this repo

This is the **build harness** — the scripts and configuration used to produce the flashable images. The actual LineageOS source tree (~160 GB) is not stored here; the harness syncs it on demand.

| File | Purpose |
|---|---|
| `setup_lineage.sh` | Clones LineageOS 21 + the R1 GSI device tree + vendor blobs into `~/lineage/`. Phases 1–5 of bring-up. |
| `slim_lineage.sh` | Re-applies all "Local Lineage tree mods" after a `repo sync` — strips ~30 kiosk-irrelevant packages, removes default notification/UI sound files, sets status bar to 0dp. Idempotent. |
| `verify_lineage_state.sh` | Pre-flight check before a build. Confirms device-tree patches and slim_lineage state. |
| `catch_fastboot.sh` | Race-catcher that polls USB at 50 ms for an R1 in MTK BROM and drives it into Google fastboot via `mtkclient`. Use this when the device is locked into stock RabbitOS with adb disabled. |
| `vbmeta.img` | 4 KB AVB0 vbmeta with `flags=3` (`HASHTREE_DISABLED | VERIFICATION_DISABLED`) baked in. Required for the patched `vendor.img` to actually mount on the R1's MT6765 dm-verity. |
| `vendor_fix/*.txt` | Diff dumps showing the `ro.telephony.default_network` 10→9 change in `/vendor/build.prop` that fixes the vendor RIL CDMA SIGSEGV crash. |
| `carrotos.png` | 480×480 carrot logo embedded as the bootanimation. |
| `CLAUDE.md` | Authoritative runbook — architecture, gotchas, build status per release. |
| `build.md` | Focused build/flash/iterate runbook for AFTER the harness has set up the tree. |
| `.claude/commands/` | Slash commands (`/build`, `/flash`, `/post-sync`, `/verify-img`, `/diagnose-boot`) wired into Claude Code. |

The launcher source lives in a separate repo: **[khalifa007/rabbitR1Luncher](https://github.com/khalifa007/rabbitR1Luncher)** — Compose-based, package `com.r1.launcher`. The build harness symlinks its release APK into `~/lineage/device/rabbit/r1/prebuilt/app/R1Launcher/R1Launcher.apk`, so a Gradle release build flows into the next `mka systemimage` automatically.

---

## Building from source

Tested on Ubuntu 24.04, 32 GB RAM, 8-core. ~160 GB free disk needed for `~/lineage/`. First build is ~1.5 hours; incremental rebuilds are 1–10 min.

```bash
# 1. One-time prep — installs deps, clones lineage + R1 device tree (long).
./setup_lineage.sh

# 2. Apply local Lineage tree mods (idempotent; re-run after every `repo sync`).
./slim_lineage.sh

# 3. Build.
cd ~/lineage
source build/envsetup.sh
lunch gsi_r1-ap2a-userdebug
WITH_DEXPREOPT_BOOT_IMG_AND_SYSTEM_SERVER_ONLY=true mka systemimage -j6

# Output: ~/lineage/out/target/product/r1/system.img (~1.7 GB)
```

See `CLAUDE.md` and `build.md` for the full flashing/iteration workflow, the eight required device-tree patches, and the build-system gotchas log.

---

## Security caveat

CarrotOS includes a service called `carroot` that exposes an **unauthenticated root shell on TCP port 1337**, listening only on `127.0.0.1`. The launcher uses it to drive the camera stepper motor and manage WiFi.

Any app installed on the device can connect to `127.0.0.1:1337` and run shell commands as root. Since this is a kiosk and only the bundled launcher is meant to run, this is currently acceptable — but **do not install untrusted third-party apps** on CarrotOS. A future release will gate the carroot socket behind launcher-UID authentication.

---

## License & warranty

This is a community ROM with **no warranty**. Flashing custom firmware to your Rabbit R1 may void any OEM warranty and carries a non-zero risk of bricking the device. You can always recover by flashing official Rabbit OS via <https://rabbit-hmi-oss.github.io/flashing/>.

---

CarrotOS — by khalifa007
