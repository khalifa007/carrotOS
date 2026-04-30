#!/usr/bin/env bash
# Slim the Lineage build by removing kiosk-irrelevant packages.
#
# These edits live OUTSIDE device/rabbit/r1/ — they touch upstream Lineage
# config and AOSP build/make/target/product/*.mk files. A `repo sync
# --force-sync` of ~/lineage/ silently wipes them. After any sync, re-run
# this script.
#
# Removes Tier 1 + Tier 2 + Tier 3 (~80–90 MB). See CLAUDE.md "Local
# Lineage tree mods". Tier 3 = packages that survived to build #14 and
# are pure dead weight in a kiosk: BookmarkProvider, PartnerBookmarksProvider,
# HTMLViewer, BluetoothMidiService, MusicFX, CallLogBackup. WallpaperBackup
# is NOT here — it's gated by DISABLE_WALLPAPER_BACKUP, set in gsi_r1.mk.
#
# Idempotent: every removal is a no-op if already done.

set -euo pipefail

LINEAGE="${LINEAGE:-/home/khalifa/lineage}"
cd "$LINEAGE"

say() { printf "  %s\n" "$*"; }

# perl with -0777 reads the whole file; multiline regex matches across newlines.
# Each pattern targets the EXACT package list as Lineage/AOSP write it. If a
# future merge changes whitespace or ordering, the regex fails closed (no edit)
# and the package returns to the build — fail-safe rather than silent breakage.

# ---------------------------------------------------------------------------
# vendor/lineage/config/common.mk
#   - ExactCalculator + Jelly  (PRODUCT_IS_ATV-gated block, both removed)
#   - LineageParts + LineageSetupWizard  (PRODUCT_IS_AUTOMOTIVE-gated, both removed)
#   - Updater  (keep LineageSettingsProvider; drop Updater only)
#   - init.lineage-updater.rc  (PRODUCT_COPY_FILES — Updater's init script,
#     orphaned once Updater is gone)
# ---------------------------------------------------------------------------
echo "=> vendor/lineage/config/common.mk"
perl -0777 -i -pe '
  $c1 = s|^PRODUCT_PACKAGES \+= \\\n    ExactCalculator \\\n    Jelly\n||m;
  $c2 = s|^PRODUCT_PACKAGES \+= \\\n    LineageParts \\\n    LineageSetupWizard\n||m;
  $c3 = s|^PRODUCT_PACKAGES \+= \\\n    LineageSettingsProvider \\\n    Updater\n|PRODUCT_PACKAGES += \\\n    LineageSettingsProvider\n|m;
  $c4 = s|^PRODUCT_COPY_FILES \+= \\\n    vendor/lineage/prebuilt/common/etc/init/init\.lineage-updater\.rc:\$\(TARGET_COPY_OUT_SYSTEM_EXT\)/etc/init/init\.lineage-updater\.rc\n||m;
  print STDERR "    ExactCalculator+Jelly: ", ($c1?"removed":"already gone"), "\n";
  print STDERR "    LineageParts+SetupWizard: ", ($c2?"removed":"already gone"), "\n";
  print STDERR "    Updater: ", ($c3?"removed":"already gone"), "\n";
  print STDERR "    init.lineage-updater.rc: ", ($c4?"removed":"already gone"), "\n";
' vendor/lineage/config/common.mk

# ---------------------------------------------------------------------------
# vendor/lineage/config/telephony.mk
#   - messaging + Stk  (whole block — both are tier 1)
# ---------------------------------------------------------------------------
echo "=> vendor/lineage/config/telephony.mk"
perl -0777 -i -pe '
  $c = s|^# Telephony packages\nPRODUCT_PACKAGES \+= \\\n    messaging \\\n    Stk\n\n||m;
  print STDERR "    messaging+Stk: ", ($c?"removed":"already gone"), "\n";
' vendor/lineage/config/telephony.mk

