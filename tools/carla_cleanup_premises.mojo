# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the five reviewed cleanup premise lists.

    carla_cleanup_premises DIRECTORY

`DIRECTORY` contains `sources.json` with `line`, `arc`, `bounds`, `center`,
and `outward`.
"""

from std.sys import argv, exit, stderr

from tools._cleanup_premises import prepare_cleanup_premises
from tools.carla_cleanup_gate import cleanup_premises


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_cleanup_premises DIRECTORY", file=stderr)
    exit(2)


def main() raises:
    """Check the five premise declarations.

    Raises:
        Error: The command is invalid, or a premise fragment changed.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        prepare_cleanup_premises(arguments[1])
        cleanup_premises(arguments[1])
    except error:
        print(String(error), file=stderr)
        exit(1)
