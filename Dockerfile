# creaper — containerised REAPER for pure-Wayland hosts (e.g. niri).
# All X lives in here; the host stays X-free. REAPER windows reach the host
# compositor via xwayland-satellite (rootless Xwayland, no compositor support needed).

FROM archlinux:latest

# Everything we need is in the official Arch repos — no AUR, no source builds.
#   xorg-xwayland      : the X server (driven by satellite, never by the host)
#   xwayland-satellite : rootless Xwayland bridge → REAPER shows as real niri windows
#   reaper             : the DAW itself
#   pipewire-jack      : lets REAPER's JACK backend talk to the host PipeWire socket
#   mesa / ttf-dejavu  : software GL + fonts so the UI renders
RUN pacman -Syu --noconfirm --needed archlinux-keyring && \
    pacman -S   --noconfirm --needed \
        xorg-xwayland \
        xwayland-satellite \
        reaper \
        gtk3 \
        pipewire pipewire-jack \
        alsa-lib \
        mesa \
        ttf-dejavu && \
    pacman -Scc --noconfirm

# Xwayland runs as non-root and can't create this itself; pre-create it so the
# X socket lands on the filesystem (not just an abstract socket) without a stall.
RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# Match the host login uid so we can connect to the owner-only Wayland socket.
# (Single-user Linux hosts are almost always uid 1000; override at build time
#  with --build-arg UID=... if the target machine differs.)
ARG UID=1000
RUN useradd -u "${UID}" -m -s /bin/bash reaper && \
    mkdir -p "/run/user/${UID}" && \
    chown "${UID}:${UID}" "/run/user/${UID}" && \
    chmod 700 "/run/user/${UID}"

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER ${UID}
ENV XDG_RUNTIME_DIR=/run/user/1000 \
    HOME=/home/reaper \
    DISPLAY_NUM=:12

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
