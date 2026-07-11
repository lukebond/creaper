#!/usr/bin/env bash
# creaper-autolink: keep REAPER's input ports cabled to a chosen capture device.
#
# Opt-in and generic. Set CREAPER_INPUT_MATCH to a substring of your interface's
# PipeWire port name (e.g. "Scarlett", "Mustang", "UMC", "Babyface"). The watcher
# then keeps REAPER's inputs fed by that device, reacting to hotplug and REAPER
# restarts. By default it also removes any *other* links into REAPER's inputs
# (e.g. WirePlumber auto-cabling your default mic) — turn that off for setups
# that record several sources at once.
#
#   CREAPER_INPUT_MATCH       substring identifying the capture device (empty = do nothing)
#   CREAPER_INPUT_EXCLUSIVE   1 (default) remove non-matching links into REAPER inputs; 0 = additive
#   CREAPER_AUTOLINK_INTERVAL reconcile seconds (default 2)
#   CREAPER_AUTOLINK_ONCE     1 = single reconcile pass then exit (default: loop)
#
# All links are live/ephemeral graph edits — nothing is written to disk or to
# system audio config. Uses only pw-link against the current PipeWire session.
set -uo pipefail

MATCH="${CREAPER_INPUT_MATCH:-}"
EXCLUSIVE="${CREAPER_INPUT_EXCLUSIVE:-1}"
INTERVAL="${CREAPER_AUTOLINK_INTERVAL:-2}"
ONCE="${CREAPER_AUTOLINK_ONCE:-0}"

[ -z "$MATCH" ] && { echo "[autolink] CREAPER_INPUT_MATCH unset — not auto-linking"; exit 0; }
command -v pw-link >/dev/null || { echo "[autolink] pw-link not found"; exit 0; }

# Capture ports of the chosen device, sorted. Prefer ALSA 'capture' ports so a
# duplex interface's playback-monitor ports aren't mistaken for inputs.
device_ports() {
    local all
    all="$(pw-link -o 2>/dev/null | grep -iE "$MATCH" || true)"
    local cap; cap="$(grep -iE 'capture' <<<"$all" || true)"
    [ -n "$cap" ] && { sort -V <<<"$cap"; return; }
    [ -n "$all" ] && sort -V <<<"$all"
}

# "src dst" for every link currently feeding a REAPER input port.
reaper_input_links() {
    pw-link -l 2>/dev/null | awk '
        /^[^[:space:]]/ { d = $1 }
        (d ~ /^REAPER:in[0-9]+$/) && /\|<-/ { print $2, d }'
}

reconcile() {
    mapfile -t rin < <(pw-link -i 2>/dev/null | grep -E '^REAPER:in[0-9]+$' | sort -V)
    [ "${#rin[@]}" -eq 0 ] && return 0            # REAPER not up yet
    mapfile -t dev < <(device_ports)
    [ "${#dev[@]}" -eq 0 ] && return 0            # device not present — leave graph untouched

    # Add: pair device capture ports to REAPER inputs. pw-link is a no-op (nonzero,
    # silent) if the link already exists, so this only logs genuinely new links.
    local n=${#rin[@]}; [ "${#dev[@]}" -lt "$n" ] && n=${#dev[@]}
    local i
    for ((i = 0; i < n; i++)); do
        pw-link "${dev[i]}" "${rin[i]}" 2>/dev/null && echo "[autolink] linked ${dev[i]} -> ${rin[i]}"
    done

    # Exclusive: drop links into REAPER inputs from anything other than the device.
    if [ "$EXCLUSIVE" = "1" ]; then
        local src dst
        while read -r src dst; do
            [ -z "$src" ] && continue
            grep -qiE "$MATCH" <<<"$src" && continue
            pw-link -d "$src" "$dst" 2>/dev/null && echo "[autolink] removed stray $src -> $dst"
        done < <(reaper_input_links)
    fi
}

echo "[autolink] match='$MATCH' exclusive=$EXCLUSIVE interval=${INTERVAL}s once=$ONCE"
if [ "$ONCE" = "1" ]; then
    reconcile
else
    while true; do reconcile; sleep "$INTERVAL"; done
fi
