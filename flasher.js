// ═══════════════════════════════════════════════════════════════
// CarrotOS Flasher · flasher.js
// ───────────────────────────────────────────────────────────────
// Thin wrapper around kdrag0n/fastboot.js. Exposes connectDevice()
// and runFlash() to app.js. All UI state lives there; this file
// only talks to the device and emits log/progress events.
// ═══════════════════════════════════════════════════════════════

import * as fb from "./lib/fastboot.mjs";

// fastboot.js debug levels: 0=Silent, 1=Debug, 2=Verbose
fb.setDebugLevel(1);

// ─── log bus ───────────────────────────────────────────────────
// Tiny pub/sub so both flasher.js internals and app.js can write
// to the same on-screen log pane.
export const log = (() => {
  const subs = new Set();
  return {
    subscribe: fn => subs.add(fn),
    emit: (kind, msg) => subs.forEach(fn => fn(kind, msg)),
  };
})();

const emit = (k, m) => log.emit(k, m);

// ─── connect ───────────────────────────────────────────────────
let _liveDevice = null;  // module-scoped handle so we can dispose on reconnect

export async function connectDevice() {
  // If a previous session's device is still claimed, release it before a new
  // open() call — otherwise WebUSB throws "an operation that changes the
  // device state is in progress" or just refuses the second open.
  if (_liveDevice) {
    try {
      const usbDev = _liveDevice.device?.device_;
      if (usbDev?.opened) await usbDev.close();
    } catch (e) {
      emit("note", `# stale device close failed (ignored): ${e.message || e}`);
    }
    _liveDevice = null;
  }

  const dev = new fb.FastbootDevice();
  emit("info", "# requesting device permission via WebUSB");
  await dev.connect();
  _liveDevice = dev;
  emit("ok", `# usb claimed`);
  let product = "?", serial = "?";
  try {
    product = await dev.getVariable("product");
    serial  = await dev.getVariable("serialno");
    emit("info", `# product=${product}  serial=${serial}`);
    const slot = await dev.getVariable("current-slot").catch(() => null);
    if (slot) emit("info", `# current-slot=${slot}`);
    const mode = await dev.getVariable("is-userspace").catch(() => null);
    if (mode === "yes") emit("info", `# mode=fastbootd (userspace)`);
    else if (mode === "no") emit("info", `# mode=bootloader fastboot`);
  } catch (e) {
    emit("note", `# variable probe failed (still connected): ${e.message || e}`);
  }
  return { _raw: dev, product, serial };
}

// ─── partition mode classification ─────────────────────────────
// `super` partitions (logical) → fastbootd only. Physical partitions →
// bootloader fastboot only. Trying the wrong one yields "FAIL This
// partition doesn't exist" without any other useful error.
const LOGICAL_PARTS  = new Set(["system", "vendor", "product", "system_ext", "odm"]);
const PHYSICAL_PARTS = new Set(["vbmeta", "vbmeta_system", "boot", "dtbo", "userdata", "metadata"]);

async function getMode(dev) {
  try {
    const v = await dev.getVariable("is-userspace");
    if (v === "yes") return "fastbootd";
    if (v === "no")  return "bootloader";
  } catch {}
  return "unknown";
}

// 25s upper bound on a reboot+reconnect. Past that, WebUSB has likely
// lost track of the device after re-enumeration and the only reliable
// recovery is a manual user reconnect (Chrome's permission model
// requires a user gesture to re-claim a re-enumerated device that
// changed its endpoint layout).
function withTimeout(promise, ms, label) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`${label} timed out after ${ms / 1000}s`)), ms)
    ),
  ]);
}

async function ensureMode(dev, want, emit) {
  const cur = await getMode(dev);
  if (cur === want) return;
  const target = want === "fastbootd" ? "fastboot" : "bootloader";
  const label  = want === "fastbootd" ? "fastbootd" : "bootloader fastboot";
  emit("note", `# need ${label} (currently ${cur}). rebooting…`);
  try {
    await withTimeout(dev.reboot(target, true), 25_000, `reboot to ${label}`);
    emit("ok", `# now in ${label}`);
  } catch (e) {
    emit("err", `# ${e.message || e}`);
    emit("note", "# the device probably rebooted into the right mode but webusb");
    emit("note", "# lost the re-enumerated handle. close this tab fully, open a");
    emit("note", "# new one, reconnect, and only flash partitions that match the");
    emit("note", `# current mode (${label} expected).`);
    throw new Error(`${label} reboot lost USB handle — reconnect and resume`);
  }
}

