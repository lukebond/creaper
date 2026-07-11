#!/usr/bin/env bash
# Launch creaper: REAPER in a container, rendering to your Wayland compositor
# via xwayland-satellite. No X is installed on the host.
#
# Mounts in: the host Wayland socket (for display) and PipeWire socket (for audio).
# Windows come out as native windows on your compositor.
set -euo pipefail

WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
RTD="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
IMAGE="${CREAPER_IMAGE:-creaper:latest}"

# Where REAPER projects/recordings land ON THE HOST (so they're not trapped in
# the container). Override with CREAPER_PROJECTS=/path ./run.sh
PROJECTS="${CREAPER_PROJECTS:-$HOME/reaper}"
mkdir -p "$PROJECTS"

args=(
    --rm -it
    --name creaper
    -e WAYLAND_DISPLAY="${WAYLAND_DISPLAY}"
    -e XDG_RUNTIME_DIR=/run/user/1000
    -v "${RTD}/${WAYLAND_DISPLAY}:/run/user/1000/${WAYLAND_DISPLAY}"
    -v creaper-home:/home/reaper                 # REAPER config/prefs/license
    -v "${PROJECTS}:/home/reaper/projects"       # your projects/recordings, on the host
)

# Audio: hand the host PipeWire socket in. REAPER auto-connects via pipewire-jack.
[ -S "${RTD}/pipewire-0" ] && args+=( -v "${RTD}/pipewire-0:/run/user/1000/pipewire-0" )

# GPU: optional, speeds up Xwayland/GL. Skipped if absent.
[ -d /dev/dri ] && args+=( --device /dev/dri )

# --- Low-latency opt-ins (uncomment when you want to push the buffer down) ------
# Realtime scheduling for JACK/PipeWire (Docker blocks RT by default):
#   args+=( --ulimit rtprio=95 --cap-add SYS_NICE )
# Raw ALSA instead of PipeWire (lowest latency, exclusive device access — the
# host's PipeWire must NOT be holding the interface):
#   args+=( --device /dev/snd )
# -------------------------------------------------------------------------------

exec docker run "${args[@]}" "${IMAGE}" "$@"
