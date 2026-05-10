// ============================================================
// carrot // flasher — app.js
// ============================================================

import { connectDevice, runFlash, log as logBus } from "./flasher.js";

const state = {
    step: 0,
    images: { system: null, vbmeta: null, vendor: null },
    hashes: { system: null, vbmeta: null, vendor: null },
    options: { vbmeta: true, vendor: true, wipe: false, reboot: true },
    device: null,
};

const TOTAL = 6;

// ===== browser feature gate =====
// WebUSB needs both (a) a chromium browser and (b) a secure context
// (HTTPS or http://localhost / http://127.0.0.1). file:// is blocked.
(function gateBrowser() {
    const hasUsb = "usb" in navigator;
    const isFileProto = location.protocol === "file:";
    const isSecure = window.isSecureContext;
    if (!hasUsb || !isSecure) {
        const banner = document.getElementById("browser-warning");
        const text   = document.getElementById("browser-warning-text");
        let msg;
        if (isFileProto) {
            msg = "webusb is blocked on file://. serve the page over http: " +
                  "open a terminal, run  cd ~/Desktop/carrotFlasher && python3 -m http.server 8765  " +
                  "then visit http://127.0.0.1:8765";
        } else if (!isSecure) {
            msg = "webusb requires https or http://localhost. " +
                  "you're on " + location.origin + " — switch to a secure origin.";
        } else {
            msg = "webusb unavailable in this browser. open in chrome / edge / brave to flash.";
        }
        if (text) text.textContent = msg;
        if (banner) banner.hidden = false;

        const cc = document.getElementById("connect-card");
        if (cc) {
            cc.disabled = true;
            document.getElementById("connect-label").textContent = "webusb unavailable here";
            document.getElementById("connect-sub").textContent = isFileProto ? "serve via http://127.0.0.1" : "switch to a chromium browser";
        }
    }
})();

// ===== stepper navigation =====
function goto(n) {
    if (n < 0 || n >= TOTAL) return;
    state.step = n;
    document.querySelectorAll(".step").forEach(s => {
        s.classList.toggle("is-active", +s.dataset.step === n);
    });
    document.querySelectorAll(".step-pill").forEach(p => {
        const i = +p.dataset.step;
        p.classList.toggle("is-active", i === n);
        p.classList.toggle("is-done", i < n);
    });
    refreshGates();
    window.scrollTo({ top: 0, behavior: "smooth" });
}

function advance() {
    if (state.step === 1 && !state.images.system) return;
    if (state.step === 2 && !state.device) return;
    if (state.step === 3) { startFlash(); return; }
    goto(state.step + 1);
}
function back() { goto(state.step - 1); }
function restart() {
    state.images = { system: null, vbmeta: null, vendor: null };
    state.hashes = { system: null, vbmeta: null, vendor: null };
    state.device = null;
    document.querySelectorAll(".dropzone").forEach(z => {
        z.classList.remove("is-loaded");
        z.querySelector(".dz-file").textContent = "";
        z.querySelector(".dz-hash").textContent = "";
        z.querySelector('input[type="file"]').value = "";
    });
    const cc = document.getElementById("connect-card");
    cc?.classList.remove("is-connected");
    document.getElementById("connect-label").textContent = "authorize r1 over webusb";
    document.getElementById("connect-sub").textContent = "browser will prompt";
    document.getElementById("connect-dot").classList.remove("live");
    document.getElementById("connect-dot").classList.add("pulsing");
    setConnPill("disconnected");
    document.getElementById("log").innerHTML = "";
    document.getElementById("bars").innerHTML = "";
    goto(0);
}

function refreshGates() {
    // All three images required for the canonical first-flash from stock:
    //   - system.img : the GSI itself
    //   - vbmeta.img : flags=3 to disable AVB, else "corrupted OS"
    //   - vendor.img : default_network=9 patch, else mtkfusionrild SEGV-loops on wipe
    const pickAdv = document.querySelector('.step[data-step="1"] [data-action="advance"]');
    if (pickAdv) pickAdv.disabled = !(state.images.system && state.images.vbmeta && state.images.vendor);
    const connAdv = document.getElementById("continue-after-connect");
    if (connAdv) connAdv.disabled = !state.device;
}

function setConnPill(text, cls = "") {
    const p = document.getElementById("conn-pill");
    if (!p) return;
    p.textContent = text;
    p.className = "pill" + (cls ? " " + cls : "");
}

