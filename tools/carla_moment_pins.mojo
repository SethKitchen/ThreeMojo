# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the stored-moment pin shape.

    carla_moment_pins PATH
    carla_moment_pins --legacy PATH
    carla_moment_pins --result PATH

`PATH` is JSON with `pins` and `spec`. `--legacy` reads `actual` and
`expected`. `--result` reads `projection` and `result`. The program
prints nothing when the check matches.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_pin_shape import (
    require_legacy_digest,
    require_moment_pin_shape,
    require_projection_result,
)


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_moment_pins PATH | --legacy PATH | --result PATH",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check one moment pin document.

    Raises:
        Error: The command is invalid, or a pin check failed.
    """
    var arguments = argv()
    var mode = String("shape")
    var path = String("")
    if len(arguments) == 2 and not arguments[1].startswith("--"):
        path = arguments[1]
    elif len(arguments) == 3 and (
        arguments[1] == "--legacy" or arguments[1] == "--result"
    ):
        mode = arguments[1]
        path = arguments[2]
    else:
        _usage()
    try:
        var text = Path(path).read_text()
        if mode == "shape":
            require_moment_pin_shape(text)
        elif mode == "--legacy":
            require_legacy_digest(text)
        else:
            require_projection_result(text)
    except error:
        print(String(error), file=stderr)
        exit(1)
