# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Decide whether a lane declaration is the reviewed predecessor.

    carla_lane_predecessor PATH
    carla_lane_predecessor --minimum PATH

`PATH` is the predecessor JSON. `--minimum` reads `path`, `name`, and
`owner`. The program prints `true` or `false`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._lane_predecessor import (
    accept_lane_predecessor,
    selected_lane_minimum,
)


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_lane_predecessor PATH | --minimum PATH", file=stderr)
    exit(2)


def main() raises:
    """Decide one lane predecessor.

    Raises:
        Error: The command is invalid, or a declaration cannot be read.
    """
    var arguments = argv()
    var minimum = False
    var path = String("")
    if len(arguments) == 2:
        path = arguments[1]
    elif len(arguments) == 3 and arguments[1] == "--minimum":
        minimum = True
        path = arguments[2]
    else:
        _usage()
    try:
        var text = Path(path).read_text()
        if minimum:
            print(selected_lane_minimum(text), end="")
        else:
            print(accept_lane_predecessor(text), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
