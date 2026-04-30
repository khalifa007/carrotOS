# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this directory is

A **build harness** for producing a custom **LineageOS 21 GSI (Android 14)** for the **Rabbit R1**, with a single custom launcher (`com.r1.launcher`) baked in, branded as **CarrotOS**. The harness is these files:

- `setup_lineage.sh` — automates phases 1‑5 (deps → git/ccache → repo sync → R1 device tree clones → launcher prebuilt). Stops *before* the actual build so you can inspect.
- `slim_lineage.sh` — applies all "Local Lineage tree mods" (see section below). Edits ~12 upstream `.mk` files + 1 `dimens.xml` to strip ~30 kiosk-irrelevant packages and remove all default notification + UI sound oggs. Idempotent (perl regexes match-or-noop). MUST run after any `repo sync` of `~/lineage/`.
- `verify_lineage_state.sh` — pre-flight check before a build. Confirms device-tree patches, status-bar 0dp edit, slim_lineage.sh state, and notification-chime upstream removal. Wired into `/build` skill.
- `setup_cipheros.sh` — **DEAD legacy script** for the abandoned CipherOS fifteen path. Kept for reference. Do not use.
- `app-debug.apk` — historical copy of the prebuilt R1Launcher (13 MB, multidex, debug-signed). **No longer the build's source of truth as of 2026-04-29.** The device tree's `R1Launcher.apk` is now a **symlink** to `~/Desktop/rabbitR1Luncher/app/build/outputs/apk/debug/app-debug.apk` (the launcher project's Gradle debug output), so daily Android-Studio rebuilds flow into the next `mka systemimage` automatically — no manual copy step. Make's `stat()` follows symlinks, so ninja invalidates the prebuilt's install rule whenever Gradle updates the source apk's mtime. Wired into `/system/app/` (NOT priv-app — see "Required device-tree patches" below) as `LOCAL_CERTIFICATE := PRESIGNED` overriding `Launcher3 / Launcher3QuickStep / TrebuchetQuickStep / TrebuchetQuickStepGo`. To pin a specific apk version (e.g. for a release), break the symlink: `cp --remove-destination /path/to/specific.apk ~/lineage/device/rabbit/r1/prebuilt/app/R1Launcher/R1Launcher.apk`.
- `carrotos.png` — 480x480 carrot logo embedded as the single-frame bootanimation PNG. Copied into `device/rabbit/r1/bootanimation/bootanimation.zip` during bring-up.
- `vbmeta.img` — 4 KB stock R1 vbmeta with AVB0 header. Used to fix the "Corrupted OS" boot error after flashing (see `build.md`).
- `vendor_fix/` — pre-built `vendor_a_fixed.img` (338 MB) with `ro.telephony.default_network=9,9,9,9` patched into `/vendor/build.prop` (was `10,10,10,10` stock, which triggered the CDMA RIL crash). Flash from bootloader fastboot whenever vendor regresses to stock. `original_vendor_buildprop.txt` and `fixed_vendor_buildprop.txt` are the diff dumps. Full extract/edit/repack procedure in memory `project_cdma_ril_crash.md`.
- `build.md` — focused build/flash/iterate runbook for AFTER prep is done.
- `.claude/commands/{build,flash,post-sync,verify-img,diagnose-boot}.md` — slash commands wired into Claude Code. `/build` runs `verify_lineage_state.sh` then `mka systemimage`; `/flash [wipe]` runs the full fastboot chain with `wait-for-device` between mode transitions (no `sleep` races).
- `claude.md` — **legacy** long-form runbook from the abandoned CipherOS path. Mostly outdated; do not follow its commands. CLAUDE.md (this file) and build.md are authoritative.

The actual LineageOS source tree (~160 GB) lives at **`~/lineage/`** — *not* in this directory. Treat that path as the build root.

**Build status (2026-04-29):**
- Build #1: ~1h 37min full build, 1.7 GB `system.img`. Bootlooped on flash.
- Builds #2–3: zygote NPE fixes (Lineage SDK + LineageSettingsProvider). Build #3 first to reach `sys.boot_completed=1`.
- Build #4: launcher relocated to `/system/app/`, kiosk overlays added (lock screen + nav bar config), launcher auto-installs on first scan.
- Build #5: `carroot.rc` service installed; **cellular started working** (was crashing in `mtkfusionrild` before). Device boots straight to R1Launcher.
- Builds #6–8: immersive `policy_control` init script, package slim attempt (didn't take — see gotchas), camera/mic pre-grants.
- Build #9: `qemu.hw.mainkeys=1` baked via `system.prop` (proper place — see gotchas).
- Build #10–11: status-bar height = 0 overlay (only landscape took — Lineage's no-rro overlay outranked our device overlay for portrait/default), custom boot screen strings ("Loading…").
- Build #12: failed — PRODUCT_COPY_FILES bootanim conflict and PRODUCT_PACKAGE_OVERLAYS reorder didn't move device overlay above no-rro.
- Build #13: bootanimation hijack via `TARGET_BOOTANIMATION` worked (black 480x480 zip via Lineage's existing make rule); status bar still 28dp because `filter-out` on `PRODUCT_PACKAGE_OVERLAYS` doesn't remove inherited entries.
- Build #14: **status bar finally 0dp on all variants** after manually editing `vendor/lineage/overlay/no-rro/.../dimens.xml` 28dp → 0dp. ROM **renamed CarrotOS** with `ro.carrot.*` props.
- Build #15 (Tier 3 slim): 7 more packages stripped (HTMLViewer, BookmarkProvider, PartnerBookmarksProvider, BluetoothMidiService, MusicFX, CallLogBackup, WallpaperBackup via `DISABLE_WALLPAPER_BACKUP`). SettingsProvider sound-defaults overlay added. ~1.6 GB image.
- Build #16: added `persist.adb.notify=0` and `persist.charging.notify=0` to `system.prop` — both USB notification kill switches needed (line 1525 vs line 1358 of `UsbDeviceManager.java`, two different notifications).
- Build #17: still chirped post-boot. Settings.System.NOTIFICATION_SOUND was being written to `pixiedust.ogg` URI by an early-boot path independent of `ro.config.notification_sound`. Fix: physically delete all 75 default notification ogg files via `slim_lineage.sh` editing `frameworks/base/data/sounds/AllAudio.mk`.
- Build #18: still chirped — notification dir nuke wasn't enough; sound was actually from `/product/media/audio/ui/*` (likely `ChargingStarted.ogg` since USB cable is always plugged for ADB). Extended the AllAudio.mk regex to strip `ui/` too. **Confirmed silent boot.** Tier 4+5 slim removed Dialer, DocumentsUI, Browser2, Contacts, BlockedNumberProvider, CalendarProvider, MmsService, MtpService, VpnDialogs, E2eeContactKeysProvider, DSU. **48 apps total** (down from 75+).
- Build #19: launcher wired up the **camera swivel motor** (R1's stepper-gimbal lens). Stock OEM only exposes flipping via `com.rabbitescape.stepmotor/.CameraTileService` Quick Settings tile — unreachable in kiosk. Launcher now drives `/sys/devices/platform/step_motor_ms35774/orientation` via carroot socket: QR scanner and still-camera panels rotate to **180° (back-facing)** on open and return to **90° (idle)** on close. Calibrated values: `0` = front/selfie, `90` = idle, `180` = back. Verified end-to-end on device. Boot is fully clean: zero crashes, zero tombstones, LTE+data up on first boot post-wipe (`mDataConnectionState=2`, route `ccmni0`), `mtkfusionrild` stable. See memory `project_camera_swivel_motor.md` for the launcher-side wiring (R1Motor.kt + DisposableEffect calls).
- Build #20 (v1.0.1, audit pass 1): **carroot localhost bind** — `service carroot` in `device/rabbit/r1/rootdir/system/etc/init/carroot.rc` now uses `nc -s 127.0.0.1 -L -p 1337 sh` (was `nc -L -p 1337 sh` listening on `0.0.0.0`). Closes the remote-root regression where the unauthenticated shell was reachable via USB-tether or wifi-AP. **Tier 6 slim**: `StatementService` (~12 MB PSS, ~1.8 MB on /system) removed via `slim_lineage.sh` editing `build/make/target/product/media_system.mk`. **pm-disable wiring** in `r1_kiosk.rc`: rkpdapp + healthconnect.controller disabled at boot via `pm disable` (~25 MB combined PSS reclaimed at next reboot). devicelockcontroller is on AOSP's protected-packages list (`PackageManagerService.setEnabledSettings()` throws `SecurityException: Cannot disable a protected package`); left enabled, ~11 MB cost.
- Build #21 (v1.0.1, audit pass 1 cont.): added `com.android.cellbroadcastreceiver.module` to the `r1_kiosk.rc` `pm disable` list. ~21 MB PSS on a service that fires emergency alerts (CMAS/WEA) — never triggered on a data-only IoT-style SIM, no UI to display them in kiosk. Total reclaimed via Tier 6 slim + pm-disable: ~46 MB PSS RAM + ~1.8 MB on /system. **Note on `sh -c` chain robustness** (corrected audit finding): toybox `sh -c "cmd1; cmd2"` does NOT short-circuit on failure — every command runs regardless of previous exit code. The chained `settings put` block in `r1_kiosk.rc` is already robust; no need to split into separate `exec` lines.

Incremental rebuilds are 1–10 min; only the first build is the long pole.

## Local Lineage tree mods (outside the device tree)

These edits live OUTSIDE `device/rabbit/r1/` and would be silently wiped by a `repo sync --force-sync` of `~/lineage/`. **Run `slim_lineage.sh` to re-apply all of them at once** after any sync (idempotent, every regex is no-op if already done):

| File | Change | Why |
|---|---|---|
| `vendor/lineage/overlay/no-rro/frameworks/base/core/res/res/values/dimens.xml` | `status_bar_height_default` and `status_bar_height_portrait`: `28dp` → `0dp` | Lineage's no-rro overlay outranks our device overlay for these specific dimens in Soong's framework-res merge. `filter-out` on PRODUCT_PACKAGE_OVERLAYS doesn't remove inherited entries. Run: `sed -i 's/>28dp</>0dp</g' /home/khalifa/lineage/vendor/lineage/overlay/no-rro/frameworks/base/core/res/res/values/dimens.xml` |
| `vendor/lineage/config/common.mk`, `vendor/lineage/config/telephony.mk`, `build/make/target/product/{base_system,handheld_system,handheld_product,telephony_system,telephony_product,media_system,generic_system,full_base,aosp_product}.mk`, `device/generic/common/gsi_product.mk` | Strip ~30 kiosk-irrelevant `PRODUCT_PACKAGES` lines (Tier 1+2+3+4+5 — see slim_lineage.sh comments for the per-tier list). Also strips `pixiedust.ogg` / `Ring_Synth_04.ogg` `ro.config.*` defaults. | `filter-out` on inherited PRODUCT_PACKAGES doesn't work (see gotchas). Editing the upstream `.mk` lines directly is the only reliable removal. Each removal is regex-matched and fail-safe (no-op if regex doesn't match — package returns to build instead of silent breakage). |
| `frameworks/base/data/sounds/AllAudio.mk` | Strip every `PRODUCT_COPY_FILES` line for `media/audio/notifications/*.ogg` and `media/audio/ui/*.ogg` (~100 lines). | This is the **only fix** for the post-boot chirp. Even with `ro.config.notification_sound=` empty + `def_lockscreen_sounds_enabled=0` + `persist.{adb,charging}.notify=0`, an early-boot path (suspected `RingtoneManager.ensureDefaultRingtones()` post-MediaProvider-scan) writes a default ogg URI to `Settings.System.NOTIFICATION_SOUND` before init.rc runs. With the files physically gone, no URI can resolve to playable audio — every notification/UI sound is silent. See `project_usb_notification_kill.md` memory. |

