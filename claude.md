# CipherOS R1 Custom ROM Build Guide

## Goal
Build a custom CipherOS ROM for the Rabbit R1 with:
- Our custom launcher (com.r1.launcher) as the ONLY launcher
- All bloat apps removed (Jelly, Eleven, Etar, Email, Recorder, etc.)
- R1 hardware support (camera motor, scroll wheel, etc.)
- Distributable ZIP that other R1 users can flash

---

## Source Repos

| Component | Repo | Branch |
|-----------|------|--------|
| CipherOS Manifest | https://github.com/CipherOS/android_manifest | fifteen |
| CipherOS Vendor | https://github.com/CipherOS/android_vendor_cipher | fifteen |
| R1 Device Tree | https://github.com/techyminati/android_device_rabbit_r1 | fifteen |
| R1 Kernel | https://github.com/techyminati/alps-4.19 | alps-mp-t0.mp1.tc16sp-pr1-V1 |
| R1 Vendor Blobs | https://github.com/techyminati/proprietary_vendor_rabbit_r1 | android-15 |
| Our Launcher | ~/Desktop/r1/mylauncher-compose | main |


R1 Maintainer: **techyminati** (Aryan Sinha)

---

## Build Environment

- **OS**: Ubuntu 24.04 LTS (native, kernel 6.17) on `khalifa-MS-7E25`
- **RAM**: 32 GB (+ 8 GB swap)
- **Disk**: NVMe `/dev/nvme0n1p1`, ~416 GB free
- **Source tree**: `~/cipher`
- **Launcher APK**: `~/Desktop/cipherOsCustom/app-debug.apk` (already on box, 13 MB, com.r1.launcher)
  (override with `LAUNCHER_APK=...` when running `setup_cipheros.sh`)

---

## Step-by-Step Commands

### STEP 1: Install dependencies
```bash
sudo apt update
sudo apt install -y \
    bc bison build-essential ccache curl flex \
    g++-multilib gcc-multilib git git-lfs gnupg \
    gperf imagemagick lib32readline-dev lib32z1-dev \
    libelf-dev liblz4-tool libsdl1.2-dev libssl-dev \
    libxml2 libxml2-utils lzop pngcrush rsync \
    schedtool squashfs-tools xsltproc zip zlib1g-dev \
    python3 python3-pip openjdk-17-jdk \
    libncurses-dev repo fontconfig \
    python-is-python3 wget unzip
```

### STEP 2: Configure git & ccache
```bash
git config --global user.name "R1 Builder"
git config --global user.email "r1builder@localhost"
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
ccache -M 50G
echo 'export USE_CCACHE=1' >> ~/.bashrc
echo 'export CCACHE_EXEC=/usr/bin/ccache' >> ~/.bashrc
```

### STEP 3: Sync CipherOS source (3-6 hours, can game during this)
```bash
cd ~/cipher
repo init -u https://github.com/CipherOS/android_manifest -b fifteen
repo sync -c -j4 --force-sync --no-clone-bundle --no-tags
```

Note: We're on Android 15 (`fifteen`), NOT Android 16 (`sixteen-qpr2`). The R1
maintainer (techyminati) only ships an Android 15 port — the device tree,
kernel, and vendor blobs all target Android 15. Mixing them with the Android 16
manifest fails the build.

### STEP 4: Clone R1 device tree + kernel
```bash
cd ~/cipher

# Device tree (Android 15)
git clone https://github.com/techyminati/android_device_rabbit_r1 \
    device/rabbit/r1 -b fifteen

# Kernel (V1 variant — the bare branch name doesn't exist)
git clone https://github.com/techyminati/alps-4.19 \
    kernel/mediatek/alps-4.19 -b alps-mp-t0.mp1.tc16sp-pr1-V1

# Vendor blobs (Android 15)
git clone https://github.com/techyminati/proprietary_vendor_rabbit_r1 \
    vendor/rabbit/r1 -b android-15
```

### STEP 5: Add our launcher APK as prebuilt
```bash
# Create directory
mkdir -p device/rabbit/r1/prebuilt/app/R1Launcher

# Copy APK from local launcher build output
cp ~/Desktop/cipherOsCustom/app-debug.apk \
    device/rabbit/r1/prebuilt/app/R1Launcher/R1Launcher.apk
```

Create file `device/rabbit/r1/prebuilt/app/R1Launcher/Android.mk`:
```makefile
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)

LOCAL_MODULE := R1Launcher
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := R1Launcher.apk
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_PRIVILEGED_MODULE := true
LOCAL_OVERRIDES_PACKAGES := TrebuchetQuickStep TrebuchetQuickStepGo Launcher3 Launcher3QuickStep

include $(BUILD_PREBUILT)
```

Add to `device/rabbit/r1/cipher_r1.mk`:
```makefile
# R1 Custom Launcher
PRODUCT_PACKAGES += \
    R1Launcher
```

