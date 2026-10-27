# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Write historical pin values back along coverage transitions.

    carla_pin_apply PATH

`PATH` is JSON with `pins` and `transitions`. The program prints the
pins after each historical value is written.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import apply_pin_transitions


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_pin_apply PATH", file=stderr)
    exit(2)


def main() raises:
    """Apply one list of pin transitions.

    Raises:
        Error: The command is invalid, or a pointer cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(apply_pin_transitions(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