## Why LineageOS 21 GSI, not CipherOS

CipherOS `fifteen` (Android 15) was abandoned by upstream in Aug 2024; the rest of the AOSP-15 tree drifted past it and the `frameworks/base@fifteen` snapshot can't be patched into compatibility (we tried — class-level drift in `frameworks/opt/telephony` alone is hundreds of CLs). CipherOS moved to `sixteen` (Android 16) but the R1 maintainer (techyminati) hasn't published the sixteen device tree publicly.

LineageOS has no public R1 device tree on `lineage-21.0` either — the only R1 source available on Lineage is the **GSI tree** from `RabbitHoleEscapeR1`, which produces a generic system image rather than a device-tuned ROM. Trade-off: vanilla feel, possible rough edges on R1-specific hardware (camera tuning, scroll wheel, push-to-talk button), but actually builds and ships in days vs. weeks.

## Common commands

**Slash commands (preferred — they handle envsetup, pre-flight, and fastboot races):**
- `/build` (or `/build clean`) — runs `verify_lineage_state.sh`, sources envsetup, lunches, runs `mka systemimage`
- `/flash` (or `/flash wipe`) — adb-reboot → fastbootd → optionally bootloader+wipe → flash → reboot, with `wait-for-device` between mode transitions
- `/post-sync` — re-applies all "Local Lineage tree mods" via `slim_lineage.sh` after a `repo sync`
- `/verify-img` — sanity-checks the built `system.img` for expected R1Launcher content
- `/diagnose-boot <logcat-file>` — pattern-matches against known CarrotOS boot failure signatures