// ===== file pickers =====
function bytesPretty(n) {
    if (n < 1024) return n + " B";
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " kb";
    if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + " mb";
    return (n / (1024 * 1024 * 1024)).toFixed(2) + " gb";
}

async function sha256(file) {
    const buf = await file.arrayBuffer();
    const hash = await crypto.subtle.digest("SHA-256", buf);
    return Array.from(new Uint8Array(hash))
        .map(b => b.toString(16).padStart(2, "0")).join("");
}

async function adoptFile(zone, file) {
    const slot = zone.dataset.slot;
    state.images[slot] = file;
    zone.classList.add("is-loaded");
    zone.querySelector(".dz-file").textContent = `${file.name.toLowerCase()} · ${bytesPretty(file.size)}`;
    zone.querySelector(".dz-hash").textContent = "sha256: …";
    try {
        const h = await sha256(file);
        state.hashes[slot] = h;
        zone.querySelector(".dz-hash").textContent = `${h.slice(0, 16)}…${h.slice(-8)}`;
    } catch {
        zone.querySelector(".dz-hash").textContent = "sha256: failed";
    }
    if (slot === "vbmeta" || slot === "vendor") {
        const t = document.querySelector(`.toggle-card input[data-opt="${slot}"]`);
        if (t) {
            t.checked = true;
            state.options[slot] = true;
            renderPlan();
        }
    }
    refreshGates();
}

document.querySelectorAll(".dropzone").forEach(zone => {
    const input = zone.querySelector('input[type="file"]');
    input.addEventListener("change", e => {
        const f = e.target.files[0];
        if (f) adoptFile(zone, f);
    });
    ["dragenter", "dragover"].forEach(evt =>
        zone.addEventListener(evt, e => {
            e.preventDefault();
            zone.classList.add("is-dragging");
        })
    );
    ["dragleave", "drop"].forEach(evt =>
        zone.addEventListener(evt, e => {
            e.preventDefault();
            if (evt === "dragleave" && e.target !== zone) return;
            zone.classList.remove("is-dragging");
        })
    );
    zone.addEventListener("drop", e => {
        const f = e.dataTransfer.files[0];
        if (f) adoptFile(zone, f);
    });
});

// ===== connect device =====
async function connect() {
    const card = document.getElementById("connect-card");
    const label = document.getElementById("connect-label");
    const sub = document.getElementById("connect-sub");
    const dot = document.getElementById("connect-dot");
    try {
        label.textContent = "requesting…";
        sub.textContent = "pick the device in the prompt";
        const dev = await connectDevice();
        state.device = dev;
        card.classList.add("is-connected");
        dot.classList.remove("pulsing");
        dot.classList.add("live");
        label.textContent = `connected · ${(dev.product || "r1").toLowerCase()}`;
        sub.textContent = `serial ${(dev.serial || "—").slice(0, 12)}`;
        setConnPill("connected", "live");
    } catch (e) {
        label.textContent = "couldn't connect";
        sub.textContent = String(e.message || e).toLowerCase();
        card.classList.remove("is-connected");
        setConnPill("error", "error");
    }
    refreshGates();
}

// ===== toggles + plan =====
document.querySelectorAll(".toggle-card input").forEach(t => {
    t.addEventListener("change", () => {
        state.options[t.dataset.opt] = t.checked;
        renderPlan();
    });
});

function renderPlan() {
    const list = document.getElementById("plan-list");
    if (!list) return;
    const lines = [];
    if (state.options.wipe) {
        lines.push(`reboot bootloader`);
        lines.push(`-w · wipe userdata`);
        lines.push(`reboot fastboot`);
    }
    if (state.options.vbmeta && state.images.vbmeta) lines.push(`flash vbmeta vbmeta.img`);
    if (state.options.vendor && state.images.vendor) lines.push(`flash vendor vendor.img`);
    if (state.images.system) lines.push(`flash system system.img`);
    if (state.options.reboot) lines.push(`reboot · boot carrotos`);
    list.innerHTML = lines.length
        ? lines.map(l => `<li>${l}</li>`).join("")
        : `<li style="color:var(--dim)">— nothing to do —</li>`;
}

