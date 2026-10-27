# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the runtime-boundary module paths.

    carla_runtime_boundary_modules
"""

from std.sys import argv, exit, stderr

from tools.carla_runtime_boundary_gate import runtime_boundary_modules


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_runtime_boundary_modules", file=stderr)
    exit(2)


def main() raises:
    """Print the four runtime-boundary module paths.

    Raises:
        Error: The command is invalid, or the list cannot be written.
    """
    if len(argv()) != 1:
        _usage()
    try:
        print(runtime_boundary_modules(), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
