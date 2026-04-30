---
description: Build the CarrotOS GSI system image for r1
argument-hint: [clean|dirty]
---

Build the CarrotOS / LineageOS 21 GSI system image for the Rabbit R1.

**Steps to run, in order:**

1. **Pre-flight check.** Run `bash /home/khalifa/Desktop/cipherOsCustom/verify_lineage_state.sh`. If it returns non-zero, STOP and tell the user to run `/post-sync` first — do not start a 1.5h build on a regressed tree.

2. **Optionally clean.** If `$ARGUMENTS` is `clean`, run `cd ~/lineage && source build/envsetup.sh && lunch gsi_r1-ap2a-userdebug && m installclean` first. Otherwise (default / `dirty`), skip — incremental builds are 5-15 min vs 1.5h full.

3. **Build.** Run the build in `~/lineage` (use `run_in_background: true` since this can be long; track with Monitor):
   ```
   cd ~/lineage && source build/envsetup.sh && lunch gsi_r1-ap2a-userdebug && WITH_DEXPREOPT=false mka systemimage -j6 2>&1 | tee build.log
   ```
   `mka` is a shell function from envsetup.sh — must be sourced in the same command chain. `WITH_DEXPREOPT=false` is REQUIRED (see CLAUDE.md "Build-system gotchas").

4. **Verify outputs.** When build finishes:
   - `ls -lh ~/lineage/out/target/product/r1/system.img` (expect ~1.6 GB after slim, ~1.7 GB pre-slim)
   - Tail build.log for "build completed successfully" or the failing target
   - If failed: surface the failing target + 30 lines of context, then suggest a fix based on CLAUDE.md patterns

5. **Suggest next step.** On success: tell user to `/verify-img` for sanity checks, then `/flash` (with optional `wipe` arg).

Argument: `$ARGUMENTS`
