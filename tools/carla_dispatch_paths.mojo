# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the dispatch sources and protected paths.

    carla_dispatch_paths
"""

from std.sys import argv, exit, stderr

from tools.carla_dispatch_gate import dispatch_paths


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_dispatch_paths", file=stderr)
    exit(2)


def main() raises:
    """Print the two dispatch sources and the five protected paths.

    Raises:
        Error: The command is invalid, or the lists cannot be written.
    """
    if len(argv()) != 1:
        _usage()
    try:
        print(dispatch_paths(), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
