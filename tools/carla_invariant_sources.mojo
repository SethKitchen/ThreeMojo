# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the coverage-invariant source paths.

    carla_invariant_sources
"""

from std.sys import argv, exit, stderr

from tools.carla_invariant_gate import invariant_sources


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_invariant_sources", file=stderr)
    exit(2)


def main() raises:
    """Print the four coverage-invariant source paths.

    Raises:
        Error: The command is invalid, or the list cannot be written.
    """
    if len(argv()) != 1:
        _usage()
    try:
        print(invariant_sources(), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
