# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the sampled copy order and rename map.

    carla_sampled_copies
"""

from std.sys import argv, exit, stderr

from tools._sampled_copies import sampled_copies


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_sampled_copies", file=stderr)
    exit(2)


def main() raises:
    """Print the copy order and the rename map.

    Raises:
        Error: The command is invalid, or the map cannot be written.
    """
    if len(argv()) != 1:
        _usage()
    try:
        print(sampled_copies(), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
