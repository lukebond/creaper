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

# creaper's home ON THE HOST: config, license, projects, recordings — all here,
# nothing hidden in a Docker volume. Override with CREAPER_HOME=/path ./run.sh
CREAPER_HOME="${CREAPER_HOME:-$HOME/reaper}"
mkdir -p "$CREAPER_HOME"

args=(
    --rm
    --name creaper
    -e WAYLAND_DISPLAY="${WAYLAND_DISPLAY}"
    -e XDG_RUNTIME_DIR=/run/user/1000
    -v "${RTD}/${WAYLAND_DISPLAY}:/run/user/1000/${WAYLAND_DISPLAY}"
    -v "${CREAPER_HOME}:/home/reaper"            # everything REAPER writes lands on the host
)

# Attach an interactive TTY only when run from a real terminal, so launching from
# a .desktop entry / app launcher (which has no TTY) works too.
[ -t 0 ] && [ -t 1 ] && args+=( -it )

# Audio: hand the host PipeWire socket in. REAPER auto-connects via pipewire-jack.
[ -S "${RTD}/pipewire-0" ] && args+=( -v "${RTD}/pipewire-0:/run/user/1000/pipewire-0" )

# Optional input auto-linking (see scripts/creaper-autolink.sh):
#   CREAPER_INPUT_MATCH=Mustang ./run.sh   → auto-cable that interface into REAPER
[ -n "${CREAPER_INPUT_MATCH:-}" ]     && args+=( -e CREAPER_INPUT_MATCH="${CREAPER_INPUT_MATCH}" )
[ -n "${CREAPER_INPUT_EXCLUSIVE:-}" ] && args+=( -e CREAPER_INPUT_EXCLUSIVE="${CREAPER_INPUT_EXCLUSIVE}" )

# GPU: optional, speeds up Xwayland/GL. Skipped if absent.
[ -d /dev/dri ] && args+=( --device /dev/dri )

# --- Low latency (opt-in): CREAPER_LOWLATENCY=1 ./run.sh -----------------------
# Buffer size is the real latency knob; realtime scheduling just makes a small
# buffer stable (prevents dropouts). This lowers REAPER's requested PipeWire
# quantum AND grants RT so it holds. Override the buffer with e.g.
# CREAPER_QUANTUM=256/48000 (bigger = safer, higher latency).
#
# Cost (why it's off by default): an RT-scheduled thread can starve the host if
# it misbehaves, and --cap-add is a small privilege increase. No benefit at the
# default buffer, so opt-in only.
if [ "${CREAPER_LOWLATENCY:-0}" = "1" ]; then
    args+=(
        --ulimit rtprio=95
        --cap-add SYS_NICE
        -e PIPEWIRE_LATENCY="${CREAPER_QUANTUM:-128/48000}"
    )
fi
# Raw ALSA (lowest latency, exclusive; needs freeing the device from PipeWire) is
# a future mode — see README.
# -------------------------------------------------------------------------------

exec docker run "${args[@]}" "${IMAGE}" "$@"
