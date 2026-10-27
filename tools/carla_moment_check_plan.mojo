# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the moment dependency record and the check messages.

    carla_moment_check_plan
"""

from std.sys import argv, exit, stderr

from tools._moment_check_plan import moment_check_plan


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_moment_check_plan", file=stderr)
    exit(2)


def main():
    """Print the moment dependency record and the check messages."""
    if len(argv()) != 1:
        _usage()
    print(moment_check_plan(), end="")
