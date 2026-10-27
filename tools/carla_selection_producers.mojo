# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the selection producer digests.

    carla_selection_producers
"""

from std.sys import argv, exit, stderr

from tools.carla_selection_gate import selection_producers


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_selection_producers", file=stderr)
    exit(2)


def main():
    """Print the two selection producer digests."""
    if len(argv()) != 1:
        _usage()
    print(selection_producers(), end="")
