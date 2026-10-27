# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the optional-runtime declaration schedule.

    carla_optional_runtime_schedule
"""

from std.sys import argv, exit, stderr

from tools._optional_runtime_schedule import optional_runtime_schedule


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_optional_runtime_schedule", file=stderr)
    exit(2)


def main():
    """Print the optional-runtime declaration schedule."""
    if len(argv()) != 1:
        _usage()
    print(optional_runtime_schedule(), end="")
