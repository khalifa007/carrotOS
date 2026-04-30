---
description: Flash system.img to R1 (optionally wipe userdata)
argument-hint: [wipe]
---

Flash the freshly-built `system.img` to the Rabbit R1.

**Confirm with the user before any destructive step.** This is a destructive operation on the device.

**Sudo:** if a udev rule for vendor 18d1/0e8d/2717 is in `/etc/udev/rules.d/51-android.rules` and the user is in `plugdev`, no sudo is needed and the chain runs autonomously. Otherwise sudo is required and you must ask the user to run the chain themselves with the `!` prompt prefix (Claude Code's bash has no TTY for password prompts).

**Steps:**

1. **Verify the image exists:**
   ```
   ls -lh ~/lineage/out/target/product/r1/system.img
   ```
   If missing, tell user to `/build` first. Do not proceed.

2. **Get to fastbootd.**
   - Booted in CarrotOS / Android: run `adb reboot fastboot` (lands in fastbootd, which CAN flash logical partitions inside `super` including `system`).
   - Already in fastbootd: skip.
   - Powered off / unresponsive: tell user to use the web flasher https://rabbit-hmi-oss.github.io/flashing/ to enter MT65 Preloader, then bootloader fastboot.
   - Wait for enumeration with **`until fastboot devices 2>/dev/null | grep -q fastboot; do sleep 1; done`** — the host-side `fastboot` binary in `~/Android/Sdk/platform-tools` does NOT have a `wait-for-device` subcommand (that's an `adb` subcommand), so polling is the portable approach. R1's USB transition takes 15–25s; a fixed `sleep 10` races and you'll see `< waiting for any device >`.

3. **If `$ARGUMENTS` contains `wipe`:** WARN the user this erases all user data and apps. Confirm explicitly. Then:
   - `fastboot reboot bootloader` — switch from fastbootd to bootloader fastboot. Userdata is on a PHYSICAL partition outside `super`, so it can ONLY be erased from bootloader mode.
   - Poll until enumerated: `until fastboot devices 2>/dev/null | grep -q fastboot; do sleep 1; done`.
   - `fastboot -w` (erases userdata + metadata).
   - `fastboot reboot fastboot` — back to fastbootd, because `system` is a logical partition only flashable from fastbootd. (Trying to flash system from bootloader mode fails with `Writing 'system' FAILED (remote: 'This partition doesn't exist')`.)
   - Poll again: `until fastboot devices 2>/dev/null | grep -q fastboot; do sleep 1; done`.

4. **Flash system:**
   ```
   fastboot flash system ~/lineage/out/target/product/r1/system.img
   ```

5. **Reboot:**
   ```
   fastboot reboot
   ```

   Chain steps 2–5 with `&&` in a single Bash invocation so the whole sequence executes atomically. If sudo is needed (no udev rule), one `sudo -v` upfront caches creds for ~15min covering the rest.

6. **Watch first boot.** First boot after a clean wipe is 3-5 min (`WITH_DEXPREOPT=false` means apps compile at runtime). If it bootloops:
   - "Corrupted OS" error → flash vbmeta: `fastboot --disable-verity --disable-verification flash vbmeta ~/Desktop/cipherOsCustom/vbmeta.img`
   - Other → `adb logcat -d > /tmp/boot.log` and run `/diagnose-boot /tmp/boot.log`

7. **Cellular sanity (post-wipe).** With `ro.telephony.default_network=9,9,9,9` baked into system.prop (build #19+), data should auto-come up. Verify with:
   ```
   adb shell "dumpsys telephony.registry | grep mDataConnectionState"   # should be 2
   adb shell "ip route show default"                                     # should show ccmni0
   adb shell "ping -c 2 -W 3 8.8.8.8"                                    # should succeed
   ```
   If `mDataConnectionState=1` and no default route, the CDMA RIL crash regression is back — check `adb logcat -d -b crash | grep mtkfusionrild` for SIGSEGV in `RmcCdmaBcRangeParser`. Recovery: `adb shell "settings put global preferred_network_mode 9" && adb reboot`. (See CLAUDE.md gotcha + memory `project_cdma_ril_crash.md`.)

8. **Suggest next step.** After successful boot, suggest `adb logcat -s R1Power` to see launcher button keycodes (verifies double-press → home is wired up).

Argument: `$ARGUMENTS`

Reference: `build.md` for full flash procedure, `CLAUDE.md` for known boot failure patterns.
