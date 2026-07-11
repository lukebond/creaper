# creaper — containerised REAPER

**Containerised REAPER** for pure-Wayland hosts (e.g. [niri](https://github.com/YaLTeR/niri))
that don't have — and don't want — an X server installed.

REAPER's Linux GUI (Cockos SWELL) needs an X11 display. Rather than install
Xwayland on the host, creaper puts **everything X inside the container**:
Xwayland + [`xwayland-satellite`](https://github.com/Supreeeme/xwayland-satellite)
run in the image and bridge REAPER's windows out to the host Wayland compositor
as **native, per-window** surfaces. The host stays completely X-free.

```
 host compositor (pure Wayland)  ◄── wayland socket (mounted in) ──┐
 pipewire socket (mounted in)   ◄──────────────────────────────────┤
                                                          [ container, uid 1000 ]
                                                          xwayland-satellite → Xwayland
                                                          REAPER → windows appear on the host
                                                          REAPER audio ⇄ host PipeWire
```

## Why a container at all?

Honestly: mostly **host hygiene**. `xwayland-satellite` works fine installed
natively. The container's payoff is that your host package DB stays X-free and
X exists only as a disposable image you run on demand. It does *not* add
capability — it's a taste/reproducibility choice. (See the design notes at the
bottom.)

## Requirements

- A Wayland compositor. On niri, X apps need `xwayland-satellite` — which here
  lives in the container, so **niri needs nothing extra**.
- Docker (or Podman; see notes).
- PipeWire on the host (for audio).

## Build

```bash
docker build -t creaper:latest .
```

The container process must run as **the host user's uid** to connect to the
owner-only Wayland socket. It defaults to `1000`. If the target machine's login
user isn't uid 1000:

```bash
docker build -t creaper:latest --build-arg UID=$(id -u) .
```

## Run

```bash
./run.sh
```

REAPER opens as a native window on your compositor. `run.sh` mounts your
Wayland + PipeWire sockets in, persists REAPER config in a `creaper-home`
volume, and maps `~/reaper` on the host to the project/recording folder
(override with `CREAPER_PROJECTS=/path ./run.sh`).

## Audio

REAPER auto-selects the **JACK backend**, which reaches the host PipeWire via
`pipewire-jack` — output connects to your speakers automatically.

### Recording from a hardware interface

Inputs need wiring in the PipeWire graph. Plug the interface in, then on the
host:

```bash
./scripts/link-input.sh Mustang     # match your device by name substring
```

This connects the device's capture ports to `REAPER:in1/in2` and clears any
stray auto-links (WirePlumber tends to wire your default mic into REAPER). Then
in REAPER: **Ctrl+T** (new track) → click the round **record-arm** button
(turns red) → right-click it → **Input → Stereo → 1/2** → right-click →
**Monitoring → On** → play and watch the track meter → press **Record**.

All `pw-link` connections are ephemeral — they vanish on close/unplug/reboot and
never touch host audio config.

### Latency

Default is PipeWire's quantum (≈21 ms at 1024/48k) — fine for mixing, high for
tracking. To go lower, uncomment the realtime opt-ins in `run.sh`
(`--ulimit rtprio=95 --cap-add SYS_NICE`) and lower the PipeWire quantum. For
absolute lowest latency you can switch REAPER to **raw ALSA** (uncomment
`--device /dev/snd`), but on a PipeWire host that means prying the interface
away from PipeWire — only worth it with a dedicated interface. See the audio
discussion in the design notes.

## Portability to another machine

- Rebuild with `--build-arg UID=$(id -u)` if that host's user isn't uid 1000.
- `WAYLAND_DISPLAY` differs per session (here it's `wayland-1`); `run.sh` reads
  it from the environment.
- Device port names in `link-input.sh` differ per interface — pass a matching
  substring.

## Known limitations

- **Floating window placement:** `xwayland-satellite` doesn't give X apps a true
  global coordinate space, so REAPER's remembered floating FX/plugin window
  positions may not land exactly. Everything else integrates cleanly.
- Recordings live under `~/reaper` on the host (bind-mounted); REAPER
  config/license live in the `creaper-home` Docker volume.

## podman vs docker

Either works; the image is identical OCI. The one real constraint is that the
container process must present as the host uid to reach the Wayland socket —
Docker handles this via the baked `uid 1000` user (or `--build-arg UID`), Podman
via rootless `--userns=keep-id`. Docker is the default here simply because it was
already installed. Podman is a drop-in with a smaller (daemonless, rootless)
footprint if you prefer it.
