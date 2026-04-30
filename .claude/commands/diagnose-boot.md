---
description: Analyze logcat for known CarrotOS boot failure patterns
argument-hint: [path-to-logcat]
---

Read the logcat and scan for documented failure modes from CLAUDE.md's build history. Match against known patterns; if no match, surface the smoking gun (FATAL EXCEPTION / SIGSEGV / restart-loop) for the user to investigate.

**Get the log:**
- If `$ARGUMENTS` is a path → read that file.
- If empty → grab fresh: `adb logcat -d > /tmp/r1_boot.log` and read that. (Falls back to nothing if device offline; tell user to capture and pass a path.)

**Patterns to match (in priority order):**

1. **Zygote NPE — missing org.lineageos.platform-res.apk** (build #1)
   - Signal: zygote / system_server crash preloading `GsmAlphabet`; `AssetManager` throws because `/system/framework/org.lineageos.platform-res.apk` is missing.
   - Fix: `gsi_r1.mk` must inherit `vendor/lineage/config/lineage_sdk_common.mk` (or better, `common.mk`).

2. **system_server NPE in DisplayPolicy.updateSettings** (build #2)
   - Signal: `NullPointerException at LineageSettings$NameValueCache.getStringForUser:295` or `at DisplayPolicy.updateSettings`.
   - Fix: LineageSettingsProvider not installed. `gsi_r1.mk` must inherit `vendor/lineage/config/common.mk` (not just `lineage_sdk_common.mk`).

3. **Launcher not registered** (build #3)
   - Signal: `pm list packages | grep r1` empty; falls back to `com.android.settings/.FallbackHome`.
   - Fix: R1Launcher in `/system/priv-app/` requires a `privapp-permissions-com.r1.launcher.xml`. Better: ship in `/system/app/` (LOCAL_PRIVILEGED_MODULE := false in the prebuilt Android.mk).

4. **mtkfusionrild crash** (early builds)
   - Signal: `RmcCdmaBcRangeParser::getRange` SIGSEGV; `init.svc.mtkfusionrild` shows `restarting`.
   - Fix: full userdata wipe (`fastboot reboot bootloader && fastboot -w`) + ensure `carroot.rc` is installed.

5. **Bootanim blank screen / black**
   - Signal: black screen during boot, no logo visible.
   - Fix: `desc.txt` uses `c 1 0 part0` (single frame, exits) instead of `p 0 0 part0` (loops). Re-bake `device/rabbit/r1/bootanimation/bootanimation.zip` with `zip -0` (store, no compression).

6. **Notification chime at boot**
   - Signal: `pixiedust.ogg` audible before `sys.boot_completed=1`; user reports "bird whisper sound".
   - Fix: `ro.config.notification_sound=` must be empty in BOTH `system.prop` (→ `/system/build.prop`) AND removed from `aosp_product.mk` / `gsi_product.mk` / `full_base.mk` (→ `/system/product/etc/build.prop`). slim_lineage.sh handles all three.

7. **Status bar still 28dp**
   - Signal: top 28dp reserved by SystemUI; status bar visible.
   - Fix: edit `vendor/lineage/overlay/no-rro/frameworks/base/core/res/res/values/dimens.xml` directly: `28dp` → `0dp` for `status_bar_height_default` and `status_bar_height_portrait`. PRODUCT_PACKAGE_OVERLAYS outranks DEVICE_PACKAGE_OVERLAYS in Soong, so a device-tree overlay alone won't take.

8. **Nav bar still drawn**
   - Signal: bottom nav bar visible at home or in apps.
   - Fix: `qemu.hw.mainkeys=1` must be in `/system/build.prop` (NOT `/system/product/etc/build.prop`). Wired via `TARGET_SYSTEM_PROP` in `BoardConfig.mk`. PRODUCT_PROPERTY_OVERRIDES filters `qemu.*` on GSI builds — don't use that path.

9. **Launcher buttons not working**
   - Signal: PowerService not getting key events; `adb logcat -s R1Power` shows nothing on button press.
   - Fix: AccessibilityService not enabled. `r1_kiosk.rc` must run `settings put secure enabled_accessibility_services com.r1.launcher/com.r1.launcher.PowerService` and `accessibility_enabled 1` on `sys.boot_completed=1`.

10. **Generic catch-all.**
    - Look for `FATAL EXCEPTION`, `SIGSEGV`, `Process: system_server`, services in repeat-restart loops (`init: Service '...' restarting`).
    - Surface the first crash + 30 lines of surrounding context.

**Output format:**
```
Matched pattern: <number + name> (or "no known pattern")
Evidence: <key log lines, ≤5 lines>
Suggested fix: <one sentence + file path>
```

If multiple patterns match, list them all in priority order.

Reference: CLAUDE.md "Build status" + "Build-system gotchas" sections.
