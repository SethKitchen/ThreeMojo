#!/bin/sh
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Build the C ABI examples into out/capi/.
#
#   build.sh [native] [web] [host] [gpu]   default: everything this machine can,
#                                          and gpu only if you name it
#
#   native  libthreemojo_core, libthreemojo_scene, libthreemojo_water and
#           libthreemojo_splat, shared libraries
#   web     threemojo_core.wasm, threemojo_water.wasm and threemojo_splat.wasm,
#           and the page that runs them, in out/capi/web. The water also builds for many threads
#           as threemojo_water_threads.wasm, which a page can run only when
#           serve.py sends the headers that allow shared memory.
#   host    threemojo_host and ThreeMojo.app, the macOS window (macOS only). The
#           window draws the splats on Metal.
#   gpu     libthreemojo_water_gpu, the water shaded on a GPU. It needs MAX and
#           a GPU. The first build on Apple Metal can take many minutes.
#
# Environment: MOJO, PYTHON, CLANG (a clang that has the wasm32 target) and
# WASM_LD override what this script finds.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT=$REPO/out/capi
MOJO=${MOJO:-$REPO/.venv/bin/mojo}
PYTHON=${PYTHON:-$REPO/.venv/bin/python}
[ -x "$PYTHON" ] || PYTHON=python3
APPS=${APPS:-core scene water splat}
# The apps that need MAX and a GPU. They are built only when asked for.
GPU_APPS=${GPU_APPS:-water_gpu}
# The apps that build for WebAssembly. capi_scene needs the whole renderer.
WASM_APPS=${WASM_APPS:-core water splat}
# The apps that also build for many threads: threemojo_APP_threads.wasm.
THREAD_APPS=${THREAD_APPS:-water}
# The memory that threads share. The page makes it, so these sizes must match
# MEMORY_PAGES in web/threemojo.js. A page is 64 KiB.
INITIAL_MEMORY=${INITIAL_MEMORY:-134217728}
MAX_MEMORY=${MAX_MEMORY:-1073741824}
EXPORTS="tm_abi_version tm_init tm_create tm_destroy tm_event tm_step tm_frame tm_width tm_height"

case $(uname -s) in
Darwin) EXT=dylib ;;
*) EXT=so ;;
esac

die() {
  echo "build.sh: $*" >&2
  exit 1
}

mojo_build() { # mojo_build EMIT OUTPUT SOURCE
  # The compiler prints a crash-reporter banner that is not an error.
  # Capture its status before filtering: an old or partial output must not
  # make a failed compile look successful. This also works with macOS sh.
  if build_log=$("$MOJO" build -I "$REPO" --emit "$1" -o "$2" "$3" 2>&1); then
    build_status=0
  else
    build_status=$?
  fi
  printf '%s\n' "$build_log" | sed '/Crashpad/d'
  [ "$build_status" -eq 0 ] || die "mojo build failed with status $build_status"
  [ -s "$2" ] || die "mojo did not write $2"
}

find_wasm_clang() {
  for candidate in "${CLANG:-}" \
    "$(brew --prefix llvm 2>/dev/null)/bin/clang" \
    /opt/homebrew/opt/llvm/bin/clang /usr/local/opt/llvm/bin/clang \
    /usr/lib/llvm*/bin/clang clang; do
    [ -n "$candidate" ] || continue
    if "$candidate" --print-targets 2>/dev/null | grep -q wasm32; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

find_wasm_ld() {
  if [ -n "${WASM_LD:-}" ]; then
    echo "$WASM_LD"
  elif command -v wasm-ld >/dev/null 2>&1; then
    command -v wasm-ld
  else
    # Mojo ships lld, and lld picks the WebAssembly flavor from its own name.
    [ -e "$REPO/.venv/bin/lld" ] || return 1
    mkdir -p "$OUT/bin"
    ln -sf "$REPO/.venv/bin/lld" "$OUT/bin/wasm-ld"
    echo "$OUT/bin/wasm-ld"
  fi
}

build_native() {
  echo "== native libraries"
  for app in $APPS; do
    mojo_build shared-lib "$OUT/libthreemojo_$app.$EXT" "$REPO/window/capi_$app.mojo"
  done
}

# wasm_module APP THREADS: window/capi_APP.mojo as
# out/capi/web/threemojo_APP.wasm, or with THREADS=yes as
# threemojo_APP_threads.wasm, which runs on a pool of Web Workers.
wasm_module() {
  app=$1
  threads=$2
  exports=$EXPORTS
  cflags=""
  ldflags="-z stack-size=2097152"
  suffix=""
  case $app in
  water)
    # The water module takes its photograph from the host, and Mojo's IR
    # for its drawing code uses tail calls and vectors.
    exports="$exports tm_alloc tm_free tm_asset"
    # A browser with WebGPU draws the frame on its device.
    exports="$exports tm_gpu_prepare tm_gpu_glare tm_gpu_part tm_gpu_words tm_gpu_info"
    cflags="-mtail-call -msimd128"
    ;;
  splat)
    # The splat module takes its scan from the host. A browser with WebGPU
    # sorts here and draws the splats on its device.
    exports="$exports tm_alloc tm_free tm_asset tm_resize"
    exports="$exports tm_splat_prepare tm_splat_part tm_splat_words tm_splat_info"
    cflags="-mtail-call -msimd128"
    ;;
  esac
  if [ "$threads" = yes ]; then
    # Atomics and bulk memory are what shared memory needs. A worker starts
    # on a stack that the page makes with mw_stack, and sets __stack_pointer
    # to it, so that global is exported.
    exports="$exports mw_set_threads mw_stack mw_worker_main __stack_pointer"
    cflags="$cflags -matomics -mbulk-memory"
    ldflags="$ldflags --shared-memory --import-memory --initial-memory=$INITIAL_MEMORY --max-memory=$MAX_MEMORY"
    suffix="_threads"
    object=$OUT/wasm/mwrt_threads.o
  else
    object=$OUT/wasm/mwrt.o
  fi
  mojo_build llvm "$OUT/wasm/$app.ll" "$REPO/window/capi_$app.mojo"
  "$PYTHON" -I "$HERE/retarget.py" "$clang" "$OUT/wasm/$app.ll" "$OUT/wasm/$app.wasm32.ll"
  # shellcheck disable=SC2086
  "$clang" --target=wasm32-unknown-unknown -O2 $cflags -c "$OUT/wasm/$app.wasm32.ll" -o "$OUT/wasm/$app$suffix.o"
  flags=""
  for name in $exports; do flags="$flags --export=$name"; done
  # shellcheck disable=SC2086
  "$wasm_ld" --no-entry $ldflags $flags -o "$OUT/web/threemojo_$app$suffix.wasm" \
    "$OUT/wasm/$app$suffix.o" "$object"
}

