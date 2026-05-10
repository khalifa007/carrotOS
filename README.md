# CarrotOS Flasher

A static-site web flasher for the **Rabbit R1**. Walks users through flashing
[CarrotOS](https://github.com/khalifa007/carrotOS) — a custom LineageOS 21 GSI (Android 14)
with the R1Launcher home app baked in — directly from a Chromium-based browser
over WebUSB. No installs, no telemetry, no upload.

## At your own risk

Flashing is at your own risk. CarrotOS and this flasher are community work — if your
R1 bricks, won't boot, or loses cellular after flashing, we can't recover it for you.
Unlocking the bootloader also voids the Rabbit warranty (Rabbit support will not help
you re-lock or recover). Proceed only if you accept that.

## How to use

1. Open `index.html` in Chrome / Edge / Brave (or visit the GitHub Pages URL once deployed).
2. **Step 01** — drop in `system.img`, optionally `vbmeta.img`, optionally `vendor.img`.
3. **Step 02** — get the R1 into fastboot, then click "Authorize R1 over WebUSB".
4. **Step 03** — pick options (wipe userdata, flash vbmeta, etc.) and review the plan.
5. **Step 04** — watch the bars + log; don't unplug.
6. **Step 05** — wait for boot; troubleshooting tips inside.

## Stack

- Vanilla HTML / CSS / ES modules. No build step.
- [`kdrag0n/fastboot.js`](https://github.com/kdrag0n/fastboot.js) vendored at `lib/fastboot.mjs`.
- Web fonts: Fraunces (display) + JetBrains Mono (everything else).

## Browser support

WebUSB is Chromium-only. Firefox and Safari can browse the page but the connect
button is disabled — a banner explains this on load.

## Stuck devices

`scripts/catch_fastboot.sh` is a Linux/macOS helper for racing the MediaTek BROM
window to drive a stuck R1 into Google fastboot via mtkclient. Step 02 has a
download link and copy-paste instructions. The page does *not* try to port mtkclient
to JS — for users without a Linux/macOS box, it links out to
[`rabbit-hmi-oss.github.io/flashing/`](https://rabbit-hmi-oss.github.io/flashing/)
for the BROM hop only.

## Deploying to GitHub Pages

```bash
# In a fresh repo:
git init
git add .
git commit -m "init: carrotFlasher v1"
git remote add origin https://github.com/<you>/carrot-flasher.git
git push -u origin main
# Then in repo settings → Pages → branch: main, dir: /
```

The `.nojekyll` file in the repo root tells Pages to serve files starting
with underscore unmodified (not actually used here, but standard practice).

## Layout

```
carrotFlasher/
├── index.html              single page, all 6 steps
├── style.css               carrot-orange + paper-cream service-manual look
├── app.js                  state, stepper, file pickers, plan rendering
├── flasher.js              fastboot.js wrapper, log bus, partition sequence
├── lib/fastboot.mjs        kdrag0n/fastboot.js v1.1.1 (vendored, ~143 KB)
├── assets/favicon.svg
├── scripts/catch_fastboot.sh   downloadable Linux/macOS BROM helper
├── .nojekyll
└── README.md
```

## Roadmap (post-v1)

- **v1.1** — auto-fetch latest release imgs from GitHub Releases API
- **v1.2** — service worker for offline caching (handles flaky USB / refresh mid-flash)
- **v1.3** — WebUSB-based vendor/system image inspection (verify version before flashing)

## License

MIT. `lib/fastboot.mjs` is MIT-licensed by kdrag0n.
