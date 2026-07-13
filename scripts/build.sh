#!/usr/bin/env bash
# Build the lean base image, then optionally layer addon images on top.
#
#   ./scripts/build.sh                 # base only        -> creaper:latest
#   ./scripts/build.sh guitar          # base + guitar    -> creaper:guitar
#   ./scripts/build.sh guitar windows  # stack them       -> creaper:windows
#
# Each addon is addons/<name>.Dockerfile (FROM the previous image). Run a
# variant with: CREAPER_IMAGE=creaper:<name> ./run.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> base: creaper:latest"
docker build -t creaper:latest --build-arg UID="$(id -u)" .

prev="creaper:latest"
for addon in "$@"; do
    df="addons/${addon}.Dockerfile"
    [ -f "$df" ] || { echo "no such addon: $df" >&2; exit 1; }
    tag="creaper:${addon}"
    echo "==> addon '${addon}': ${prev} -> ${tag}"
    docker build -f "$df" --build-arg BASE="$prev" -t "$tag" .
    prev="$tag"
done

echo "done. run with: CREAPER_IMAGE=${prev} ./run.sh"
