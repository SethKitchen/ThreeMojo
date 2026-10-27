# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the native loop source and the production drivers.

    carla_coverage_loop_drivers
"""

from std.sys import argv, exit, stderr

from tools._coverage_loop_drivers import coverage_loop_drivers


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_coverage_loop_drivers", file=stderr)
    exit(2)


def main():
    """Print the native loop source and the production drivers."""
    if len(argv()) != 1:
        _usage()
    print(coverage_loop_drivers(), end="")