// ===== flash orchestration =====
async function startFlash() {
    if (!state.device) { alert("device not connected — go back to step 02"); return; }
    if (!state.images.system) { alert("system.img missing — go back to step 01"); return; }
    goto(4);

    const parts = [];
    if (state.options.wipe)                          parts.push({ name: "userdata", action: "erase" });
    if (state.options.vbmeta && state.images.vbmeta) parts.push({ name: "vbmeta", action: "flash", file: state.images.vbmeta });
    if (state.options.vendor && state.images.vendor) parts.push({ name: "vendor", action: "flash", file: state.images.vendor });
    parts.push({ name: "system", action: "flash", file: state.images.system });

    renderBars(parts);

    try {
        await runFlash(state.device, parts, {
            reboot: state.options.reboot,
            onPartitionStart: name => updateBar(name, { state: "active" }),
            onPartitionProgress: (name, pct) => updateBar(name, { pct }),
            onPartitionDone: name => updateBar(name, { state: "done", pct: 100 }),
            onPartitionError: (name, e) => updateBar(name, { state: "error", error: e }),
        });
        appendLog("ok", "# all partitions flashed");
        document.getElementById("done-glyph").textContent = "✓";
        document.getElementById("done-card").classList.remove("error");
        setTimeout(() => goto(5), 1200);
    } catch (e) {
        appendLog("err", `# flash failed: ${e.message || e}`);
        document.getElementById("done-title").textContent = "failed";
        document.getElementById("done-sub").textContent = String(e.message || e).toLowerCase();
        document.getElementById("done-glyph").textContent = "✗";
        document.getElementById("done-card").classList.add("error");
        setTimeout(() => goto(5), 1500);
    }
}

function renderBars(parts) {
    const wrap = document.getElementById("bars");
    wrap.innerHTML = parts.map(p => `
        <div class="bar" data-bar="${p.name}">
            <div class="bar-head">
                <span class="bar-name">${p.action === "erase" ? "wipe " : ""}${p.name}</span>
                <span class="bar-pct">0%</span>
            </div>
            <div class="bar-track"><div class="bar-fill"></div></div>
        </div>
    `).join("");
}
function updateBar(name, { state: st, pct, error }) {
    const el = document.querySelector(`[data-bar="${name}"]`);
    if (!el) return;
    if (st) {
        el.classList.remove("is-active", "is-done", "is-error");
        el.classList.add(`is-${st}`);
    }
    if (typeof pct === "number") {
        el.querySelector(".bar-fill").style.width = `${Math.min(100, Math.max(0, pct))}%`;
        el.querySelector(".bar-pct").textContent = `${Math.round(pct)}%`;
    }
    if (error) el.querySelector(".bar-pct").textContent = "err";
}

function appendLog(kind, msg) {
    const pane = document.getElementById("log");
    if (!pane) return;
    const line = document.createElement("span");
    line.className = `log-line log-line--${kind}`;
    line.textContent = msg;
    pane.appendChild(line);
    pane.appendChild(document.createTextNode("\n"));
    pane.scrollTop = pane.scrollHeight;
}
logBus.subscribe(appendLog);

document.querySelector('[data-action="copy-log"]')?.addEventListener("click", async (e) => {
    const txt = document.getElementById("log").textContent;
    try {
        await navigator.clipboard.writeText(txt);
        e.currentTarget.textContent = "copied";
        setTimeout(() => (e.currentTarget.textContent = "copy"), 1200);
    } catch {
        e.currentTarget.textContent = "select & copy";
    }
});

// ===== action delegation =====
document.body.addEventListener("click", e => {
    const t = e.target.closest("[data-action]");
    if (!t) return;
    const action = t.dataset.action;
    if (action === "advance") advance();
    else if (action === "back") back();
    else if (action === "connect-device") connect();
    else if (action === "start-flash") startFlash();
    else if (action === "restart") restart();
    else if (action === "jump-flash") { e.preventDefault(); goto(1); }
});

// ===== init =====
renderPlan();
const params = new URLSearchParams(location.search);
const startStep = Math.max(0, Math.min(TOTAL - 1, parseInt(params.get("step") || "0", 10)));
goto(startStep);

if ("usb" in navigator) {
    navigator.usb.addEventListener("disconnect", e => {
        if (state.device && e.device === state.device._raw?.device?.device_) {
            appendLog("err", "# device disconnected");
            state.device = null;
            document.getElementById("connect-card")?.classList.remove("is-connected");
            document.getElementById("connect-label").textContent = "device disconnected";
            document.getElementById("connect-sub").textContent = "reconnect to retry";
            document.getElementById("connect-dot").classList.remove("live");
            document.getElementById("connect-dot").classList.add("pulsing");
            setConnPill("disconnected");
            refreshGates();
        }
    });
}
