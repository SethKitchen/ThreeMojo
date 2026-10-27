# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read every stored-moment scalar word.

    carla_moment_scalars PATH

PATH is a JSON object of scalar pins. The command prints a JSON object of
the unsigned decimal words.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_scalars import moment_scalars


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_moment_scalars PATH", file=stderr)
    exit(2)


def main() raises:
    """Print the stored scalar words that match their pins.

    Raises:
        Error: The command is invalid, or a scalar pin changed.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(moment_scalars(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
