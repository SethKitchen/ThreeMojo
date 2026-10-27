# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the ideal projection digests.

    carla_ideal_digests
"""

from std.sys import argv, exit, stderr

from tools.carla_ideal_gate import ideal_digests


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_ideal_digests", file=stderr)
    exit(2)


def main():
    """Print the legacy digest and the projected digest."""
    if len(argv()) != 1:
        _usage()
    print(ideal_digests(), end="")
