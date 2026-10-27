# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the speed-parser module and tests.

    carla_speed_parser_paths
"""

from std.sys import argv, exit, stderr

from tools.carla_speed_gate import speed_parser_paths


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_speed_parser_paths", file=stderr)
    exit(2)


def main() raises:
    """Print the speed-limit module and its two correctness tests.

    Raises:
        Error: The command is invalid, or the lists cannot be written.
    """
    if len(argv()) != 1:
        _usage()
    try:
        print(speed_parser_paths(), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
