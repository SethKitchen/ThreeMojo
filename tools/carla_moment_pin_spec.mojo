# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the stored-moment pin specification.

    carla_moment_pin_spec PATH

`PATH` is a JSON object with a `dependencies` object.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_pin_spec import moment_pin_spec


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_moment_pin_spec PATH", file=stderr)
    exit(2)


def main() raises:
    """Print the moment pin specification.

    Raises:
        Error: The command is invalid, or `dependencies` is not an object.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(moment_pin_spec(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
