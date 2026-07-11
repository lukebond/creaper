#!/usr/bin/env bash
# Connect a hardware capture device to REAPER's inputs in the PipeWire graph,
# and clear any stray auto-links (e.g. WirePlumber wiring your laptop mic into
# REAPER). Run this on the HOST after ./run.sh, with REAPER open and the
# interface plugged in.
#
#   ./scripts/link-input.sh            # defaults to a device matching "Mustang"
#   ./scripts/link-input.sh Scarlett   # match any device by name substring
#
# All links are live/ephemeral — they vanish when REAPER closes, the device is
# unplugged, or on reboot. Nothing is written to disk or to system audio config.
set -euo pipefail

MATCH="${1:-Mustang}"

command -v pw-link >/dev/null || { echo "pw-link not found (install pipewire)"; exit 1; }

# Find the device's stereo capture ports.
src_fl="$(pw-link -o | grep -i "$MATCH" | grep -i 'capture_FL' | head -1 || true)"
src_fr="$(pw-link -o | grep -i "$MATCH" | grep -i 'capture_FR' | head -1 || true)"

if [ -z "$src_fl" ]; then
    echo "No capture ports matching '$MATCH' found. Available capture ports:"
    pw-link -o
    exit 1
fi

# Drop whatever currently feeds REAPER's inputs (clears mic auto-links etc.).
for line in $(pw-link -l 2>/dev/null | awk '/^REAPER:in[12]/{p=$1} /\|<-/{print p"@@"$2}'); do
    dst="${line%%@@*}"; src="${line##*@@}"
    pw-link -d "$src" "$dst" 2>/dev/null && echo "unlinked $src -> $dst"
done

# Link the device to REAPER.
pw-link "$src_fl" "REAPER:in1" && echo "linked $src_fl -> REAPER:in1"
[ -n "$src_fr" ] && pw-link "$src_fr" "REAPER:in2" && echo "linked $src_fr -> REAPER:in2"

echo
echo "REAPER inputs now fed by:"
pw-link -l 2>/dev/null | awk '/^REAPER:in[12]/{print; getline; print}'