# ---------------------------------------------------------------------------
# build/make/target/product/aosp_product.mk
#   - messaging  (one line in a longer list — drop just that line)
# ---------------------------------------------------------------------------
echo "=> build/make/target/product/aosp_product.mk"
perl -0777 -i -pe '
  $c = s|^    messaging \\\n||m;
  print STDERR "    messaging: ", ($c?"removed":"already gone"), "\n";
' build/make/target/product/aosp_product.mk

# ---------------------------------------------------------------------------
# device/generic/common/gsi_product.mk
#   - Camera2 + messaging  (both in one block; messaging is last)
#     Keep Browser2 / Dialer / LatinIME — those are still useful or risky to drop.
# ---------------------------------------------------------------------------
echo "=> device/generic/common/gsi_product.mk"
perl -0777 -i -pe '
  $c1 = s|^    Camera2 \\\n||m;
  $c2 = s|^    LatinIME \\\n    messaging \\\n|    LatinIME\n|m;
  print STDERR "    Camera2: ", ($c1?"removed":"already gone"), "\n";
  print STDERR "    messaging: ", ($c2?"removed":"already gone"), "\n";
' device/generic/common/gsi_product.mk

# ---------------------------------------------------------------------------
# build/make/target/product/generic_system.mk
#   - LiveWallpapersPicker, Stk, Tag
# ---------------------------------------------------------------------------
echo "=> build/make/target/product/generic_system.mk"
perl -0777 -i -pe '
  $c1 = s|^    LiveWallpapersPicker \\\n||m;
  $c2 = s|^    Stk \\\n||m;
  $c3 = s|^    Tag \\\n||m;
  print STDERR "    LiveWallpapersPicker: ", ($c1?"removed":"already gone"), "\n";
  print STDERR "    Stk: ", ($c2?"removed":"already gone"), "\n";
  print STDERR "    Tag: ", ($c3?"removed":"already gone"), "\n";
' build/make/target/product/generic_system.mk

# ---------------------------------------------------------------------------
# build/make/target/product/full_base.mk
#   - LiveWallpapersPicker (also redeclared here)
# ---------------------------------------------------------------------------
echo "=> build/make/target/product/full_base.mk"
perl -0777 -i -pe '
  $c = s|^    LiveWallpapersPicker \\\n||m;
  print STDERR "    LiveWallpapersPicker: ", ($c?"removed":"already gone"), "\n";
' build/make/target/product/full_base.mk

# ---------------------------------------------------------------------------
# build/make/target/product/handheld_system.mk
#   Tier 2: BasicDreams, BuiltInPrintService, DeviceAsWebcam, EasterEgg,
#           ManagedProvisioning, PrintRecommendationService, PrintSpooler,
#           SimAppDialog
#   Tier 3: BookmarkProvider (no browser → no bookmarks),
#           BluetoothMidiService (MIDI-over-BT, useless on R1),
#           MusicFX (equalizer UI never reachable from R1Launcher)
# ---------------------------------------------------------------------------
echo "=> build/make/target/product/handheld_system.mk"
perl -0777 -i -pe '
  for my $p (qw(BasicDreams BluetoothMidiService BookmarkProvider BuiltInPrintService DeviceAsWebcam EasterEgg ManagedProvisioning MusicFX PrintRecommendationService PrintSpooler SimAppDialog)) {
    $c = s|^    \Q$p\E \\\n||m;
    print STDERR "    $p: ", ($c?"removed":"already gone"), "\n";
  }
' build/make/target/product/handheld_system.mk

# ---------------------------------------------------------------------------
# build/make/target/product/media_system.mk
#   - CompanionDeviceManager (BT pairing flow, kiosk pairs from launcher)
#   - HTMLViewer (system intent handler for text/html — kiosk app should
#     own URL handling itself; removing this kills a default route to a
#     barebones webview activity that bypasses the launcher)
# ---------------------------------------------------------------------------
echo "=> build/make/target/product/media_system.mk"
perl -0777 -i -pe '
  for my $p (qw(CompanionDeviceManager HTMLViewer)) {
    $c = s|^    \Q$p\E \\\n||m;
    print STDERR "    $p: ", ($c?"removed":"already gone"), "\n";
  }
