---
description: Build the CarrotOS GSI system image for r1
argument-hint: [clean|dirty]
---

Build the CarrotOS / LineageOS 21 GSI system image for the Rabbit R1.

**Steps to run, in order:**

1. **Pre-flight check.** Run `bash /home/khalifa/Desktop/cipherOsCustom/verify_lineage_state.sh`. If it returns non-zero, STOP and tell the user to run `/post-sync` first — do not start a 1.5h build on a regressed tree.

2. **Optionally clean.** If `$ARGUMENTS` is `clean`, run `cd ~/lineage && source build/envsetup.sh && lunch gsi_r1-ap2a-userdebug && m installclean` first. Otherwise (default / `dirty`), skip — incremental builds are 5-15 min vs 1.5h full.

3. **Stop Gradle/Kotlin daemons first IF this is the first build after a dexpreopt-config change.** Idle daemons hoard 6-8 GB of swap; combined with soong_build's 28 GB peak during full ninja regen, the 32 GB system OOMs. `cd ~/Desktop/rabbitR1Luncher && ./gradlew --stop` reclaims the swap. Skip for normal incrementals — the daemons only matter when Soong has to re-analyze Android.bp (env change, slim_lineage.sh edit, etc.).

4. **Build.** Run the build in `~/lineage` (use `run_in_background: true` since this can be long; track with Monitor):
   ```
   cd ~/lineage && source build/envsetup.sh && lunch gsi_r1-ap2a-userdebug && WITH_DEXPREOPT_BOOT_IMG_AND_SYSTEM_SERVER_ONLY=true mka systemimage -j6 2>&1 | tee build.log
   ```
   `mka` is a shell function from envsetup.sh — must be sourced in the same command chain. `WITH_DEXPREOPT_BOOT_IMG_AND_SYSTEM_SERVER_ONLY=true` preopts the boot image + system_server jars (the big perf wins) while skipping per-app preopt — sidesteps `org.lineageos.platform`'s preopt failure. R1Launcher gets verify-only preopt + speed-profile compile at first launch via its baked-in baseline profile (build #22+). DO NOT use plain `WITH_DEXPREOPT=true` — that hits the per-app preopt failure on `org.lineageos.platform`. DO NOT regress to `WITH_DEXPREOPT=false` — that loses the boot-image AOT win.

5. **Verify outputs.** When build finishes:
   - `ls -lh ~/lineage/out/target/product/r1/system.img` (expect ~1.7 GB with dexpreopt boot+sysserver enabled; was ~1.6 GB pre-build #23)
   - Tail build.log for "build completed successfully" or the failing target
   - If failed with `Killed` during soong bootstrap (~40s in, OOM): step 3 wasn't done. Run `./gradlew --stop` and retry.
   - If failed otherwise: surface the failing target + 30 lines of context, then suggest a fix based on CLAUDE.md patterns

6. **Suggest next step.** On success: tell user to `/verify-img` for sanity checks, then `/flash` (with optional `wipe` arg).

Argument: `$ARGUMENTS`
