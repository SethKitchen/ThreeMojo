# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the reviewed ideal half projection.

    carla_ideal_half --legacy PATH
    carla_ideal_half --current PATH --dump PATH

`--legacy` prints the commuted function dump.
`--current` requires that dump to match the live projection.
The program reads only the files it is given.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_expr import ideal_current_matches, ideal_legacy_dump


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_ideal_half --legacy PATH | --current PATH --dump PATH",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check one legacy spiral or compare it with the live spiral.

    Raises:
        Error: The command is invalid, or the projection changed.
    """
    var legacy = String("")
    var current = String("")
    var dump = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--legacy" or word == "--current" or word == "--dump":
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--legacy":
                legacy = value
            elif word == "--current":
                current = value
            else:
                dump = value
            index += 2
            continue
        _usage()
    var legacy_mode = legacy != ""
    var current_mode = current != "" or dump != ""
    if legacy_mode == current_mode:
        _usage()
    if current != "" and dump == "":
        _usage()
    if dump != "" and current == "":
        _usage()
    try:
        if legacy_mode:
            print(ideal_legacy_dump(Path(legacy).read_text()), end="")
            return
        ideal_current_matches(Path(current).read_text(), Path(dump).read_text())
    except error:
        print(String(error), file=stderr)
        exit(1)
