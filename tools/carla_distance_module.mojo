# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the spiral-domain proof path.

    carla_distance_module
"""

from std.sys import argv, exit, stderr

from tools.carla_distance_gate import distance_module


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_distance_module", file=stderr)
    exit(2)


def main():
    """Print the spiral-domain proof path."""
    if len(argv()) != 1:
        _usage()
    print(distance_module(), end="")