function modeForPartition(p) {
  if (p.action === "erase" && p.name === "userdata") return "bootloader";
  if (LOGICAL_PARTS.has(p.name))  return "fastbootd";
  if (PHYSICAL_PARTS.has(p.name)) return "bootloader";
  return null; // unknown — try current mode
}

// ─── flash sequence ────────────────────────────────────────────
export async function runFlash(deviceWrap, parts, opts) {
  const {
    reboot = true,
    onPartitionStart, onPartitionProgress, onPartitionDone, onPartitionError,
  } = opts || {};
  const dev = deviceWrap._raw;

  emit("info", `# starting flash · ${parts.length} step${parts.length === 1 ? "" : "s"}`);

  // Reorder so we minimize bootloader↔fastbootd round-trips:
  // physical partitions first (vbmeta, then optional userdata wipe),
  // then logical partitions (vendor, system). Same-class items keep
  // their relative order from the caller.
  const score = (p) => {
    const m = modeForPartition(p);
    if (m === "bootloader") return 0;
    return 1; // fastbootd or unknown
  };
  parts = [...parts].sort((a, b) => score(a) - score(b));

  for (const p of parts) {
    onPartitionStart?.(p.name);
    emit("cmd", `${p.action}:${p.name}${p.file ? ` (${p.file.name}, ${(p.file.size / 1048576).toFixed(1)} MB)` : ""}`);

    try {
      // route to the right fastboot mode for this partition class
      const want = modeForPartition(p);
      if (want) await ensureMode(dev, want, emit);

      if (p.action === "erase" && p.name === "userdata") {
        emit("cmd", "erase:userdata");
        await dev.runCommand("erase:userdata");
        try {
          emit("cmd", "erase:metadata");
          await dev.runCommand("erase:metadata");
        } catch (e) {
          emit("note", `# erase:metadata not supported (ok to ignore): ${e.message || e}`);
        }

      } else if (p.action === "erase") {
        await dev.runCommand(`erase:${p.name}`);

      } else if (p.action === "flash") {
        // fastboot.js progress callback receives a fraction 0..1
        await dev.flashBlob(p.name, p.file, (frac) => {
          if (typeof frac === "number") {
            onPartitionProgress?.(p.name, frac * 100);
          }
        });
      }

      onPartitionDone?.(p.name);
      emit("ok", `# ${p.action}:${p.name} ✓`);

    } catch (err) {
      onPartitionError?.(p.name, err);
      const msg = String(err.message || err);
      emit("err", `# ${p.action}:${p.name} FAILED · ${msg}`);
      // explanatory hints for common failures
      if (/transferIn|transferOut|transfer error|stall|babble/i.test(msg)) {
        emit("note", "# tip: this is almost always ModemManager on Linux grabbing the");
        emit("note", "# usb endpoint mid-transfer. stop it and retry the flash:");
        emit("note", "#   sudo systemctl stop ModemManager");
        emit("note", "# also try: a different cable, no usb hub, direct port.");
      }
      if (/USER_ACTION_MAP|access denied|not allowed|claim|permission/i.test(msg)) {
        emit("note", "# tip: unplug/replug and re-authorize the device. on linux,");
        emit("note", "# ensure your user is in the plugdev group and udev rules exist");
        emit("note", "# for vendor 18d1 (google fastboot).");
      }
      if (/operation that changes the device state|already in progress|device is open/i.test(msg)) {
        emit("note", "# tip: stale webusb handle from a previous attempt. fully CLOSE");
        emit("note", "# this tab (not just refresh), unplug + replug the r1, then open");
        emit("note", "# a fresh tab and reconnect.");
      }
      if (/partition.*not found|doesn't exist|This partition/i.test(msg)) {
        emit("note", "# tip: this partition isn't visible from the current fastboot mode.");
        emit("note", "# fastbootd handles logical (system/vendor/product); bootloader");
        emit("note", "# fastboot handles physical (userdata/boot/vbmeta).");
      }
      if (/locked|Device is locked/i.test(msg)) {
        emit("note", "# tip: bootloader is still locked. complete the rabbithole unlock");
        emit("note", "# flow first (step 00 → before you start).");
      }
      throw err;
    }
  }

  if (reboot) {
    emit("cmd", "reboot");
    try {
      // empty target = reboot to system
      await dev.reboot("", false);
      emit("ok", "# device is rebooting into the new system");
    } catch (e) {
      emit("note", `# reboot command result: ${e.message || e} (often fine — device may have already started rebooting)`);
    }
  }
}
