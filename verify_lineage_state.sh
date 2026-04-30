#!/usr/bin/env bash
# Pre-flight verifier — confirms all edits OUTSIDE the device tree are still
# in place. A `repo sync --force-sync` of ~/lineage/ silently wipes them.
# Returns non-zero if any regression is detected. Run before /build.

set -uo pipefail

LINEAGE="${LINEAGE:-/home/khalifa/lineage}"
fail=0

ok()  { printf "  [OK]   %s\n" "$*"; }
bad() { printf "  [FAIL] %s\n" "$*"; fail=$((fail+1)); }

echo "== Device tree patches in $LINEAGE/device/rabbit/r1/ =="

bc="$LINEAGE/device/rabbit/r1/BoardConfig.mk"
gr="$LINEAGE/device/rabbit/r1/gsi_r1.mk"

if [[ ! -f "$bc" ]]; then
  bad "BoardConfig.mk missing — device tree not present at expected path"
elif grep -qE '^\s*include\s+device/mediatek/sepolicy/BoardSEPolicyConfig\.mk' "$bc"; then
  bad "BoardConfig: mediatek sepolicy include is NOT commented out"
else
  ok "BoardConfig: mediatek sepolicy include removed"
fi

grep -q '^include vendor/lineage/config/BoardConfigLineage.mk' "$bc" 2>/dev/null \
  && ok "BoardConfig: BoardConfigLineage.mk is included" \
  || bad "BoardConfig: BoardConfigLineage.mk include missing"

grep -q '^TARGET_BOOTANIMATION' "$bc" 2>/dev/null \
  && ok "BoardConfig: TARGET_BOOTANIMATION is set (kiosk bootanim)" \
  || bad "BoardConfig: TARGET_BOOTANIMATION missing — bootanim won't be hijacked"

grep -q '^TARGET_SYSTEM_PROP' "$bc" 2>/dev/null \
  && ok "BoardConfig: TARGET_SYSTEM_PROP is set (system.prop wired)" \
  || bad "BoardConfig: TARGET_SYSTEM_PROP missing — qemu.hw.mainkeys etc. won't apply"

if [[ ! -f "$gr" ]]; then
  bad "gsi_r1.mk missing"
else
  grep -q '^LINEAGE_BUILD := r1' "$gr" \
    && ok "gsi_r1: LINEAGE_BUILD := r1 is set" \
    || bad "gsi_r1: LINEAGE_BUILD := r1 missing"

  grep -q 'inherit-product.*vendor/lineage/config/common\.mk' "$gr" \
    && ok "gsi_r1: inherits vendor/lineage/config/common.mk" \
    || bad "gsi_r1: inherit of vendor/lineage/config/common.mk missing — boot will fail (LineageSettingsProvider NPE)"

  grep -q 'PRODUCT_PACKAGES.*R1Launcher\|R1Launcher' "$gr" \
    && ok "gsi_r1: R1Launcher in PRODUCT_PACKAGES" \
    || bad "gsi_r1: R1Launcher NOT in PRODUCT_PACKAGES — launcher won't ship"

  grep -q 'PRODUCT_SOONG_NAMESPACES.*FMRadio' "$gr" \
    && ok "gsi_r1: FMRadio Soong namespace declared" \
    || bad "gsi_r1: FMRadio Soong namespace missing"
fi

echo
echo "== Status bar 0dp (vendor/lineage/overlay/no-rro) =="
dim="$LINEAGE/vendor/lineage/overlay/no-rro/frameworks/base/core/res/res/values/dimens.xml"
if [[ ! -f "$dim" ]]; then
  bad "dimens.xml not found at $dim"
elif grep -q '>28dp<' "$dim"; then
  bad "dimens.xml: still has 28dp — run /post-sync to re-apply"
else
  ok "dimens.xml: 28dp removed (status bar 0dp)"
fi

echo
echo "== Package slim (sample) =="
common="$LINEAGE/vendor/lineage/config/common.mk"
handheld="$LINEAGE/build/make/target/product/handheld_system.mk"
gsiprod="$LINEAGE/device/generic/common/gsi_product.mk"

check_slimmed() {
  local label="$1" file="$2" pkg="$3"
  if [[ ! -f "$file" ]]; then bad "$label: source file missing ($file)"; return; fi
  if grep -qE "^\s+${pkg}\s*\\\\?\s*$" "$file"; then
    bad "$label: $pkg still present — run /post-sync"
  else
    ok "$label: $pkg slimmed"
  fi
}

check_slimmed "common.mk" "$common" "Updater"
check_slimmed "common.mk" "$common" "Jelly"
check_slimmed "common.mk" "$common" "LineageParts"
check_slimmed "handheld_system.mk" "$handheld" "EasterEgg"
check_slimmed "handheld_system.mk" "$handheld" "PrintSpooler"
check_slimmed "gsi_product.mk" "$gsiprod" "Camera2"

# Notification sound props should be removed from /product partition sources
echo
echo "== Notification chime sources (should be removed) =="
for f in \
  "$LINEAGE/build/make/target/product/aosp_product.mk" \
  "$LINEAGE/device/generic/common/gsi_product.mk" \
  "$LINEAGE/build/make/target/product/full_base.mk"; do
  if [[ -f "$f" ]] && grep -q 'ro\.config\.notification_sound?=pixiedust\.ogg' "$f"; then
    bad "$(basename $f): pixiedust.ogg notification default still present"
  else
    ok "$(basename $f): pixiedust.ogg removed"
  fi
done

echo
if [[ $fail -eq 0 ]]; then
  echo "All checks passed. Safe to build."
  exit 0
else
  echo "$fail regression(s) detected. Run /post-sync (or slim_lineage.sh + the dimens.xml sed) before building."
  exit 1
fi
