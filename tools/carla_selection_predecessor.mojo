# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Rebuild one selection predecessor.

    carla_selection_predecessor PATH
    carla_selection_predecessor --then-grouped PATH GEOMETRY

`PATH` is the predecessor JSON. The program prints the restored module.
`--then-grouped` checks the grouped table after that module is restored.
`GEOMETRY` is the geometry module source.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._selection_predecessor import selection_predecessor
from tools.carla_grouped_gate import grouped_table


def selection_predecessor_then_grouped(
    payload: String, geometry: String
) raises -> String:
    """Restore one selection predecessor, then check the grouped table.

    Args:
        payload: The predecessor JSON.
        geometry: The geometry module source.

    Returns:
        The grouped pass record.

    Raises:
        Error: The predecessor fails before the grouped table is checked.
    """
    var restored = selection_predecessor(payload)
    return grouped_table(restored, geometry)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_selection_predecessor PATH | --then-grouped PATH"
            " GEOMETRY"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print the restored selection predecessor.

    Raises:
        Error: The command is invalid, or the predecessor changed.
    """
    var arguments = argv()
    try:
        if len(arguments) == 2:
            print(selection_predecessor(Path(arguments[1]).read_text()), end="")
            return
        if len(arguments) == 4 and arguments[1] == "--then-grouped":
            print(
                selection_predecessor_then_grouped(
                    Path(arguments[2]).read_text(),
                    Path(arguments[3]).read_text(),
                ),
                end="",
            )
            return
    except error:
        print(String(error), file=stderr)
        exit(1)
    _usage()