```bash
# Raw equivalents (when slash commands aren't available, e.g. background subshell).
# Idempotent prep (skips work that's already done):
./setup_lineage.sh

# Re-apply local Lineage mods after `repo sync`:
./slim_lineage.sh

# Just the long sync, without re-running apt:
cd ~/lineage && repo sync -c -j4 --force-sync --no-clone-bundle --no-tags

# Build the GSI (first time ~1.5h on 32GB / 8-core; run in tmux):
cd ~/lineage
source build/envsetup.sh
lunch gsi_r1-ap2a-userdebug
WITH_DEXPREOPT=false mka systemimage -j6 2>&1 | tee build.log

# Output:
ls -lh ~/lineage/out/target/product/r1/system.img    # ~1.7GB GSI

# Incremental rebuild after editing a .mk or replacing the launcher APK
# (re-uses everything cached — typically 5-15 min):
cd ~/lineage && WITH_DEXPREOPT=false mka systemimage -j6 2>&1 | tee build.log

# Verify the build without flashing (sanity-check artifacts):
find ~/lineage/out/target/product/r1/system -name "R1Launcher.apk"
~/lineage/out/host/linux-x86/bin/aapt2 dump badging \
  ~/lineage/out/target/product/r1/system/priv-app/R1Launcher/R1Launcher.apk \
  | grep -E "package|launchable-activity|sdkVersion|native-code"
grep ro.build.fingerprint ~/lineage/out/target/product/r1/system/build.prop

# Flashing — R1 has a non-standard bootloader (MT65 Preloader).
# First-time entry to fastboot needs the web tool: https://rabbit-hmi-oss.github.io/flashing/
# After Android is up at least once, `adb reboot fastboot` works and lands in fastbootd.
# Re-flashing from fastbootd:
#   sudo ~/Android/Sdk/platform-tools/fastboot flash system ~/lineage/out/target/product/r1/system.img
#   sudo ~/Android/Sdk/platform-tools/fastboot reboot
# (sudo is needed unless you've added a udev rule for vendor 18d1; see build.md)
# Full procedure incl. "Corrupted OS" fix and density adjustment lives in build.md.
```

