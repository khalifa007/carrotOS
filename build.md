# R1 ROM Build Runbook (CarrotOS / LineageOS 21 GSI)

Source tree is **`~/lineage/`**. ROM is branded **CarrotOS**. CipherOS path was abandoned (see `CLAUDE.md`).

---

## TL;DR — Incremental build + flash (the everyday loop)

Once your R1 has booted CarrotOS at least once, this is the full iterate loop. Copy-paste:

```bash
# 1. Build (5-15 min)
cd ~/lineage && source build/envsetup.sh && lunch gsi_r1-ap2a-userdebug && \
  WITH_DEXPREOPT=false mka systemimage -j6 2>&1 | tee build.log

# 2. Reboot R1 into fastbootd, flash, reboot
sudo ~/Android/Sdk/platform-tools/adb reboot fastboot
sudo ~/Android/Sdk/platform-tools/fastboot flash system ~/lineage/out/target/product/r1/system.img
sudo ~/Android/Sdk/platform-tools/fastboot reboot
```

That's it. Userdata is preserved.

> **Why the multi-line build command?** `mka` is a shell function defined by `envsetup.sh`, not a binary. A fresh terminal will say `Command 'mka' not found` until you source the env and `lunch` a target. Always run all four (`cd` → `source` → `lunch` → `mka`) in the same shell.

---

## First-time build (~1.5 hours, only once)

The first build is slow because nothing is cached. **Run inside `tmux`** so a closed terminal or dropped SSH doesn't kill it:

```bash
tmux new -s lineage
cd ~/lineage
source build/envsetup.sh
lunch gsi_r1-ap2a-userdebug
WITH_DEXPREOPT=false mka systemimage -j6 2>&1 | tee build.log

# detach:        Ctrl-b d
# reattach:      tmux attach -t lineage
```

