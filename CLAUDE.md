# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this directory is

A **static-site WebUSB flasher** for the **Rabbit R1**. Walks users through flashing **CarrotOS** — a custom LineageOS 21 GSI (Android 14) with the R1Launcher home app baked in — directly from a Chromium-based browser. No installs, no upload, no telemetry; everything runs locally in the user's browser.

- **Live URL:** https://khalifa007.github.io/carrotOS/
- **Deployed via:** GitHub Pages, `gh-pages` branch of `khalifa007/carrotOS` (the same repo whose `main` branch holds the user-facing README pointing to Releases). Pages serves the branch root at `/`.
- **Sister projects** (sit alongside this one in `~/Desktop/`):
  - `~/Desktop/rabbitR1Luncher/` — the launcher app this flasher ships. **Design language is copied from there** — same fonts (`jersey_15.ttf` + `tajawal_bold.ttf`), palette, lowercase Jersey 15, single accent `#FF6A00`, scanlines + grain CRT atmosphere.
  - `~/Desktop/cipherOsCustom/` — the build harness that produces the `system.img` / `vbmeta.img` / `vendor.img` users drop into this flasher. Locally it is the clone of `khalifa007/carrotOS` (its `main` branch), so `git push` from there pushes to the same repo this flasher lives on as `gh-pages`.

## Stack