' build/make/target/product/media_system.mk

# ---------------------------------------------------------------------------
# build/make/target/product/generic_system.mk
#   Tier 2 already removed: LiveWallpapersPicker, Stk, Tag
#   Tier 3: PartnerBookmarksProvider (browser bookmarks DB, orphaned with
#           Jelly + BookmarkProvider gone)
# ---------------------------------------------------------------------------
echo "=> build/make/target/product/generic_system.mk (Tier 3)"
perl -0777 -i -pe '
  $c = s|^    PartnerBookmarksProvider \\\n||m;
  print STDERR "    PartnerBookmarksProvider: ", ($c?"removed":"already gone"), "\n";
' build/make/target/product/generic_system.mk

# ---------------------------------------------------------------------------
# build/make/target/product/telephony_system.mk
#   - CallLogBackup (we do not back up call history; kiosk does not
#     restore from a previous device. Removing strips the backup-agent
#     classpath entry too)
# ---------------------------------------------------------------------------
echo "=> build/make/target/product/telephony_system.mk"
perl -0777 -i -pe '
  $c = s|^    CallLogBackup \\\n||m;
  print STDERR "    CallLogBackup: ", ($c?"removed":"already gone"), "\n";
' build/make/target/product/telephony_system.mk

# ---------------------------------------------------------------------------
# build/make/target/product/handheld_product.mk
#   - Camera2 leaks through despite our `LINEAGE_BUILD := r1` setting because
#     gsi_r1.mk sets that variable AFTER the inherit-product chain runs, so the
#     ifeq($(LINEAGE_BUILD),) conditional in handheld_product.mk evaluates as
#     empty and Camera2 gets pulled in. Just delete the Camera2 line — keep
#     LatinIME (we want the keyboard).
# ---------------------------------------------------------------------------
echo "=> build/make/target/product/handheld_product.mk"
perl -0777 -i -pe '
  $c = s|^    Camera2 \\\n||m;
  print STDERR "    Camera2 (LINEAGE_BUILD-empty branch): ", ($c?"removed":"already gone"), "\n";
' build/make/target/product/handheld_product.mk

# ---------------------------------------------------------------------------
# build/make/target/product/aosp_product.mk
#   - ro.config.notification_sound?=pixiedust.ogg + ro.config.ringtone?=Ring_Synth_04.ogg
#     These land in /system/product/etc/build.prop, which loads AFTER /system/build.prop,
#     so they clobber our system.prop empty values. Removing them lets our
#     device-tree system.prop empty values win.
# ---------------------------------------------------------------------------
echo "=> build/make/target/product/aosp_product.mk"
perl -0777 -i -pe '
  $c1 = s|^    ro\.config\.notification_sound\?=pixiedust\.ogg \\\n||m;
  $c2 = s|^    ro\.config\.ringtone\?=Ring_Synth_04\.ogg \\\n||m;
  print STDERR "    ro.config.notification_sound (pixiedust): ", ($c1?"removed":"already gone"), "\n";
  print STDERR "    ro.config.ringtone (Ring_Synth_04): ", ($c2?"removed":"already gone"), "\n";
' build/make/target/product/aosp_product.mk

# ---------------------------------------------------------------------------
# device/generic/common/gsi_product.mk
#   - ro.config.notification_sound + ro.config.ringtone (also redeclared here,
#     and gsi_product.mk IS in our inheritance chain — these are the actual
#     ones reaching /system/product/etc/build.prop)
# ---------------------------------------------------------------------------
echo "=> device/generic/common/gsi_product.mk (notification props)"
perl -0777 -i -pe '
  $c1 = s|^    ro\.config\.notification_sound\?=pixiedust\.ogg \\\n||m;
  $c2 = s|^    ro\.config\.ringtone\?=Ring_Synth_04\.ogg \\\n||m;
  print STDERR "    ro.config.notification_sound (pixiedust): ", ($c1?"removed":"already gone"), "\n";
  print STDERR "    ro.config.ringtone (Ring_Synth_04): ", ($c2?"removed":"already gone"), "\n";
