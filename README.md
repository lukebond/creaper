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
Wayland + PipeWire sockets in and bind-mounts `~/reaper` on the host as the
container's home — so **everything REAPER writes** (config, license, projects,
recordings) lives under `~/reaper`, nothing hidden in a Docker volume. Override
the location with `CREAPER_HOME=/path ./run.sh`.

By default REAPER saves new projects under `~/reaper/Documents/REAPER Media/`;
set a different default in REAPER's Preferences → General → Paths if you'd rather
projects land straight in `~/reaper`.

## App launcher (.desktop)

To launch creaper from your Wayland app launcher (fuzzel / rofi / wofi / niri's
mod-d) instead of a terminal:

```bash
./scripts/install-desktop.sh
```

This installs `~/.local/share/applications/creaper.desktop` and REAPER's icon.
Any `CREAPER_*` options set when you run the installer are baked into the entry:

```bash
CREAPER_INPUT_MATCH=Mustang CREAPER_LOWLATENCY=1 ./scripts/install-desktop.sh
```

Uninstall with `rm ~/.local/share/applications/creaper.desktop`. (`run.sh`
attaches a terminal only when run from one, so it works both from a shell and
from a no-TTY launcher.)

## Audio

REAPER auto-selects the **JACK backend**, which reaches the host PipeWire via
`pipewire-jack` — output connects to your speakers automatically.

### Recording from a hardware interface

REAPER's inputs need to be cabled to your interface in the PipeWire graph
(WirePlumber otherwise tends to wire your *default mic* into REAPER instead).
Two ways:

**Automatic (recommended).** Name your interface and creaper keeps REAPER's
inputs cabled to it for the whole session — surviving hotplug and restarts:

```bash
CREAPER_INPUT_MATCH=Mustang ./run.sh      # substring of your device's name
```

A watcher (`scripts/creaper-autolink.sh`) bundled in the image links the device
to `REAPER:in1/in2` and removes any other links into REAPER's inputs. Options:
- `CREAPER_INPUT_MATCH` — substring identifying the device (opt-in; unset = off).
- `CREAPER_INPUT_EXCLUSIVE=0` — additive mode: keep other input links too (for
  recording several sources at once). Default `1` (exclusive).

**Manual, one-shot.** Or wire it once by hand after launch:

```bash
./scripts/link-input.sh Mustang
```

Then in REAPER: **Ctrl+T** (new track) → click the round **record-arm** button
(turns red) → right-click it → **Input → Stereo → 1/2** → right-click →
**Monitoring → On** → play and watch the track meter → press **Record**.

All `pw-link` connections are ephemeral — they vanish on close/unplug/reboot and
never touch host audio config.

### Latency

Default is PipeWire's quantum (≈21 ms at 1024/48k) — fine for mixing, high for
tracking. For lower latency:

```bash
CREAPER_LOWLATENCY=1 ./run.sh                       # ~128-sample buffer + realtime
CREAPER_LOWLATENCY=1 CREAPER_QUANTUM=256/48000 ./run.sh   # safer/higher if 128 glitches
```

Buffer size is the actual latency knob; the realtime flags
(`--ulimit rtprio=95 --cap-add SYS_NICE`) don't lower latency themselves — they
keep a *small* buffer from dropping out. **Cost:** an RT thread can starve the
host if it misbehaves, plus a small privilege bump — hence opt-in.

**How to tell it worked:** REAPER's title bar shows the live buffer and latency,
e.g. `… 1024spls ~21.3/21.3ms JACK`. With the flag it should drop to roughly
`… 128spls ~2.7/2.7ms`. Watch that number, and listen for clicks/dropouts (that's
what the RT flag prevents) — especially under load. On the host, `pw-top` shows
the quantum and an xrun/ERR counter per node for an objective stability check.

For *absolute* lowest latency you'd switch REAPER to **raw ALSA**, but on a
PipeWire host that means first prying the interface away from PipeWire
(`wpctl set-profile <id> 0`, restore on exit) — a heavier, exclusive mode not yet
implemented.

## Plugins

REAPER *discovers* plugins by scanning folders — it doesn't install them itself.
creaper keeps the **base image plugin-free**; plugin sets are opt-in image
variants layered on top (so non-users carry no bloat).

### Native-Linux plugin sets (addons)