`-j6` is sane for 32GB RAM / 8 cores. Drop to `-j4` if OOM-killed.
`WITH_DEXPREOPT=false` is required (R1 GSI tree doesn't preopt `org.lineageos.platform`).

**Pre-flight sanity check (optional, 10 sec):**
```bash
echo "USE_CCACHE=$USE_CCACHE  CCACHE_EXEC=$CCACHE_EXEC"   # both non-empty
df -h ~/lineage | awk 'NR==2 {print "free: "$4}'           # need >80 GB free
grep R1Launcher ~/lineage/device/rabbit/r1/gsi_r1.mk       # launcher wired in
```

**Output:**
```bash
ls -lh ~/lineage/out/target/product/r1/system.img    # ~1.7 GB
```

The output is a **GSI** — only `system.img`. Boot/vbmeta/vendor partitions stay stock.

---

## First-time flash (~5 min, only once per device)

The R1 uses a MediaTek MT65 Preloader, not standard fastboot. To enter fastboot the very first time you must use the web flasher. **After Android is up once, `adb reboot fastboot` works** and you can use the TL;DR loop above forever.

### One-time prerequisites

1. **Bootloader unlocked** — Rabbit Inc. must approve. Apply at [rabbit.tech/contact-us](https://www.rabbit.tech/contact-us). Wait 1–2 days. Then in your Rabbit Hole account toggle **"Developer: allow R1 bootloader to be unlocked"** (device on Wi-Fi, idle).
2. **Platform tools** — `apt install android-sdk-platform-tools` (or use `~/Android/Sdk/platform-tools/`).

### First flash flow

```bash
# 1. Power R1 off, UNPLUG it.

# 2. Open https://rabbit-hmi-oss.github.io/flashing/ in Chrome/Edge.
#    Click "Enter Fastboot Mode". Plug R1 in. A popup appears within ~1.5s —
#    pick "MT65 Preloader". R1 screen now shows FASTBOOT.

# 3. Confirm:
sudo ~/Android/Sdk/platform-tools/fastboot devices

# 4. Flash + wipe + reboot
sudo ~/Android/Sdk/platform-tools/fastboot flash system ~/lineage/out/target/product/r1/system.img
sudo ~/Android/Sdk/platform-tools/fastboot -w
sudo ~/Android/Sdk/platform-tools/fastboot reboot
```

First boot takes 3–5 min. **Don't interrupt.**

> Drop the `sudo` if you've installed the udev rule under "Troubleshooting" below.

---

## Post-flash one-time fixes

### "Corrupted OS" at boot

AVB rejected the unsigned system. Re-enter fastboot (web flasher again) and:

```bash
sudo ~/Android/Sdk/platform-tools/fastboot flash --disable-verity --disable-verification vbmeta \
  ~/Desktop/cipherOsCustom/vbmeta.img
sudo ~/Android/Sdk/platform-tools/fastboot reboot
```

Persists across re-flashes — only do this once.

### Wrong screen density (giant icons)

```bash
adb shell wm density 190
```

190 is the R1 community value. Persists.

---

## Troubleshooting

### `mka: command not found`
Build env not sourced. Re-run the full build line from the TL;DR — `source build/envsetup.sh && lunch gsi_r1-ap2a-userdebug` must precede `mka` in the same shell.

### `fastboot devices` returns empty
- R1 screen says `MT65 PRELOADER` not `FASTBOOT` → web-flasher popup wasn't completed. Power off, unplug, retry.
- `lsusb` shows MediaTek but `fastboot devices` is empty → add udev rule:
  ```bash
  echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0e8d", MODE="0666"' | \
    sudo tee /etc/udev/rules.d/51-mediatek.rules
  sudo udevadm control --reload-rules
  ```
  Unplug/replug R1. After this, `sudo` is no longer needed for fastboot.

### Build OOM-killed (`signal 9`)
Drop parallelism: `WITH_DEXPREOPT=false mka systemimage -j4`. Add a 16 GB swapfile if it persists:
```bash
sudo fallocate -l 16G /swapfile.extra && sudo chmod 600 /swapfile.extra
sudo mkswap /swapfile.extra && sudo swapon /swapfile.extra
```

### Build error: `module ... can't read namespace ...`
Add the missing path to `device/rabbit/r1/gsi_r1.mk`:
```
PRODUCT_SOONG_NAMESPACES += <path>
```

### Build error: `overriding commands for target`
Duplicate install rule. Confirm `LINEAGE_BUILD := r1` is in `gsi_r1.mk`. For bootanimation specifically, never use `PRODUCT_COPY_FILES` — use `TARGET_BOOTANIMATION` in `BoardConfig.mk` instead (already wired).

### Bootloop / black screen after flash
Grab `adb logcat` if USB comes up. If totally bricked, recover by re-flashing the official CipherOS Android 16 zip from [sourceforge.net/projects/cipheros](https://sourceforge.net/projects/cipheros/files/CipherOS-7/r1/), then iterate.

### Forgot what changed since last build → want a clean rebuild of one module
```bash
m installclean
WITH_DEXPREOPT=false mka systemimage -j6 2>&1 | tee build.log
```
Faster than a full clean.

---

## Special cases

### Just swapped the launcher APK
```bash
cp /path/to/new/app-debug.apk ~/lineage/device/rabbit/r1/prebuilt/app/R1Launcher/R1Launcher.apk
# then run the TL;DR build + flash
```

### Want to wipe userdata on next flash (test fresh-install flow)
Replace `fastboot reboot` step with:
```bash
sudo ~/Android/Sdk/platform-tools/fastboot -w
sudo ~/Android/Sdk/platform-tools/fastboot reboot
```
Required when testing `default-permissions` pre-grants or `SettingsProvider/defaults.xml` overlays — those only apply on first install with empty `/data`.

---

## Quick reference

| What | Where |
|---|---|
| Source tree | `~/lineage/` |
| Build log | `~/lineage/build.log` |
| Output GSI | `~/lineage/out/target/product/r1/system.img` |
| Launcher prebuilt | `~/lineage/device/rabbit/r1/prebuilt/app/R1Launcher/` |
| Bootanimation source | `~/lineage/device/rabbit/r1/bootanimation/bootanimation.zip` |
| Stock vbmeta (Corrupted OS fix) | `~/Desktop/cipherOsCustom/vbmeta.img` |
| Web flasher (first-time only) | [rabbit-hmi-oss.github.io/flashing](https://rabbit-hmi-oss.github.io/flashing/) |
| Recovery image | [sourceforge.net/projects/cipheros](https://sourceforge.net/projects/cipheros/files/CipherOS-7/r1/) |
| ccache stats | `ccache -s` |
| Build tree disk usage | `du -sh ~/lineage/out` |
