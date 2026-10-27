# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the reviewed Sum2 helper and caller texts.

    carla_sum2_checkpoints
"""

from std.sys import argv, exit, stderr

from tools._sum2_checkpoints import sum2_checkpoints


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_sum2_checkpoints", file=stderr)
    exit(2)


def main() raises:
    """Print the four reviewed Sum2 source texts.

    Raises:
        Error: The command is invalid, or the texts cannot be written.
    """
    if len(argv()) != 1:
        _usage()
    try:
        print(sum2_checkpoints(), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
