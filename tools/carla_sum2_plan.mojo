# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the Sum2 module names and caller comparisons.

    carla_sum2_plan
"""

from std.sys import argv, exit, stderr

from tools._sum2_plan import sum2_plan


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_sum2_plan", file=stderr)
    exit(2)


def main():
    """Print the Sum2 module names and caller comparisons."""
    if len(argv()) != 1:
        _usage()
    print(sum2_plan(), end="")