**Recovery fallback:** if a flashed GSI bootloops, re-flash the official CipherOS Android 16 zip to recover. URL: https://sourceforge.net/projects/cipheros/files/CipherOS-7/r1/ (file: `CipherOS-7.0-ALHENA-cipher_r1-20250623-0753-BETA-OFFICIAL-VANILLA.zip`).

## Architecture

The build composes three trees under `~/lineage/`:

| Tree | Branch | Source |
|---|---|---|
| LineageOS platform manifest | `lineage-21.0` | `LineageOS/android` |
| R1 GSI device tree → `device/rabbit/r1/` | `main` | `RabbitHoleEscapeR1/device_rabbit_r1` |
| R1 vendor blobs → `vendor/rabbit/r1/` | `main` | `RabbitHoleEscapeR1/vendor_rabbit_r1` |
| MediaTek kernel → `kernel/mediatek/alps-4.19/` | `alps-mp-t0.mp1.tc16sp-pr1-V1` | `techyminati/alps-4.19` |

**Lunch target:** `gsi_r1-ap2a-userdebug`. Android 14 (Lineage 21) uses 3-part lunch: `<product>-<release>-<variant>`. The R1 GSI tree's product is `gsi_r1`, not `lineage_gsi_r1`.

**`WITH_DEXPREOPT=false` is required.** The GSI tree pulls in Lineage's `org.lineageos.platform` jar but doesn't preopt it; without disabling dexpreopt the build fails on a missing-artifacts check. Trade-off: slightly slower first launch of system apps. Acceptable.

**Launcher integration point.** Phase 5 writes `device/rabbit/r1/prebuilt/app/R1Launcher/{R1Launcher.apk, Android.mk}` and appends `PRODUCT_PACKAGES += R1Launcher` to `device/rabbit/r1/gsi_r1.mk`. The `LOCAL_OVERRIDES_PACKAGES` line in the prebuilt's Android.mk is what makes ours the *only* launcher in the system image.

**`LOCAL_PRIVILEGED_MODULE := false`** — R1Launcher lands in `/system/app/`, NOT `/system/priv-app/`. On Android 14, every priv-app must have a matching `privapp-permissions-<package>.xml` allowlist file; without it, PackageManager silently rejects the package on first scan. Build #3 (2026-04-28) hit this: APK was on disk at `/system/priv-app/R1Launcher/R1Launcher.apk` but `pm list packages | grep r1` returned empty, the launcher never registered, and the device fell back to `com.android.settings/.FallbackHome`. A regular launcher doesn't need privileged perms, so `/system/app/` is the right home.

