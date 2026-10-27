# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Reduce one captured standard-error file.

    carla_reduce_capture PATH

The program prints the reduced text. It does not change `PATH`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._coverage_reduce import reduce_capture


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_reduce_capture PATH", file=stderr)
    exit(2)


def main() raises:
    """Print the reduced capture.

    Raises:
        Error: The command is invalid, or a probe record is malformed.
    """
    if len(argv()) != 2:
        _usage()
    try:
        print(reduce_capture(Path(argv()[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
