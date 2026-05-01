#!/usr/bin/env bash
# catch_fastboot.sh — race-catch the Rabbit R1 in MTK BROM/Preloader and
# drive it into Google fastboot mode. Replaces the unreliable web-flasher
# click flow when the BROM window is shorter than human reaction time.
#
# Prereq: mtkclient installed at ~/mtkclient with deps installed.
#   git clone --depth=1 https://github.com/bkerler/mtkclient.git ~/mtkclient
#   cd ~/mtkclient && pip3 install --user -r requirements.txt --break-system-packages
#
# How to use:
#   1. Run this script.
#   2. Power off the R1 fully (screen black, no boot logo).
#   3. Unplug USB.
#   4. Press and hold the scroll-wheel button (or talk button if scroll fails).
#   5. While holding, plug USB. Keep holding ~5s.
#   6. Script catches BROM/Preloader within 50 ms and drives to fastboot.

set -u

MTK_DIR="${MTK_DIR:-$HOME/mtkclient}"
MTK_PY="$MTK_DIR/mtk.py"

if [[ ! -f "$MTK_PY" ]]; then
    echo "ERROR: mtkclient not found at $MTK_PY"
    echo "Install with:"
    echo "  git clone --depth=1 https://github.com/bkerler/mtkclient.git ~/mtkclient"
    echo "  cd ~/mtkclient && pip3 install --user -r requirements.txt --break-system-packages"
    exit 1
fi

# ModemManager occasionally claims MTK BROM USB endpoints and corrupts the
# session. We don't auto-stop it (needs sudo) — just warn if it's running.
if systemctl is-active --quiet ModemManager 2>/dev/null; then
    echo "WARN: ModemManager is running — it may grab BROM endpoints."
    echo "If catch fails repeatedly, stop it: sudo systemctl stop ModemManager"
    echo
fi

cat <<'EOF'
================================================================
  R1 BROM/Preloader → fastboot catcher
================================================================
  1. Power OFF the R1 completely (screen fully black, 5s+).
  2. Unplug USB.
  3. Press and HOLD the scroll-wheel button (push it inward).
  4. While HOLDING, plug USB.
  5. Keep holding for ~5 seconds.

  Watching USB at 50 ms intervals for 120 s...
EOF

# Tight poll loop. 50ms interval = 20 checks/sec; well under human reaction.
caught_id=""
deadline=$(( $(date +%s) + 120 ))
while [[ $(date +%s) -lt $deadline ]]; do
    # Match exact pid:vid pairs to avoid grabbing a partly-booted RabbitOS (2304)
    line=$(lsusb 2>/dev/null | grep -E "ID 0e8d:(0003|2000) " | head -1)
    if [[ -n "$line" ]]; then
        caught_id=$(echo "$line" | grep -oE "0e8d:(0003|2000)")
        echo
        echo "Caught: $line"
        echo "Mode: $caught_id ($([ "$caught_id" = "0e8d:0003" ] && echo BROM || echo Preloader))"
        break
    fi
    sleep 0.05
done

if [[ -z "$caught_id" ]]; then
    echo
    echo "TIMED OUT after 120 s — device never entered BROM/Preloader."
    echo "Try a different button (talk button instead of scroll wheel),"
    echo "or hold longer / make sure the device was fully powered off first."
    exit 1
fi

echo
echo "==> Driving device to fastboot via mtkclient..."
cd "$MTK_DIR"

# `meta FASTBOOT` is the canonical command (mtkclient 2.x). Fall back to
# `payload --metamode FASTBOOT` if older.
if python3 mtk.py meta FASTBOOT 2>&1 | tee /tmp/mtk_payload.log; then
    echo "meta FASTBOOT OK."
elif python3 mtk.py payload --metamode FASTBOOT 2>&1 | tee -a /tmp/mtk_payload.log; then
    echo "payload --metamode FASTBOOT OK."
else
    echo
    echo "ERROR: mtkclient failed. Log: /tmp/mtk_payload.log"
    echo "Try manually:"
    echo "  cd $MTK_DIR && python3 mtk.py meta FASTBOOT"
    exit 1
fi

echo
echo "==> Waiting up to 60 s for Google fastboot (vendor 18d1)..."
deadline=$(( $(date +%s) + 60 ))
while [[ $(date +%s) -lt $deadline ]]; do
    if fastboot devices 2>/dev/null | grep -q "fastboot$"; then
        echo
        echo "================================================================"
        echo "  Fastboot ready:"
        fastboot devices
        echo "================================================================"
        echo
        echo "Now flash CarrotOS:"
        echo "  cd ~/Desktop/cipherOsCustom/release/carrotos-v1.0.1 && ./flash.sh"
        exit 0
    fi
    sleep 0.3
done

echo
echo "Fastboot never appeared. Current USB state:"
lsusb | grep -iE "0e8d|18d1|2717|google|mediatek|rabbit"
echo
echo "If you see 0e8d:* still, mtkclient didn't fully drive the bootmode switch."
echo "Re-run this script, or fall back to the web flasher."
exit 1