**Kiosk-mode chrome removal.** R1 ships without lock screen / nav bar / status bar / setup wizard. Since R1Launcher is a prebuilt APK (we can't change it to call `WindowInsetsController.hide()`), every chrome element has to be killed at the system level. The mechanisms are layered defense-in-depth because Android resists kiosk mode:

| Element | Mechanism | File |
|---|---|---|
| Software nav bar | `qemu.hw.mainkeys=1` in `/system/build.prop` → `mHasNavigationBar=false`, window never created | `device/rabbit/r1/system.prop` (wired via `TARGET_SYSTEM_PROP` in `BoardConfig.mk`) |
| Status bar | `status_bar_height_*` 0dp — but the device-tree overlay is outranked by `vendor/lineage/overlay/no-rro` for the `_default`/`_portrait` variants. The actual fix is editing the Lineage no-rro file directly (28dp → 0dp); see "Local Lineage tree mods" above. Our device overlay still ships and covers `_landscape` plus future-proofs against the Lineage edit drifting back. | `vendor/lineage/overlay/no-rro/.../dimens.xml` (in-tree edit) + `device/rabbit/r1/overlay/.../r1_kiosk_dimens.xml` |
| Boot animation | Replace Lineage's logo bootanim with a 480x480 black PNG zip. The hijack hook is `TARGET_BOOTANIMATION` set in `BoardConfig.mk` — `vendor/lineage/bootanimation/Android.mk` only generates from `.tar` if that var is unset. PRODUCT_COPY_FILES collides with that module's install rule. | `device/rabbit/r1/bootanimation/bootanimation.zip` + `BoardConfig.mk` (`TARGET_BOOTANIMATION` line) |
| Boot transition text | Override `android_start_title` (and `android_upgrading_title`) for ALL `product=` variants (default, tablet, automotive, device) — AAPT errors with "multiple default products" if you only override some. Subtitle uses `<small>` styled-text markup which Resources.getText() honors. | `device/rabbit/r1/overlay/frameworks/base/core/res/res/values/r1_kiosk_strings.xml` |
| ROM branding (CarrotOS) | `ro.carrot.os` / `ro.carrot.version` / `ro.carrot.author` / `ro.carrot.device` props baked into `/system/build.prop`. Boot title uses "CarrotOS\n<small>by khalifa007</small>" (shortened from earlier "Loading… · by khalifa007" to fit R1's 480px screen — line 2 was getting truncated). | `device/rabbit/r1/system.prop` + `r1_kiosk_strings.xml` |
| Lock screen | `config_disableLockscreenByDefault=true`, `config_showNavigationBar=false` (defensive) | `device/rabbit/r1/overlay/frameworks/base/core/res/res/values/r1_kiosk_config.xml` |
| Notification + UI sounds | TWO USB notification props (`persist.adb.notify=0` for ADB-active line 1525, `persist.charging.notify=0` for USB-charging line 1358) PLUS SettingsProvider defaults overlay (`def_lockscreen_sounds_enabled=0` etc.) PLUS physical removal of every `/product/media/audio/{notifications,ui}/*.ogg` from the build. The file removal is the only thing that consistently silences the boot chirp; everything else can be circumvented by `RingtoneManager.ensureDefaultRingtones()` writing a default URI before init.rc runs. | `device/rabbit/r1/system.prop` + `device/rabbit/r1/overlay/frameworks/base/packages/SettingsProvider/res/values/r1_kiosk_sound_defaults.xml` + `slim_lineage.sh` (strips `frameworks/base/data/sounds/AllAudio.mk`) |
| Setup wizard | `ro.setupwizard.mode=DISABLED` + skip the package | `device/rabbit/r1/device.mk` |
| Heads-up notifications + immersive policy | `settings put global` commands, run from init on `sys.boot_completed=1` | `device/rabbit/r1/rootdir/system/etc/init/r1_kiosk.rc` |
| Camera + mic prompts | `default-permissions` XML pre-grants `CAMERA` + `RECORD_AUDIO` for `com.r1.launcher` on first install | `device/rabbit/r1/configs/default-permissions/default-permissions-r1.xml` |
| Launcher's WiFi/OTA actions | `carroot` service: `nc -L -p 1337 sh` running as root in `u:r:su:s0` — launcher connects to localhost:1337 to run shell commands. **Significant security caveat for public release** (see memory `project_carroot_root_shell.md`) | `device/rabbit/r1/rootdir/system/etc/init/carroot.rc` |
| Camera flip (stepper-motor gimbal) | R1 has a single physical camera on a kernel-controlled stepper motor (`step_motor_ms35774`). Stock OEM exposes flipping only via `com.rabbitescape.stepmotor/.CameraTileService` Quick Settings tile — unreachable in kiosk. Launcher writes to `/sys/devices/platform/step_motor_ms35774/orientation` via the carroot socket (sysfs is `sysfs_motor` SELinux class, only `u:r:su:s0` has rw access). Calibrated values: `0`=front/selfie, `90`=idle, `180`=back. QR + still-camera panels rotate to `180` on open, return to `90` on close. | Launcher: `R1Motor.kt`, `OpenClawQrPanel.kt`, `OpenClawCameraPanel.kt` in `~/Desktop/rabbitR1Luncher/app/src/main/java/com/r1/launcher/ui/`. Memory: `project_camera_swivel_motor.md` |

## Required device-tree patches (already applied)

The RabbitHoleEscapeR1 GSI tree was designed for AOSP, not Lineage. Eight patches in `device/rabbit/r1/` make it compose with the Lineage manifest:

- **`BoardConfig.mk`** — comment out `BOARD_BUILD_SYSTEM_ROOT_IMAGE := false` (obsolete in Android 14+).
- **`BoardConfig.mk`** — comment out `include device/mediatek/sepolicy/BoardSEPolicyConfig.mk` (that path doesn't exist in the Lineage manifest; generic sepolicy is sufficient for a GSI).
- **`BoardConfig.mk`** — append `include vendor/lineage/config/BoardConfigLineage.mk` (provides `PATH_OVERRIDE_SOONG`, kernel-make vars, and FMRadio namespace logic).
- **`gsi_r1.mk`** — `DISABLE_WALLPAPER_BACKUP := true` AND `PRODUCT_NO_DYNAMIC_SYSTEM_UPDATE := true` set at the **top** of the file, BEFORE the inherit-product chain. Both upstream `.mk` files gate their PRODUCT_PACKAGES additions on these vars via `ifeq` / `ifneq` — and Make's `ifeq` is parse-time, so the variable must be set before the upstream file is parsed (i.e., before its inherit-product call). Setting them after the inherits is a no-op (same trap as `LINEAGE_BUILD := r1` setting Camera2 — see slim_lineage.sh comment).
- **`gsi_r1.mk`** — add `LINEAGE_BUILD := r1` (so AOSP's `gsi_product.mk` and `aosp_product.mk` skip their own `apns-conf.xml` PRODUCT_COPY_FILES, which would conflict with Lineage's `apns-conf.xml` PRODUCT_PACKAGES).
- **`gsi_r1.mk`** — add `PRODUCT_SOONG_NAMESPACES += packages/apps/FMRadio/jni/fmr` (Lineage's BoardConfigLineage adds this for non-MTK boards via fallthrough; we add it explicitly since the R1 has no FM tuner board flag set).
- **`gsi_r1.mk`** — `$(call inherit-product, vendor/lineage/config/common.mk)`. **Critical for boot.** Lineage's patched `frameworks/base` depends on a chain of Lineage userspace components; `common.mk` is the canonical inherit that brings them in. Two failure modes seen if this is missing or undersized:
  1. (build #2) Without any Lineage product inherit: zygote dies preloading `GsmAlphabet` because `AssetManager` hardcodes `/system/framework/org.lineageos.platform-res.apk` and the file isn't built. Fixed by adding `lineage_sdk_common.mk`.
  2. (build #3) With only `lineage_sdk_common.mk`: the SDK jar is loaded but `LineageSettingsProvider` (the content provider behind `content://lineagesettings/...`) isn't installed, so `DisplayPolicy.updateSettings()` calls `LineageSettings.System.getIntForUser`, the cache resolver returns null, and `system_server` dies with `NullPointerException at LineageSettings$NameValueCache.getStringForUser:295`. Fixed by inheriting `common.mk` (which transitively includes `lineage_sdk_common.mk` AND `LineageSettingsProvider`).
  We deliberately do **not** inherit `common_mobile.mk` because it pulls in Trebuchet/icon-pack overlays we don't need (R1Launcher overrides them anyway).

If `setup_lineage.sh` re-clones the device tree (e.g. after `rm -rf ~/lineage/device/rabbit/r1`), these patches must be re-applied. The script does NOT currently re-apply them — they were applied by hand during bring-up. Future improvement: bake them into the script.

## Build-system gotchas

Several "obvious" approaches don't work for this tree; document them so future iterations don't waste time:

- **`PRODUCT_PROPERTY_OVERRIDES` silently filters `qemu.*` in GSI builds.** We tried adding `qemu.hw.mainkeys=1` via `device.mk`'s `PRODUCT_PROPERTY_OVERRIDES`; the property never landed in any `build.prop`. Fix: use `TARGET_SYSTEM_PROP` in `BoardConfig.mk` pointing at a `system.prop` file — that path appends verbatim to `/system/build.prop` with no filtering. (Note: `$(call my-dir)` doesn't resolve in `BoardConfig.mk`; hardcode `device/rabbit/r1/system.prop`.)
- **`filter-out` doesn't remove inherited entries from PRODUCT-namespaced variables.** Confirmed for both `PRODUCT_PACKAGES` (Jelly / LineageParts / LineageSetupWizard) and `PRODUCT_PACKAGE_OVERLAYS` (vendor/lineage/overlay/no-rro). AOSP's `inherit-product` namespaces these internally; the filter only affects the local accumulator, not the merged final list. Workarounds: edit the upstream file directly (cleanest if the file is in your local clone — see "Local Lineage tree mods"), build a Runtime Resource Overlay (RRO), or rewrite the inherit chain.
- **`PRODUCT_PACKAGE_OVERLAYS` outranks `DEVICE_PACKAGE_OVERLAYS` in Soong's framework-res merge.** AOSP Make-era docs say DEVICE wins, but in modern Soong the opposite is true: any resource defined in both layers takes the PRODUCT value. Hit this with `status_bar_height_default/portrait` — Lineage's no-rro overlay (PRODUCT) won over our device overlay (DEVICE). `status_bar_height_landscape` was the tell: Lineage doesn't override it, so our 0dp landed cleanly while the other two stayed at 28dp.
- **Resource Runtime Overlays (RROs) load too late to affect SystemUI's nav bar.** The auto-generated RRO for `config_showNavigationBar=false` is enabled by `OverlayManagerService` but only after SystemUI has already constructed its `NavigationBar` window using the AOSP default (`true`). Real fix: kill at system-property level (`qemu.hw.mainkeys=1`) BEFORE SystemUI starts. RROs CAN still work for status bar height because that dimen is read on every config change, not just at SystemUI init — but for our case the in-tree edit was simpler than building an RRO APK.
- **Bootanimation can't be installed via `PRODUCT_COPY_FILES`.** `vendor/lineage/bootanimation/Android.mk` declares `bootanimation.zip` as a `LOCAL_MODULE` with its own install rule; adding `PRODUCT_COPY_FILES` for the same target path fails with "overriding commands for target". Use the `TARGET_BOOTANIMATION` variable hook (set in `BoardConfig.mk`) — Lineage's makefile only generates from the `.tar` if that variable is empty; otherwise it copies whatever path you point at into place.
- **Strings overlays must override every `product=` variant the upstream string defines.** `android_start_title` upstream has `product="default"`, `"tablet"`, `"automotive"`, `"device"`. Overlaying only one (or one without a product attribute) → AAPT error "multiple default products defined for resource". Always grep upstream first to enumerate variants.
- **`cmd statusbar disable …` was removed in Android 14.** `cmd statusbar` no longer accepts `disable`/`enable`; the `disable` calls in `r1_kiosk.rc` no-op. Left in for documentation; remove on next pass.
- **Mid-build edits to `device.mk` PRODUCT_COPY_FILES don't always re-trigger ninja.** When adding new copy rules during a long build, abort and restart cleanly to be safe (~1–10 min for incremental).
- **`mka systemimage` won't always re-invalidate when upstream `.mk` PRODUCT_PACKAGES change.** Confirmed empirically: removing entries from `build/make/target/product/handheld_*.mk` etc. via slim_lineage.sh + running `mka systemimage` reported "completed successfully" but the staged install dir (and the resulting `system.img`) still contained the package. Workaround: `rm -rf out/target/product/r1/system.img out/target/product/r1/system/{app,priv-app,product/app,product/priv-app}/<PackageName>` before `mka` to force a true rebuild. `m installclean` is the heavy-handed alternative.
- **`mka` is a bash function, not a binary.** It's defined in `~/lineage/build/envsetup.sh`. Running `mka systemimage` from a fresh shell (e.g. a background-task subshell) without first sourcing envsetup gives `mka: command not found` — and the build silently doesn't run. Always chain: `cd ~/lineage && source build/envsetup.sh && lunch gsi_r1-ap2a-userdebug && mka systemimage`. The `/build` skill handles this; raw `mka` invocations need to source manually.
- **Removing the default notification-sound system property is NOT enough to silence the boot chirp.** `ro.config.notification_sound=` empty causes `RingtoneManager.getDefaultRingtoneFilename()` to return null — but on first boot, *something* (likely `RingtoneManager.ensureDefaultRingtones()` or a NotificationChannel registration) still writes a default ogg URI to `Settings.System.NOTIFICATION_SOUND`. Even after a userdata wipe with `def_notification_sound` overlaid, the URI gets re-populated. The only fix that consistently sticks is **physical removal of all default ogg files** from the build (slim_lineage.sh strips `media/audio/{notifications,ui}/*` from `AllAudio.mk`). With no audio data at the URIs, MediaPlayer fails silently — chirp gone.
- **TWO USB notification kill switches required, not one.** `UsbDeviceManager.java` has TWO independent paths: `updateAdbNotification` at line 1525 (gated by `persist.adb.notify=0`) and `updateUsbNotification` at line 1358 (gated by `persist.charging.notify=0`). The latter is the "Charging this device via USB" / MTP / PTP notification — fires on every USB plug-in regardless of ADB state, on `SystemNotificationChannels.USB` channel which has its own per-channel sound URI that bypasses the system default. Build #16 set only `persist.adb.notify` and chirp persisted; build #17 added `persist.charging.notify` + the file removal.
- **R1's USB transition to fastbootd takes 15–25s — fixed `sleep` races.** The `/flash` skill chain previously used `sleep 10` between `adb reboot fastboot` and the next `fastboot` command, which reliably hit `< waiting for any device >` and stalled. Use `fastboot wait-for-device` instead — blocks until the device enumerates, no race window. *(Caveat: `wait-for-device` is an `adb` subcommand and may not be present in older host-side `fastboot` binaries; if it errors with "unknown command", poll instead: `until fastboot devices 2>/dev/null | grep -q fastboot; do sleep 1; done`.)*
- **Default `preferred_network_mode=10` triggers vendor RIL SEGV crash on every clean wipe — and `system.prop` CANNOT fix it.** After a userdata wipe, `Settings.Global.preferred_network_mode` is empty and falls back to `ro.telephony.default_network`. AOSP default is **10** (LTE_CDMA_EVDO_GSM_WCDMA), but vendor `libmtk-ril.so` SEGV-crashes in `RmcCdmaBcRangeParser::getRange` (null deref) during CDMA broadcast-config init — taking `com.android.phone` down with it in a ~15s restart loop. Symptom: `service list` missing `phone`/`isub`, `mDataConnectionState=1` stuck CONNECTING, no default route despite `gsm.sim.state=LOADED` showing the SIM is fine. **The `system.prop` fix is structurally ineffective**: stock `/vendor/build.prop` sets `ro.telephony.default_network=10,10,10,10`, vendor_init runs BEFORE init, and `ro.*` is first-set-wins — so /system's `=9` is silently no-op'd. The PERMANENT fix is to modify `/vendor/build.prop` directly. Procedure: extract `vendor_a.img` from `~/Downloads/rabbit_OS_v0.8.293/.../super.img` (sparse → raw via `simg2img`, unpack via `lpunpack`), use `debugfs` to edit `/build.prop` (`sed 10,10,10,10 → 9,9,9,9` on line 372), restore mode `0100600` and SELinux xattr `u:object_r:vendor_file:s0` (debugfs `set_inode_field` + `ea_set`), then `fastboot flash vendor vendor_a_fixed.img`. **Survives userdata wipes** because /vendor is a separate logical partition outside super's data section. Pre-built artifact at `~/Desktop/cipherOsCustom/vendor_fix/vendor_a_fixed.img` (338 MB) — flash whenever vendor regresses to stock. CDMA2000 is dead worldwide as of 2025 (US/JP/KR/CN all shut down) so mode 9 costs no users globally. See memory `project_cdma_ril_crash.md` for full procedure + `reference_rabbit_os_firmware.md` for the source firmware. The runtime workaround `settings put global preferred_network_mode 9 && reboot` survives reboots but NOT userdata wipes — fine for ad-hoc recovery.
- **Bootloader-fastboot vs fastbootd matters for which partitions are flashable.** From `adb reboot fastboot` you land in **fastbootd** (Android-userspace fastboot) — flashes logical partitions inside `super` (system, vendor, product, system_ext) but CANNOT erase `userdata` (physical partition outside super). For wipe sequences the order is: (1) `adb reboot fastboot` → fastbootd, (2) `fastboot reboot bootloader` → bootloader fastboot, (3) `fastboot -w` (wipes userdata), (4) `fastboot reboot fastboot` → back to fastbootd, (5) `fastboot flash system …`. Skipping the round-trip and trying to flash system from bootloader fastboot fails with `Writing 'system' FAILED (remote: 'This partition doesn't exist')`.
- **Sudo + Claude Code's bash has no TTY for password prompts.** Adding a udev rule for vendor IDs `18d1` (Google fastboot), `0e8d` (MediaTek preloader), `2717` (Rabbit OEM) — `MODE=0660 GROUP="plugdev" TAG+="uaccess"` — plus user in `plugdev` group lets `fastboot`/`adb` work without sudo, so `/flash` runs autonomously without password prompts. Rule lives at `/etc/udev/rules.d/51-android.rules`.

## Post-flash risk profile

The GSI is structurally Treble-compatible with the R1 vendor partition. Tested working as of build #5+:

- **Cellular / SIM** — vendor RIL `mtkfusionrild` SEGV-crashes in `RmcCdmaBcRangeParser::getRange` if the framework asks it to init the CDMA codepath. Worked around by forcing `ro.telephony.default_network=9` (LTE/GSM/WCDMA, no CDMA) in `system.prop` so the buggy codepath never runs. With this, mtkfusionrild stays running across boots, all telephony binder services register (`phone`, `isub`, etc.), data PDP comes up on `ccmni0`, and ping over LTE works. Watch for regression: `getprop init.svc.mtkfusionrild` should be `running`, `service list | grep ' phone:'` should print, `dumpsys telephony.registry | grep mDataConnectionState` should be `2` (CONNECTED).
- **Custom launcher as default home** — auto-installs from `/system/app/` and gets `android.app.role.HOME` automatically.

Still known-rough or untested:
- **Camera tuning** — Generic camera HAL captures images, but R1-specific tuning (white balance, autofocus) lives in vendor and may give bad-looking pictures.
- **Push-to-talk button + scroll wheel** — `com.rabbitescape.keyhandler` and `com.rabbitescape.stepmotor` are present, but key/motor pass-through to the launcher hasn't been validated end-to-end.
- **First-boot delay** — `WITH_DEXPREOPT=false` means apps compile at runtime; first boot 3-5 min, first launch of each system app slightly slower. Normal speed afterward.
- **"Phone is starting" boot transition** — replaced with "CarrotOS / by khalifa007" text. With the slim build, the title window may flash so briefly between bootanim and launcher first-paint that the text is hard to read. The strings ARE compiled into `framework-res.apk` (verify with `aapt2 dump strings .../framework-res.apk | grep khalifa`). To slow the transition for visibility, add a `sleep` to `r1_kiosk.rc`'s boot_completed action — but the cleanest production answer is to bake the credit directly into the bootanimation PNG.

**Userdata wipe matters for fresh-flash tests.** `default-permissions` XML pre-grants only apply on first install (when `/data` is empty). If iterating on a device with existing user data, either wipe via `sudo fastboot erase userdata` from bootloader-fastboot (NOT fastbootd — userdata is a physical partition outside super) or manually `pm grant` the permissions to test.

## Idempotency rules baked into `setup_lineage.sh`

Re-running is safe by design:

- `repo init` always runs — no-op if branch unchanged.
- Phase 4 clones are `[[ ! -d ... ]]` guarded.
- Phase 5 only appends `R1Launcher` to `gsi_r1.mk` if not already present (`grep -q`); the prebuilt `Android.mk` is unconditionally rewritten (single source of truth).

## Knobs

- `SOURCE_TREE` (default `~/lineage`) — where to sync the LineageOS source.
- `LAUNCHER_APK` (default `<script_dir>/app-debug.apk`) — path to the prebuilt launcher to ship.
- `SKIP_LAUNCHER=1` — defer phase 5; useful if the APK isn't ready yet but you want to start the long sync. Phase 5 must be run manually before the build.
