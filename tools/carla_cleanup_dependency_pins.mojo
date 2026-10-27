# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the reviewed trig and geometry dependency pins.

    carla_cleanup_dependency_pins
"""

from std.sys import argv, exit, stderr

from tools._cleanup_dependency_pins import cleanup_dependency_pins


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_cleanup_dependency_pins", file=stderr)
    exit(2)


def main():
    """Print the trig and geometry dependency pins."""
    if len(argv()) != 1:
        _usage()
    print(cleanup_dependency_pins(), end="")
