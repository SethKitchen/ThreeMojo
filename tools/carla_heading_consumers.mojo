# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the fresh heading consumers.

    carla_heading_consumers
    carla_heading_consumers --plan

The plain command prints the three consumers. `--plan` reads the package
path before those consumers.
"""

from std.sys import argv, exit, stderr

from tools._heading_consumers import heading_consumers, heading_plan


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_heading_consumers | carla_heading_consumers --plan",
        file=stderr,
    )
    exit(2)


def main():
    """Print the three heading consumers, or the package and consumers."""
    var arguments = argv()
    if len(arguments) == 2 and arguments[1] == "--plan":
        print(heading_plan(), end="")
        return
    if len(arguments) != 1:
        _usage()
    print(heading_consumers(), end="")