### STEP 6: Strip bloat apps
```bash
# Comment out unwanted apps from vendor config
sed -i 's/^\(.*\bEmail\b\)/# REMOVED: \1/' vendor/cipher/config/common_mobile.mk
sed -i 's/^\(.*\bExchange2\b\)/# REMOVED: \1/' vendor/cipher/config/common_mobile.mk
sed -i 's/^\(.*\bBackgrounds\b\)/# REMOVED: \1/' vendor/cipher/config/common_mobile.mk
sed -i 's/^\(.*\bEleven\b\)/# REMOVED: \1/' vendor/cipher/config/common_mobile.mk
sed -i 's/^\(.*\bEtar\b\)/# REMOVED: \1/' vendor/cipher/config/common_mobile.mk
sed -i 's/^\(.*\bJelly\b\)/# REMOVED: \1/' vendor/cipher/config/common_mobile.mk
sed -i 's/^\(.*\bOmniStyle\b\)/# REMOVED: \1/' vendor/cipher/config/common_mobile.mk
sed -i 's/^\(.*\bAudioFX\b\)/# REMOVED: \1/' vendor/cipher/config/common_mobile.mk
sed -i 's/^\(.*TrebuchetQuickStep\b\)/# REMOVED: \1/' vendor/cipher/config/common_mobile.mk
sed -i 's/^\(.*TrebuchetQuickStepGo\b\)/# REMOVED: \1/' vendor/cipher/config/common_mobile.mk

# Remove Recorder
sed -i 's/^\(.*\bRecorder\b\)/# REMOVED: \1/' vendor/cipher/config/common_full.mk
```

### STEP 7: Build the ROM (4-8 hours, run before bed!)
```bash
cd ~/cipher
source build/envsetup.sh
lunch cipher_r1-ap3a-userdebug   # Android 15: 3-part product-release-variant
mka bacon -j6 2>&1 | tee build.log
```

### STEP 8: Get the output
```bash
# Find the ZIP
ls -lh out/target/product/r1/CipherOS-*.zip

# Copy to Desktop for easy flashing
cp out/target/product/r1/CipherOS-*.zip ~/Desktop/
```

### STEP 9: Flash on R1
```bash
# Boot R1 into fastboot mode
adb reboot fastboot

# Flash (from this Ubuntu host)
fastboot update ~/Desktop/CipherOS-*.zip -w
```

---

## Helper Script

A single setup script lives at `~/Desktop/cipherOsCustom/setup_cipheros.sh`.

It automates **STEPS 1‑6** (deps → git/ccache → repo sync → device clone →
launcher prebuilt → bloat strip) but deliberately STOPS before STEP 7 so you
can inspect the source tree before kicking off the multi‑hour ROM build.

```bash
cd ~/Desktop/cipherOsCustom
./setup_cipheros.sh
# optional overrides:
SOURCE_TREE=~/cipher LAUNCHER_APK=~/path/to/app-debug.apk ./setup_cipheros.sh
```

When you're satisfied, run STEP 7 manually:

```bash
cd ~/cipher
source build/envsetup.sh
lunch cipher_r1-ap3a-userdebug   # Android 15: 3-part product-release-variant
mka bacon -j6 2>&1 | tee build.log
```

---

## Troubleshooting

### "Unable to locate package libncurses5"
Ubuntu 24.04 removed ncurses5. Use `libncurses-dev` instead.

### "fatal: Remote branch sixteen-qpr2 not found in upstream origin"
You synced the manifest as Android 16 but the R1 device repos only exist for
Android 15. Re-init the manifest as `fifteen` and re-sync:
```bash
cd ~/cipher
repo init -u https://github.com/CipherOS/android_manifest -b fifteen
repo sync -c -j4 --force-sync --no-clone-bundle --no-tags
# then re-run setup_cipheros.sh — STEP 4 onwards picks up where it left off
```

### "Your local changes would be overwritten by checkout"
```bash
cd ~/cipher/.repo/manifests
git checkout -- .
cd ~/cipher
repo init -u https://github.com/CipherOS/android_manifest -b fifteen
repo sync -c -j4 --force-sync --no-clone-bundle --no-tags
```

### Build gets killed (SIGKILL / OOM)
Reduce threads: `mka bacon -j4` or even `-j2`

### Host runs out of memory during build
Current swap is 8 GB — for a 32 GB box that's tight when `mka` peaks. Add a
temporary swapfile:
```bash
sudo fallocate -l 16G /swapfile.extra
sudo chmod 600 /swapfile.extra
sudo mkswap /swapfile.extra
sudo swapon /swapfile.extra
# remove afterwards:
sudo swapoff /swapfile.extra && sudo rm /swapfile.extra
```

---

## Key Facts
- Package ID: com.r1.launcher
- Signed with: debug.keystore (PRESIGNED in build)
- R1 SoC: MediaTek MT6765 (Helio P35)
- CipherOS version: Android 15 base (branch `fifteen`)
- Android version: 15 (R1 maintainer does not ship an Android 16 port)
- Build target: cipher_r1-userdebug
- R1 maintainer: techyminati (Aryan Sinha)
