# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the moment proof and interval sources.

    carla_moment_sources
"""

from std.sys import argv, exit, stderr

from tools.carla_moment_gate import moment_sources


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_moment_sources", file=stderr)
    exit(2)


def main():
    """Print the moment proof path, the interval path, and their tokens."""
    if len(argv()) != 1:
        _usage()
    print(moment_sources(), end="")
