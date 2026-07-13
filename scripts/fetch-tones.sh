#!/usr/bin/env bash
# Download a free/open starter set of NAM amp captures + cabinet IRs into
# ~/reaper/tones (persisted on the host; the container sees it at
# /home/reaper/tones). Turns "click around forums" into one command.
#
# NAM / Ratatouille / LSP have no auto-scan folder for these — you point the
# plugin's own file browser at ~/reaper/tones/{nam,ir} when loading.
#
# Heads-up: these community collections are large (hundreds of MB to ~1 GB).
set -euo pipefail

DEST="${CREAPER_HOME:-$HOME/reaper}/tones"
NAM_DIR="$DEST/nam"
IR_DIR="$DEST/ir"
mkdir -p "$NAM_DIR" "$IR_DIR"

# Fetch a GitHub repo's default-branch zip and extract it flat into $2.
# Uses the zipball API URL so we don't have to guess the branch name; bsdtar
# ships with Arch (libarchive) and reads zips natively.
fetch_repo() {
    local repo="$1" dest="$2" tmp
    tmp="$(mktemp -d)"
    echo "==> ${repo}"
    curl -fL "https://api.github.com/repos/${repo}/zipball" -o "$tmp/pack.zip"
    bsdtar --strip-components=1 -xf "$tmp/pack.zip" -C "$dest"
    rm -rf "$tmp"
}

# NAM community amp/pedal captures (GPLv3)
fetch_repo "pelennor2170/NAM_models" "$NAM_DIR"

# Cabinet impulse responses (MIT) — comment out if you don't want the ~1 GB
fetch_repo "itsmusician/IR-Library" "$IR_DIR"

echo
echo "Tones in: ${DEST}"
echo "  NAM captures -> ${NAM_DIR}   (load in NAM / Ratatouille)"
echo "  IR .wav      -> ${IR_DIR}    (load in LSP Impulse loader / Ratatouille)"