build_gpu() {
  echo "== native libraries on the GPU"
  for app in $GPU_APPS; do
    mojo_build shared-lib "$OUT/libthreemojo_$app.$EXT" "$REPO/window/capi_$app.mojo"
  done
}

build_web() {
  echo "== WebAssembly modules"
  clang=$(find_wasm_clang) ||
    die "no clang with the wasm32 target (macOS: brew install llvm; Linux: apt install clang lld)"
  wasm_ld=$(find_wasm_ld) || die "no wasm-ld (macOS: brew install lld; or set WASM_LD)"
  mkdir -p "$OUT/web" "$OUT/wasm"
  # No fused multiply-add: mwrt.c defines fma, and a fused fma inside it
  # would call itself.
  "$clang" --target=wasm32-unknown-unknown -O2 -ffreestanding -ffp-contract=off \
    -c "$HERE/mwrt.c" -o "$OUT/wasm/mwrt.o"
  "$clang" --target=wasm32-unknown-unknown -O2 -ffreestanding -ffp-contract=off \
    -DMW_THREADS -matomics -mbulk-memory -c "$HERE/mwrt.c" -o "$OUT/wasm/mwrt_threads.o"
  for app in $WASM_APPS; do
    wasm_module "$app" no
  done
  for app in $THREAD_APPS; do
    wasm_module "$app" yes
  done
  cp "$HERE/web/index.html" "$HERE/web/threemojo.js" "$HERE/web/threemojo_worker.js" "$OUT/web/"
  cp "$HERE/web/water_gpu.js" "$HERE/web/water.wgsl" "$OUT/web/"
  cp "$HERE/web/splat_gpu.js" "$HERE/web/splat.wgsl" "$OUT/web/"
  cp "$REPO/assets/pebbles.jpg" "$REPO/assets/tomatoes/tomatoes.v4.spz" "$OUT/web/"
}

build_host() {
  [ "$(uname -s)" = Darwin ] || die "the window host is macOS only; on Linux use window/x11.mojo"
  echo "== macOS window host"
  # The Mojo libraries need the runtime libraries that come with the compiler.
  runtime=$(ls -d "$REPO"/.venv/lib/python3*/site-packages/modular/lib 2>/dev/null | head -n 1)
  [ -n "$runtime" ] || die "no Mojo runtime libraries under $REPO/.venv"
  # The splat shaders go into the host as a C string, and compile when a window
  # opens, so the build needs no Metal toolchain.
  mkdir -p "$OUT/host"
  "$PYTHON" -I - "$HERE/splat.metal" "$OUT/host/splat_msl.h" <<'PY'
import sys

lines = open(sys.argv[1]).read().splitlines()
text = ["/* Made by build.sh from splat.metal. */", "static const char SPLAT_MSL[] ="]
for line in lines:
    text.append('    "' + line.replace("\\", "\\\\").replace('"', '\\"') + '\\n"')
text.append(";")
open(sys.argv[2], "w").write("\n".join(text) + "\n")
PY
  cc -O2 -fobjc-arc -mmacosx-version-min=14.0 -I "$REPO/window" -I "$HERE" -I "$OUT/host" \
    -framework Cocoa -framework QuartzCore -framework Metal -Wl,-rpath,"$runtime" \
    -o "$OUT/threemojo_host" "$HERE/macos_host.m" "$HERE/macos_splat.m"
  # The window runs from a bundle. See Info.plist.
  app=$OUT/ThreeMojo.app
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS"
  cp "$OUT/threemojo_host" "$app/Contents/MacOS/"
  cp "$HERE/Info.plist" "$app/Contents/"
}

mkdir -p "$OUT"
[ -x "$MOJO" ] || die "no mojo at $MOJO"
targets=${*:-}
if [ -z "$targets" ]; then
  targets="native web"
  [ "$(uname -s)" = Darwin ] && targets="$targets host"
fi
for target in $targets; do
  case $target in
  native) build_native ;;
  web) build_web ;;
  host) build_host ;;
  gpu) build_gpu ;;
  *) die "unknown target $target (native, web, host or gpu)" ;;
  esac
done
echo "built into $OUT"
