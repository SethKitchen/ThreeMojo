# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the stored-moment pin shape.

    carla_moment_pins PATH

`PATH` is JSON with `pins` and `spec`. The program prints nothing when
the shape matches.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_pin_shape import require_moment_pin_shape


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_moment_pins PATH", file=stderr)
    exit(2)


def main() raises:
    """Check one moment pin document.

    Raises:
        Error: The command is invalid, or the pin shape changed.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        require_moment_pin_shape(Path(arguments[1]).read_text())
    except error:
        print(String(error), file=stderr)
        exit(1)