```bash
./scripts/build.sh guitar            # base + guitar -> creaper:guitar
CREAPER_IMAGE=creaper:guitar ./run.sh
```

The guitar addon (`addons/guitar.Dockerfile`) installs — via pacman + the OSAMC
[pro-audio binary repo](https://github.com/osam-cologne/archlinux-proaudio), no
AUR build step — GxPlugins, Guitarix, Dragonfly Reverb, LSP (incl. its Impulse
cab loader), **Neural Amp Modeler (NAM)**, and **Ratatouille**. All free/open
source; they land in system scan dirs REAPER scans. REAPER 7 hosts **VST2, VST3,
CLAP, and LV2**, so all of the above load natively.

> **Can't find a plugin in the FX browser?** Enable **"always search all FX when
> using the search field"** (options in the FX-add window). By default the search
> is scoped to the selected folder, so plugins in other categories (LV2, CLAP, …)
> won't show up until you turn this on.

Add your own set as `addons/<name>.Dockerfile` (`FROM ${BASE}`); addons stack:
`./scripts/build.sh guitar windows`.

### Amp models + cabinet IRs (the *data*)

The amp sims do nothing without capture/IR files. Grab a free starter set into
`~/reaper/tones` (persisted on the host):

```bash
./scripts/fetch-tones.sh
```

Then browse to `~/reaper/tones/nam` in NAM/Ratatouille and `~/reaper/tones/ir` in
the LSP Impulse loader — these formats have no auto-scan folder, you load them by
hand.

### Proprietary / downloaded plugins (e.g. Audio Assault Amp Locker)

Proprietary freeware and other vendor downloads can't be baked into the image
(licensing), and their download URLs are version-pinned and change over time — so
automating them just rots (the AUR `amp-locker-*-bin` packages break on every
version bump for exactly this reason). Instead, drop them into `~/reaper` by hand,
once — it's the container's home, so they persist across rebuilds.

**Example — Audio Assault Amp Locker** (free amp-sim hub):

1. Download the current **Linux** build from
   <https://audioassault.mx/downloadAudioAssault>. The version and URL change, so
   just take whatever Linux zip is offered — don't hardcode it anywhere.
2. Unzip it and copy the **`.vst3`** bundle into `~/reaper/.vst3/`:
   ```bash
   mkdir -p ~/reaper/.vst3
   cp -r /path/to/unzipped/AmpLocker.vst3 ~/reaper/.vst3/
   ```
   Amp Locker also ships an **`AmpLockerData`** folder (its amps, cabs, IRs,
   presets) — the plugin is empty without it. Per its `How To Install.txt`, copy
   the folder's *contents* into the path it expects:
   ```bash
   D="$HOME/reaper/Audio Assault/PluginData/Audio Assault/AmpLockerData"
   mkdir -p "$D" && cp -a /path/to/unzipped/AmpLockerData/. "$D/"
   ```
   The plugin looks under `~/Audio Assault/…`; since the container's home *is*
   `~/reaper`, that resolves correctly. (The zip is Mac-made — ignore the
   `__MACOSX/` and `.DS_Store` junk.)
3. In REAPER: **Preferences → Plug-ins → VST → Re-scan** (or restart REAPER).
   Amp Locker then appears in the FX browser — remember to enable **"always
   search all FX"** if you don't see it.

The same pattern works for any downloaded Linux plugin: drop the `.vst3` / `.so` /
`.clap` into the matching `~/reaper/.{vst3,vst,clap}` folder and re-scan. Because
`~/reaper` is the persisted container home, it's a one-time step.

### Windows VST plugins

Planned as an `addons/windows.Dockerfile` variant (Wine + yabridge), same opt-in
pattern — so Wine's ~1 GB only lands if you build it.

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
- Everything (REAPER config, license, projects, recordings, hand-installed
  plugins) lives under `~/reaper` on the host — nothing hidden in a Docker volume.

## podman vs docker

Either works; the image is identical OCI. The one real constraint is that the
container process must present as the host uid to reach the Wayland socket —
Docker handles this via the baked `uid 1000` user (or `--build-arg UID`), Podman
via rootless `--userns=keep-id`. Docker is the default here simply because it was
already installed. Podman is a drop-in with a smaller (daemonless, rootless)
footprint if you prefer it.
