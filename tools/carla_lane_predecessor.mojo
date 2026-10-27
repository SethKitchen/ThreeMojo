# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Decide whether a lane declaration is the reviewed predecessor.

    carla_lane_predecessor PATH

`PATH` is the predecessor JSON. The program prints `true` or `false`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._lane_predecessor import accept_lane_predecessor


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_lane_predecessor PATH", file=stderr)
    exit(2)


def main() raises:
    """Decide one lane predecessor.

    Raises:
        Error: The command is invalid, or a declaration cannot be read.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(accept_lane_predecessor(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
