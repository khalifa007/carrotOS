---
description: Re-apply local Lineage tree mods after a repo sync
---

After running `repo sync --force-sync` on `~/lineage/`, the upstream-tree edits get silently wiped. Re-apply them all in order:

**Steps:**

1. **Run the package slim:**
   ```
   bash /home/khalifa/Desktop/cipherOsCustom/slim_lineage.sh
   ```
   Idempotent — every removal is a no-op if already done. Watch the output for `removed` vs `already gone` per line; this tells you which upstream files actually drifted.

2. **Re-apply the status-bar 0dp patch:**
   ```
   sed -i 's/>28dp</>0dp</g' /home/khalifa/lineage/vendor/lineage/overlay/no-rro/frameworks/base/core/res/res/values/dimens.xml
   ```
   Verify: `grep dp /home/khalifa/lineage/vendor/lineage/overlay/no-rro/frameworks/base/core/res/res/values/dimens.xml | grep status_bar_height` — should show `0dp` for `_default` and `_portrait`.

3. **Verify everything is back in place:**
   ```
   bash /home/khalifa/Desktop/cipherOsCustom/verify_lineage_state.sh
   ```
   Must return exit 0. If it doesn't, surface the failing checks — likely a new upstream file/format change broke a regex.

4. **Note for user.** Device tree patches in `device/rabbit/r1/` are NOT touched by repo sync (we own that tree), but if the verifier flagged any of those, the device tree was somehow re-cloned and needs hand-patching from CLAUDE.md "Required device-tree patches".

5. **Suggest `/build` next.** The .mk edits invalidate intermediate outputs; an incremental rebuild will pick them up.

Reference: memory `project_local_lineage_mods.md`, CLAUDE.md "Local Lineage tree mods".
