---
description: Sanity-check the built system.img has the expected CarrotOS contents
---

Inspect the freshly-built system tree at `~/lineage/out/target/product/r1/system/` and confirm CarrotOS got everything it needs. Report each check as PASS / FAIL with a one-line note.

**Checks:**

1. **R1Launcher.apk in /system/app/ (NOT priv-app).**
   ```
   find ~/lineage/out/target/product/r1/system -name "R1Launcher.apk"
   ```
   - PASS: path is `~/lineage/out/target/product/r1/system/app/R1Launcher/R1Launcher.apk`
   - FAIL if it's in `priv-app/` — that regresses build #3 (PackageManager rejects priv-app without a privapp-permissions XML).

2. **Launcher metadata.**
   ```
   ~/lineage/out/host/linux-x86/bin/aapt2 dump badging <APK_path> | grep -E "package|launchable-activity|sdkVersion"
   ```
   - Expected: `package: name='com.r1.launcher'`, a launchable-activity, targetSdk 34+.

3. **CarrotOS branding props in build.prop.**
   ```
   grep -E "^ro\.carrot\.|^qemu\.hw\.mainkeys|^ro\.config\.notification_sound" ~/lineage/out/target/product/r1/system/build.prop
   ```
   - Expected: `ro.carrot.os=CarrotOS`, `ro.carrot.version=1.0`, `ro.carrot.author=khalifa007`, `ro.carrot.device=r1`, `qemu.hw.mainkeys=1`, `ro.config.notification_sound=` (empty).
   - Also check `~/lineage/out/target/product/r1/system/product/etc/build.prop` for any `ro.config.notification_sound?=pixiedust.ogg` — this should NOT be present (slim_lineage.sh handles).

4. **Slim took.** None of these packages should ship in the system image:
   ```
   cd ~/lineage/out/target/product/r1/system && ls app priv-app product/app product/priv-app 2>/dev/null | sort -u | grep -iE "Jelly|ExactCalculator|LineageParts|Updater|Camera2|messaging|Stk|EasterEgg|BasicDreams|PrintSpooler|DeviceAsWebcam|CompanionDeviceManager|LiveWallpapersPicker|ManagedProvisioning"
   ```
   - PASS: empty output (or just `SoundPicker` straggler, ~1MB, known).
   - FAIL: anything else listed → run `/post-sync` to re-slim and rebuild.

5. **Bootanimation is the CarrotOS one.**
   ```
   bootanim=$(find ~/lineage/out/target/product/r1/system ~/lineage/out/target/product/r1/system/product -name "bootanimation.zip" 2>/dev/null | head -1)
   unzip -l "$bootanim"
   ```
   - Expected: `desc.txt` + `part0/000.png`, total ~64 KB.
   - If size is small (<10 KB) it's the pure-black placeholder, not the CarrotOS logo — re-bake from `~/Desktop/cipherOsCustom/carrotos.png` if needed.

6. **system.img size.**
   ```
   ls -lh ~/lineage/out/target/product/r1/system.img
   ```
   - Expected: ~1.6 GB after slim. >1.7 GB suggests slim partially failed.

7. **Init scripts present.**
   ```
   ls ~/lineage/out/target/product/r1/system/etc/init/ | grep -E "r1_kiosk|carroot"
   ```
   - Expected: both `r1_kiosk.rc` and `carroot.rc`.

**Final report:** PASS / PARTIAL / FAIL with a one-line summary per check, plus a suggested next step.
