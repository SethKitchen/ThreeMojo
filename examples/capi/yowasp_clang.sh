#!/bin/sh
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# clang 22 for WebAssembly, from the npm package @yowasp/clang, as the CLANG
# of build.sh, where the system's clang is older than 22:
#
#   npm install --prefix out/capi/yowasp @yowasp/clang
#   CLANG=examples/capi/yowasp_clang.sh examples/capi/build.sh web
#
# build.sh asks a clang for its targets first. This clang targets WebAssembly
# only, so the answer is given here.
set -eu
if [ "${1:-}" = --print-targets ]; then
  echo "    wasm32     - WebAssembly 32-bit"
  exit 0
fi
HERE=$(cd "$(dirname "$0")" && pwd)
exec node "$HERE/yowasp_clang.mjs" "$@"