' device/generic/common/gsi_product.mk

# ---------------------------------------------------------------------------
# build/make/target/product/full_base.mk
#   - ro.config.notification_sound + ro.config.ringtone (defensive — full_base
#     is sometimes pulled in transitively)
# ---------------------------------------------------------------------------
echo "=> build/make/target/product/full_base.mk (notification props)"
perl -0777 -i -pe '
  $c1 = s|^    ro\.config\.notification_sound\?=pixiedust\.ogg\n||m;
  $c2 = s|^    ro\.config\.ringtone\?=Ring_Synth_04\.ogg \\\n||m;
  print STDERR "    ro.config.notification_sound (pixiedust): ", ($c1?"removed":"already gone"), "\n";
  print STDERR "    ro.config.ringtone (Ring_Synth_04): ", ($c2?"removed":"already gone"), "\n";
' build/make/target/product/full_base.mk

# ---------------------------------------------------------------------------
# frameworks/base/data/sounds/AllAudio.mk
#   Nuke ALL notification ogg PRODUCT_COPY_FILES (~75 lines).
#   Why: even with `ro.config.notification_sound=` empty, MediaProvider scans
#   /system/product/media/audio/notifications/ on first boot, and *something*
#   (suspected: ensureDefaultRingtones() running pre-launcher, or a per-channel
#   sound URI resolved at NotificationChannel registration time) writes one of
#   them as Settings.System.NOTIFICATION_SOUND before init.rc gets to clear it.
#   We confirmed empirically (build #16, post-userdata-wipe): notification_sound
#   ended up as `pixiedust.ogg` URI in the live Settings DB and a chirp fired
#   during the bootanim "Loading…" window — before sys.boot_completed=1, so the
#   r1_kiosk.rc `settings put` couldn't suppress it.
#   With the files physically absent, no URI can resolve to audio data; any
#   default-channel notification plays silence. Ringtones/alarms/UI sounds are
#   kept (alarm clock might use them; the launcher doesn't generate calls).
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Tier 4: more apps the kiosk launcher never reaches
#   - Dialer (com.android.dialer): R1 SIM is data-only, no calls → kill the
#     phone UI. Telecom + TeleService + TelephonyProvider stay (cellular data
#     still works without Dialer).
#   - DocumentsUI: file picker for Intent.ACTION_OPEN_DOCUMENT. R1Launcher
#     never fires those intents → dead code. (Settings is NOT removed —
#     hundreds of system code paths launch Settings.* activities.)
#   - Browser2: the AOSP minimal browser. We already removed Jelly; no need
#     for a second browser, and removing kills the http VIEW intent handler
#     (kiosk won't accidentally render a URL outside the launcher webview).
#   - Contacts: the user-facing contacts app. ContactsProvider stays
#     (telephony backend uses it for caller-ID lookup).
# ---------------------------------------------------------------------------
echo "=> Tier 4: telephony_product.mk + gsi_product.mk Dialer"
perl -0777 -i -pe '
  $c = s|^    Dialer \\\n||m;
  print STDERR "    Dialer (telephony_product): ", ($c?"removed":"already gone"), "\n";
' build/make/target/product/telephony_product.mk
perl -0777 -i -pe '
  $c = s|^    Dialer \\\n||m;
  print STDERR "    Dialer (gsi_product): ", ($c?"removed":"already gone"), "\n";
' device/generic/common/gsi_product.mk

echo "=> Tier 4: handheld_system.mk DocumentsUI"
perl -0777 -i -pe '
  $c = s|^    DocumentsUI \\\n||m;
  print STDERR "    DocumentsUI: ", ($c?"removed":"already gone"), "\n";
