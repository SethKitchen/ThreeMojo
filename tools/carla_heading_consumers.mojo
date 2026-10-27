# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the fresh heading consumers.

    carla_heading_consumers
"""

from std.sys import argv, exit, stderr

from tools._heading_consumers import heading_consumers


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_heading_consumers", file=stderr)
    exit(2)


def main():
    """Print the three heading consumers."""
    if len(argv()) != 1:
        _usage()
    print(heading_consumers(), end="")
