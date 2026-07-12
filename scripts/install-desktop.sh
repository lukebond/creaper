#!/usr/bin/env bash
# Install a .desktop entry so creaper's REAPER appears in your Wayland app
# launcher (fuzzel / rofi / wofi / niri's mod-d). Any CREAPER_* env vars set
# when you run this are baked into the launcher entry, e.g.:
#
#   CREAPER_INPUT_MATCH=Mustang CREAPER_LOWLATENCY=1 ./scripts/install-desktop.sh
#
# Uninstall: rm ~/.local/share/applications/creaper.desktop
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$REPO/run.sh"
IMAGE="${CREAPER_IMAGE:-creaper:latest}"
[ -x "$RUN" ] || { echo "run.sh not found/executable at $RUN" >&2; exit 1; }

DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APPS="$DATA/applications"
ICONDIR="$DATA/icons/hicolor/256x256/apps"
mkdir -p "$APPS" "$ICONDIR"

# Pull REAPER's own icon out of the image (best-effort; falls back to a stock name).
ICON="audio-x-generic"
if docker image inspect "$IMAGE" >/dev/null 2>&1 &&
   docker run --rm --entrypoint cat "$IMAGE" \
       /usr/share/icons/hicolor/256x256/apps/cockos-reaper.png > "$ICONDIR/creaper.png" 2>/dev/null &&
   [ -s "$ICONDIR/creaper.png" ]; then
    ICON="creaper"
else
    rm -f "$ICONDIR/creaper.png"
fi

# Bake in whichever creaper options are set in the environment at install time.
envline=""
for v in CREAPER_IMAGE CREAPER_HOME CREAPER_INPUT_MATCH CREAPER_INPUT_EXCLUSIVE \
         CREAPER_LOWLATENCY CREAPER_QUANTUM; do
    [ -n "${!v:-}" ] && envline+=" $v=${!v}"
done
exec_cmd="$RUN"
[ -n "$envline" ] && exec_cmd="env$envline $RUN"

desktop="$APPS/creaper.desktop"
cat > "$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=REAPER (creaper)
Comment=Containerised REAPER — pure-Wayland, no host X
Exec=$exec_cmd
Icon=$ICON
Terminal=false
Categories=AudioVideo;Audio;AudioVideoEditing;Recorder;
StartupNotify=false
StartupWMClass=REAPER
EOF

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" 2>/dev/null || true

echo "installed: $desktop"
echo "  Exec=$exec_cmd"
echo "  Icon=$ICON"
echo "Search 'REAPER' in your launcher (fuzzel / rofi / wofi / mod-d)."