- Vanilla HTML / CSS / ES modules. **No build step.** Just static files served over HTTP/HTTPS.
- [`kdrag0n/fastboot.js`](https://github.com/kdrag0n/fastboot.js) v1.1.1 vendored at `lib/fastboot.mjs`. Updated by re-fetching from `https://cdn.jsdelivr.net/npm/android-fastboot@<ver>/dist/fastboot.min.mjs`.
- Fonts hosted **locally** in `assets/` (copied from `rabbitR1Luncher/app/src/main/assets/web/`) — no Google Fonts dep so the page works offline once cached.

## File layout

```
carrotFlasher/
├── index.html              single page · 6 step sections · all DOM
├── style.css               full design system mirroring the launcher
├── app.js                  step machine, file pickers, plan rendering, USB events
├── flasher.js              fastboot.js wrapper, log bus, mode routing
├── lib/fastboot.mjs        vendored fastboot.js
├── assets/
│   ├── jersey_15.ttf       launcher's display font (latin)
│   ├── tajawal_bold.ttf    launcher's display font (arabic)
│   └── favicon.svg         carrot mark
├── scripts/catch_fastboot.sh  downloadable Linux/macOS BROM helper
├── .nojekyll               disable Jekyll on Pages so /lib serves
├── README.md               user-facing "how to run / deploy"
└── CLAUDE.md               this file
```

## Step machine (the 6 sections in index.html)

1. **00 hello** — pitch + `before you start · unlock the r1 bootloader` callout. The unlock procedure (rabbithole → developer mode → device modification → unlock → rabbit-hmi-oss flash tool) lives here because shipped R1s are locked and trying to flash without unlocking yields opaque USB errors. Voids warranty — surfaced clearly.
2. **01 images** — three dropzones: `system.img` / `vbmeta.img` / `vendor.img`. **All three are required.** Continue button is gated on all three dropping. SHA-256 computed locally via `crypto.subtle`.
3. **02 connect** — two path cards (device boots / stuck on stock) + the WebUSB authorize button. catch_fastboot.sh download lives here.
4. **03 configure** — toggles for vbmeta/vendor/wipe/reboot + a live `flash plan` mono panel that reflects the current selection.
5. **04 flash** — per-partition progress bars + dark live log pane (mono).
6. **05 done** — success/failure summary + collapsible troubleshooting list.

URL routing: `?step=N` jumps directly to step N. Useful for headless screenshotting and direct-linking from the README.

## Design language (copied wholesale from rabbitR1Luncher)

The user explicitly asked for visual parity with the launcher. **Don't drift back to maximalist / Fraunces / cream-paper aesthetics.** The look is:

- Dark canvas `#0A0A0C`, single accent `#FF6A00`, tile bg `#1C1C1E`
- **Jersey 15 everywhere** for display (lowercase, letter-spacing 0.4–1.5px). Tajawal Bold as the Arabic-glyph fallback. JetBrains-Mono-class system mono only for code blocks and the live log pane.
- Tile cards with a 14-px corner crosshair on the top-right (matches the launcher's `app-tile::before`)
- Chunky orange primary buttons with a black 4-px box-shadow underneath (`0 4px 0 0 #b34900`) — they "press down" on click
- Switch toggles: pill rail + circle knob, exact same geometry as `.switch` in `rabbitR1Luncher/app/src/main/assets/web/style.css`
- Background atmosphere: `.scanlines` (CSS-only repeating-linear-gradient) + `.grain` (radial-gradient noise) overlays
- All copy lowercased. No italics. No serifs. No corner ticks beyond the tile-corner crosshair.

If a future change feels like it needs a serif or a sentence-case heading, that's a sign it's diverging from the launcher — push back or copy the exact CSS pattern from `rabbitR1Luncher/.../style.css`.

## flasher.js architecture

`runFlash(deviceWrap, parts, opts)` is the entry point. `parts` is an array of `{ name, action, file? }` objects. Internally:

- **`LOGICAL_PARTS`** = `system, vendor, product, system_ext, odm` — only flashable from **fastbootd** (Android-userspace fastboot).
- **`PHYSICAL_PARTS`** = `vbmeta, vbmeta_system, boot, dtbo, userdata, metadata` — only flashable from **bootloader fastboot**.
- `modeForPartition(p)` → "fastbootd" | "bootloader" | null.
- The queue is **reordered** so all bootloader-mode work happens first, minimizing `bootloader↔fastbootd` round-trips. Same-class items keep caller order.
- `ensureMode(dev, want)` runs at the start of every step and reboots if the current mode is wrong. `getMode()` reads `is-userspace` (`yes`=fastbootd, `no`=bootloader).
- The reboot+wait is wrapped in `withTimeout(..., 25_000, ...)`. **WebUSB across a USB re-enumeration is fragile** — `dev.reboot(target, true)` can hang forever if the re-enumerated device's endpoint layout changes. The 25 s timeout lets us throw a clear error ("close this tab fully, reconnect, resume") instead of a frozen page.
- Errors get hint-classified and emitted as `note` log lines — see "Known WebUSB failure modes" below.

`connectDevice()` keeps a module-scoped `_liveDevice` and tries to close the previous handle before opening a new one. Without this, a second `connect()` throws `"an operation that changes the device state is in progress"` because Chrome won't let two FastbootDevice instances claim the same USB device.

## Known WebUSB failure modes (and how the flasher surfaces them)

| Error string | Cause | What flasher does |
|---|---|---|
| `transferIn` / `transferOut` / `stall` / `babble` | **ModemManager on Linux** probing the USB endpoint with AT commands mid-transfer | Log hint: `sudo systemctl stop ModemManager`; also suggests cable / no-hub. Step 05 troubleshooting echoes this. |
| `operation that changes the device state is in progress` | Stale WebUSB handle from a previous failed connect/flash | Hint: fully close the tab + replug. The `_liveDevice.close()` retry in `connectDevice()` makes this self-heal in most cases. |
| `FAIL This partition doesn't exist` | Wrong fastboot mode for the partition class | Hint: bootloader vs fastbootd explanation. Auto-fixed by `ensureMode()` going forward. |
| `Device is locked` | Bootloader still locked (rabbithole unlock not done) | Hint pointing back to step 00's `before you start` section. |
| `webusb requires https or http://localhost` | User opened `index.html` via `file://` (not a secure context) | Banner explains: `python3 -m http.server 8765` then `http://127.0.0.1:8765`. |
| Reboot timeout after 25 s | Mode-switch reboot succeeded but JS-side `waitForConnect()` lost the re-enumerated device | Throws with "close tab, reconnect, resume" message. User can retry from step 03 with the partitions that match the device's new mode. |

When something goes wrong and the user is on step 05 in failed state, the in-page troubleshooting `<details>` covers the same hits. Keep these two surfaces in sync — `flasher.js` regex + `index.html` `.trouble ul`.

## Deploying updates

```bash
# from anywhere, this is one-shot:
DEPLOY=/tmp/carrot-pages-deploy
rm -rf "$DEPLOY" && mkdir -p "$DEPLOY"
cp -a ~/Desktop/carrotFlasher/. "$DEPLOY"/
cd "$DEPLOY"
git init -q -b gh-pages
git add .
git -c user.email=noreply@khalifa007.dev -c user.name=khalifa007 commit -q -m "deploy: <what changed>"
git remote add origin https://github.com/khalifa007/carrotOS.git
git push -q -u --force origin gh-pages
# Pages picks up the push and rebuilds in ~5-10s; verify:
gh api repos/khalifa007/carrotOS/pages --jq '.status'   # → "built" when done
```

`--force` is fine because `gh-pages` is a deploy artifact branch; we never merge from it. The `main` branch is independent (user-facing README only).

To verify a deploy without opening a browser:
```bash
for p in "" style.css app.js flasher.js lib/fastboot.mjs assets/jersey_15.ttf; do
  curl -s -o /dev/null -w "HTTP %{http_code} /$p\n" "https://khalifa007.github.io/carrotOS/$p"
done
```

## Local development

```bash
cd ~/Desktop/carrotFlasher && python3 -m http.server 8765
# open http://127.0.0.1:8765 in Chrome
```

**Don't open `index.html` directly via `file://` — WebUSB is gated to secure contexts** (HTTPS or `localhost`/`127.0.0.1`). The flasher's `gateBrowser()` detects this and shows an explicit banner with the python-server one-liner.

For headless screenshotting (e.g. updating README screenshots):
```bash
google-chrome --headless --disable-gpu --no-sandbox --hide-scrollbars \
  --window-size=1280,900 --virtual-time-budget=4000 \
  --screenshot=/tmp/step.png "http://127.0.0.1:8765/?step=3"
```
The `--virtual-time-budget` is **required** — without it the screenshot fires before web fonts load and you get fallback-font ghosting. 3500–4000 ms covers Jersey 15 + Tajawal cold-load.

## Don't drift

- **Don't switch fonts.** Jersey 15 + Tajawal are vendored on purpose so the page works offline and looks identical to the launcher. Don't replace with Inter/Fraunces/system fonts even if a screenshot looks "more modern" — the user explicitly rejected that direction.
- **Don't add framework dependencies.** No React, no bundler, no PostCSS. The whole point is "drop on any static host, done." If something needs a build step, it goes in v2 with a clear separation.
- **Don't lose the secure-context gate.** WebUSB on `file://` silently fails — the explicit banner saves users from confusing "my browser is broken" debugging.
- **Don't trust fastboot.js's `waitForConnect` past 25 s.** Mode-switch reboots that hang past that point won't recover; surface the timeout, don't retry-forever.
- **Don't make `vbmeta.img` or `vendor.img` optional.** Stock-RabbitOS users (the majority) will boot-loop without vbmeta flags=3, and will cellular-crashloop on wipe without the patched vendor. The conversation that arrived at this had multiple retries — re-relaxing these gates re-creates that pain.
- **Don't try to port mtkclient to JS.** The `catch_fastboot.sh` Linux/macOS helper covers the BROM→fastboot hop for stuck devices; users without a Unix box go through `rabbit-hmi-oss.github.io/flashing/` for that step. Reimplementing thousands of lines of MediaTek BROM/DA protocol in the browser is weeks of work for marginal payoff.

## Roadmap

- **v1.1** — auto-fetch latest release imgs from the GitHub Releases API, so users don't have to download imgs manually before dropping them.
- **v1.2** — service worker for offline caching of selected imgs (handles flaky USB / browser refresh mid-flash without re-uploading).
- **v1.3** — pre-flash version inspector that reads ROM metadata from the user-selected `system.img` and warns if it doesn't match the device's current state.
- **v2** — opt-in build pipeline (Vite or esbuild) only if vendoring + tree-shaking fastboot.js becomes a significant size win, or if we add features that genuinely need TypeScript / module aliasing.
