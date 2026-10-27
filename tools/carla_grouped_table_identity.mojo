# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the grouped proof module and token digest.

    carla_grouped_table_identity
"""

from std.sys import argv, exit, stderr

from tools.carla_grouped_gate import grouped_table_identity


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_grouped_table_identity", file=stderr)
    exit(2)


def main():
    """Print the grouped proof module and its token digest."""
    if len(argv()) != 1:
        _usage()
    print(grouped_table_identity(), end="")
