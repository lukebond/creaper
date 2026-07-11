#!/bin/bash
# Start the rootless Xwayland bridge, then hand off to REAPER on that display.
set -euo pipefail

: "${WAYLAND_DISPLAY:?WAYLAND_DISPLAY must be set (mount the host socket + pass -e)}"
: "${DISPLAY_NUM:=:12}"

echo "[creaper] bridging X ${DISPLAY_NUM} -> Wayland ${WAYLAND_DISPLAY} via xwayland-satellite"
xwayland-satellite "${DISPLAY_NUM}" &
sat_pid=$!

# Wait for Xwayland's socket to come up (satellite launches it lazily).
xsock="/tmp/.X11-unix/X${DISPLAY_NUM#:}"
for _ in $(seq 1 100); do
    [ -S "${xsock}" ] && break
    if ! kill -0 "${sat_pid}" 2>/dev/null; then
        echo "[creaper] xwayland-satellite exited before the X socket appeared" >&2
        wait "${sat_pid}" || true
        exit 1
    fi
    sleep 0.1
done

export DISPLAY="${DISPLAY_NUM}"
echo "[creaper] launching REAPER on DISPLAY=${DISPLAY}"
exec reaper "$@"
