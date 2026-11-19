#!/bin/sh
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Build a Mojo tool once, then run it:
#
#     tools/tool.sh MOJO NAME ARGUMENT...
#     tools/tool.sh MOJO --build NAME
#
# runs tools/NAME.mojo with the arguments, and builds it with the compiler
# MOJO. With --build, the script only builds the program, so that parallel
# runs that follow do not all build it at once. The Makefile reads the tools' output while it parses, many times in
# one run, and `mojo run` compiles the tool every time. So the program is
# kept in .cache/tools/, under the toolchain's version.
#
# The program is built again when a source it was built from is newer than
# it. Those sources are the tool and every repository module that the tool
# imports, directly or through other modules. The build writes their names
# to NAME.d beside the program. A tool can import a library module, and an
# edit to that module builds the tool again. An edit to any other file does
# not. A program that has no NAME.d is from an older script, and it is built
# again.
#
# The script works from the repository root, where the Makefile runs.
set -eu
mojo=$1
shift
build_only=
if [ "$1" = --build ]; then
    build_only=1
    shift
fi
name=$1
shift
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

# Print the repository sources of a Mojo file: the file, and every module
# under the root that it imports, directly or through others, one name to a
# line. A module is looked for from the root, then beside the file that
# imports it, as the compiler looks. A name that is in neither place is a
# module of the standard library. The paths hold no spaces, because they are
# module names.
sources_of() {
    seen=
    queue=$1
    while [ -n "$queue" ]; do
        file=${queue%% *}
        case $queue in
        *' '*) queue=${queue#* } ;;
        *) queue= ;;
        esac
        case " $seen " in
        *" $file "*) continue ;;
        esac
        seen="$seen $file"
        beside=$(dirname "$file")
        for path in $(sed -n \
            -e 's/^[[:space:]]*from[[:space:]]\{1,\}\([A-Za-z_][A-Za-z0-9_.]*\)[[:space:]]\{1,\}import.*/\1/p' \
            -e 's/^[[:space:]]*import[[:space:]]\{1,\}\([A-Za-z_][A-Za-z0-9_.]*\).*/\1/p' \
            "$file" 2>/dev/null | tr . /); do
            if [ -f "$path.mojo" ]; then
                queue="${queue:+$queue }$path.mojo"
            elif [ -f "$path/__init__.mojo" ]; then
                queue="${queue:+$queue }$path/__init__.mojo"
            elif [ -f "$beside/$path.mojo" ]; then
                queue="${queue:+$queue }$beside/$path.mojo"
            fi
        done
    done
    printf '%s\n' $seen
}

version=$($mojo --version 2>/dev/null | cksum | cut -d ' ' -f 1)
directory=.cache/tools/$version
program=$directory/$name
stale=
if [ ! -x "$program" ] || [ ! -s "$program.d" ]; then
    stale=1
elif [ -n "$(find $(cat "$program.d") -newer "$program" 2>/dev/null | head -n 1)" ]; then
    stale=1
fi
if [ -n "$stale" ]; then
    mkdir -p "$directory"
    # Parallel runs can build at once: each writes its own files, and each
    # rename replaces a file in one step. The list of sources is in place
    # before the program is, so that a program always has its list.
    partial=$program.$$
    sources_of "tools/$name.mojo" > "$partial.d"
    if ! $mojo build -I . -o "$partial" "tools/$name.mojo" >&2; then
        rm -f "$partial" "$partial.d"
        echo "tools/tool.sh: could not build tools/$name.mojo" >&2
        exit 2
    fi
    mv -f "$partial.d" "$program.d"
    mv -f "$partial" "$program"
fi
if [ -n "$build_only" ]; then
    exit 0
fi
exec "$program" "$@"
