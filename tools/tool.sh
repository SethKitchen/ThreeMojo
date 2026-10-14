#!/bin/sh
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Build a Mojo tool once, then run it:
#
#     tools/tool.sh MOJO NAME ARGUMENT...
#
# runs tools/NAME.mojo with the arguments, and builds it with the compiler
# MOJO. The Makefile reads the tools'
# output while it parses, many times in one run, and `mojo run` compiles
# the tool every time. So the program is kept in .cache/tools/, under the
# toolchain's version, and built again only when a `.mojo` file under
# tools/ or loaders/ is newer than it. A tool must import nothing else.
#
# The script works from the repository root, where the Makefile runs.
set -eu
mojo=$1
name=$2
shift 2
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
version=$($mojo --version 2>/dev/null | cksum | cut -d ' ' -f 1)
directory=.cache/tools/$version
program=$directory/$name
if [ ! -x "$program" ] ||
    [ -n "$(find tools loaders -name '*.mojo' -newer "$program" 2>/dev/null | head -n 1)" ]; then
    mkdir -p "$directory"
    # Parallel runs can build at once: each writes its own file, and the
    # rename replaces the program in one step.
    partial=$program.$$
    if ! $mojo build -I . -o "$partial" "tools/$name.mojo" >&2; then
        rm -f "$partial"
        echo "tools/tool.sh: could not build tools/$name.mojo" >&2
        exit 2
    fi
    mv -f "$partial" "$program"
fi
exec "$program" "$@"
