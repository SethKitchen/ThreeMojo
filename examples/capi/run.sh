#!/bin/sh
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Run the C ABI examples. Each run builds first if a source is newer.
#
#   run.sh native [core|scene|water|water-gpu|splat] [WIDTH HEIGHT] [--frames N] [--dump F.ppm] [--headless] [--crisp] [--cpu]
#       Open a macOS window. The title and a label show the frame rate.
#       The window scales the frame smoothly. --crisp keeps hard pixels.
#       The splats are drawn on Metal at the window's size in pixels. --cpu
#       draws them on the CPU. Escape, Command+Q or Control-C in the terminal
#       quits it.
#   run.sh web [core|water|splat] [PORT]
#       Serve the WebAssembly build on localhost and open it in a browser.
#       A browser with WebGPU draws the water and the splats on its GPU. Add
#       ?gpu=0 to the address to draw on the CPU. serve.py sends the headers
#       that let the CPU water run on many threads.
#   run.sh check
#       Check the native and the WebAssembly builds without a window. A
#       headless Chrome checks the WebGPU water and splats, where there is a
#       Chrome, and the native splat on Metal is checked against the CPU.
#
# core is a triangle that the three builds draw the same way. scene is the
# full renderer, and the native host only. water is the Clearwater water.
# water-gpu is the same water shaded on a GPU: it needs MAX and a GPU. splat
# is the scan of three tomatoes, 445,409 Gaussian splats.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT=$REPO/out/capi
case $(uname -s) in
Darwin) EXT=dylib ;;
*) EXT=so ;;
esac

die() {
  echo "run.sh: $*" >&2
  exit 1
}

# stale FILE: succeeds if FILE is missing, or a source is newer than it.
stale() {
  [ -e "$1" ] || return 0
  [ -n "$(find "$REPO" "$HERE" \( -path "$REPO/.venv" -o -path "$REPO/out" -o -path "$REPO/coverage" \) -prune -o \
    \( -name '*.mojo' -o -name '*.m' -o -name '*.c' -o -name '*.py' -o -name '*.js' -o -name '*.html' -o -name '*.sh' \
       -o -name '*.metal' -o -name '*.wgsl' -o -name '*.h' \) \
    -newer "$1" -print -quit)" ]
}

usage() {
  sed -n '/^# Run the C ABI/,/^set -eu/p' "$0" | sed '$d; s/^# \{0,1\}//'
  exit 2
}

native() {
  app=core
  case ${1:-} in core | scene | water | water-gpu | splat) app=$1 && shift ;; esac
  app=$(echo "$app" | tr - _)
  width=480
  height=320
  [ "$app" = water ] && width=320 && height=180
  [ "$app" = water_gpu ] && width=1280 && height=720
  # Points. A Retina display makes the splat frame twice as many pixels.
  [ "$app" = splat ] && width=960 && height=540
  case ${1:-} in '' | -*) ;; *) width=$1 && height=${2:?give a height with the width} && shift 2 ;; esac
  case $width$height in *[!0-9]*) die "the width and the height must be whole numbers: $width $height" ;; esac
  [ "$(uname -s)" = Darwin ] || die "the window host is macOS only. On Linux, use window/x11.mojo."
  lib=$OUT/libthreemojo_$app.$EXT
  if stale "$lib"; then
    if [ "$app" = water_gpu ]; then "$HERE/build.sh" gpu; else APPS=$app "$HERE/build.sh" native; fi
  fi
  if stale "$OUT/ThreeMojo.app/Contents/MacOS/threemojo_host"; then "$HERE/build.sh" host; fi
  # No window: run it here. The water reads assets/pebbles.jpg from the folder
  # it runs in.
  for argument in "$@"; do
    if [ "$argument" = --headless ]; then
      cd "$REPO"
      exec "$OUT/threemojo_host" "$lib" "$width" "$height" "$@"
    fi
  done
  # A window: start the bundle through Launch Services, which makes it the
  # active app. A program that a shell starts opens behind the terminal.
  streams=""
  if [ -t 0 ]; then
    terminal=$(tty)
    streams="--stdout $terminal --stderr $terminal"
  fi
  trap 'pkill -f "ThreeMojo.app/Contents/MacOS/threemojo_host" 2>/dev/null' INT TERM
  # shellcheck disable=SC2086
  open -n -W $streams "$OUT/ThreeMojo.app" --args "$lib" "$width" "$height" --chdir "$REPO" "$@"
}

web() {
  app=core
  case ${1:-} in core | water | splat) app=$1 && shift ;; esac
  port=${1:-8000}
  if stale "$OUT/web/threemojo_water_threads.wasm" || stale "$OUT/web/threemojo_splat.wasm" ||
    stale "$OUT/web/index.html"; then "$HERE/build.sh" web; fi
  url="http://localhost:$port/?app=$app"
  echo "Serving $OUT/web"
  echo "  core:  http://localhost:$port/?app=core"
  echo "  water: http://localhost:$port/?app=water"
  echo "  splat: http://localhost:$port/?app=splat"
  echo "Press Control-C to stop."
  (sleep 1 && { open "$url" 2>/dev/null || xdg-open "$url" 2>/dev/null || true; }) &
  # serve.py isolates the page, which the water needs to use many threads.
  PYTHON=$REPO/.venv/bin/python
  [ -x "$PYTHON" ] || PYTHON=python3
  exec "$PYTHON" -I "$HERE/serve.py" "$OUT/web" "$port"
}

check() {
  "$HERE/build.sh" native web
  failed=0
  if command -v node >/dev/null 2>&1; then
    node "$HERE/web/check.mjs" "$OUT/web" || failed=1
    node "$HERE/web/check_gpu.mjs" "$OUT/web" || failed=1
    node "$HERE/web/check_splat_gpu.mjs" "$OUT/web" || failed=1
  else
    echo "node is not installed: the WebAssembly check is skipped"
  fi
  if [ "$(uname -s)" = Darwin ]; then
    stale "$OUT/threemojo_host" && "$HERE/build.sh" host
    cd "$REPO"
    echo "== native host, core, 60 frames: the hash must be the Mojo test's"
    line=$("$OUT/threemojo_host" "$OUT/libthreemojo_core.$EXT" 96 64 --headless --frames 60 | tail -n 1)
    echo "$line"
    case $line in *"frame hash 658073559776311977") echo "ok   the native hash" ;; *) echo "FAIL the native hash"; failed=1 ;; esac
    echo "== native host, water, 30 frames"
    "$OUT/threemojo_host" "$OUT/libthreemojo_water.$EXT" 64 36 --headless --frames 30 | tail -n 1
    echo "== native host, splat, 12 frames: Metal must match the CPU"
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT
    "$OUT/threemojo_host" "$OUT/libthreemojo_splat.$EXT" 320 180 --headless --frames 12 \
      --dump "$scratch/metal.ppm" | tail -n 1
    "$OUT/threemojo_host" "$OUT/libthreemojo_splat.$EXT" 320 180 --headless --frames 12 --cpu \
      --dump "$scratch/cpu.ppm" | tail -n 1
    PYTHON=$REPO/.venv/bin/python
    [ -x "$PYTHON" ] || PYTHON=python3
    if "$PYTHON" -I "$HERE/compare_ppm.py" "$scratch/metal.ppm" "$scratch/cpu.ppm" 0.3 32 0.001; then
      echo "ok   the Metal splats"
    else
      echo "FAIL the Metal splats"
      failed=1
    fi
  fi
  [ "$failed" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
}

case ${1:-} in
native) shift && native "$@" ;;
web) shift && web "$@" ;;
check) check ;;
*) usage ;;
esac
