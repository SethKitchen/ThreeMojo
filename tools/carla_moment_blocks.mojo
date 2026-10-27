# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check every stored-moment operation block.

    carla_moment_blocks PATH

PATH is a JSON list of block pins. The command prints a JSON object of
the normalized blocks. It prints nothing else when they match.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_blocks import moment_blocks


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_moment_blocks PATH", file=stderr)
    exit(2)


def main() raises:
    """Print the normalized blocks that match their pins.

    Raises:
        Error: The command is invalid, or a block pin changed.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(moment_blocks(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
