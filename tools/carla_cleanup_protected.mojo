# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the extra reviewed-cleanup inputs.

    carla_cleanup_protected
"""

from std.sys import argv, exit, stderr

from tools.carla_cleanup_gate import cleanup_protected_tail


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_cleanup_protected", file=stderr)
    exit(2)


def main() raises:
    """Print the fourteen protected inputs that follow the invariant closure.

    Raises:
        Error: The command is invalid, or the list cannot be written.
    """
    if len(argv()) != 1:
        _usage()
    try:
        print(cleanup_protected_tail(), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
