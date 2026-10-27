# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read every stored-moment constant array.

    carla_moment_arrays PATH

PATH is a JSON list of array pins. The command prints a JSON object of
the unsigned decimal words.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_arrays import moment_arrays


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_moment_arrays PATH", file=stderr)
    exit(2)


def main() raises:
    """Print the stored array words that match their pins.

    Raises:
        Error: The command is invalid, or an array pin changed.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(moment_arrays(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