' build/make/target/product/handheld_system.mk

echo "=> Tier 4: handheld_product.mk + gsi_product.mk Browser2"
perl -0777 -i -pe '
  $c = s|^    Browser2 \\\n||m;
  print STDERR "    Browser2 (handheld_product): ", ($c?"removed":"already gone"), "\n";
' build/make/target/product/handheld_product.mk
perl -0777 -i -pe '
  $c = s|^    Browser2 \\\n||m;
  print STDERR "    Browser2 (gsi_product): ", ($c?"removed":"already gone"), "\n";
' device/generic/common/gsi_product.mk

echo "=> Tier 4: handheld_product.mk Contacts (app)"
perl -0777 -i -pe '
  $c = s|^    Contacts \\\n||m;
  print STDERR "    Contacts (app, not provider): ", ($c?"removed":"already gone"), "\n";
' build/make/target/product/handheld_product.mk

# ---------------------------------------------------------------------------
# Tier 5: deeper kiosk slim
#   - CalendarProvider: no calendar app exposes it (Etar removed in Tier 1)
#   - MmsService: R1 SIM is data-only; no SMS/MMS pipeline
#   - MtpService: USB MTP transfer; we use ADB exclusively
#   - BlockedNumberProvider: orphaned with Dialer gone (Tier 4)
#   - VpnDialogs: kiosk has no user-installable VPN apps
#   - E2eeContactKeysProvider: Android 14 E2EE messaging; no SMS app to use it
#   Skipped from earlier list:
#     - NfcNci: gated by ifeq($(RELEASE_PACKAGE_NFC_STACK),NfcNci); the else
#       branch installs com.android.nfcservices apex — same problem
#     - SoundPicker: comes via build/release/build_flags.scl
#       (RELEASE_PACKAGE_SOUND_PICKER), not standard PRODUCT_PACKAGES
#     - MediaProviderLegacy: kept; R1Launcher likely uses MediaStore for
#       voice recordings / images
#   DSU is removed via gsi_r1.mk's PRODUCT_NO_DYNAMIC_SYSTEM_UPDATE := true
# ---------------------------------------------------------------------------
echo "=> Tier 5: handheld_system.mk (5 pkgs)"
perl -0777 -i -pe '
  for my $p (qw(BlockedNumberProvider CalendarProvider MmsService MtpService VpnDialogs)) {
    $c = s|^    \Q$p\E \\\n||m;
    print STDERR "    $p: ", ($c?"removed":"already gone"), "\n";
  }
' build/make/target/product/handheld_system.mk

echo "=> Tier 5: base_system.mk E2eeContactKeysProvider"
perl -0777 -i -pe '
  $c = s|^    E2eeContactKeysProvider \\\n||m;
  print STDERR "    E2eeContactKeysProvider: ", ($c?"removed":"already gone"), "\n";
' build/make/target/product/base_system.mk

echo "=> frameworks/base/data/sounds/AllAudio.mk (nuke notification + ui oggs)"
perl -0777 -i -pe '
  for my $dir (qw(notifications ui)) {
    $count = () = m|^[ \t]+\$\(LOCAL_PATH\)/[^:\n]+:\$\(TARGET_COPY_OUT_PRODUCT\)/media/audio/\Q$dir\E/[^\\\n]+\\\n|gm;
    s|^[ \t]+\$\(LOCAL_PATH\)/[^:\n]+:\$\(TARGET_COPY_OUT_PRODUCT\)/media/audio/\Q$dir\E/[^\\\n]+\\\n||gm;
    print STDERR "    $dir oggs: $count line(s) ", ($count?"removed":"already gone"), "\n";
  }
' frameworks/base/data/sounds/AllAudio.mk

echo
echo "Done. Run an incremental build to see the slim:"
echo "  cd ~/lineage && source build/envsetup.sh && lunch gsi_r1-ap2a-userdebug && \\"
echo "    WITH_DEXPREOPT=false mka systemimage -j6 2>&1 | tee build.log"
