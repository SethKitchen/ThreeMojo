# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Rebuild one selection predecessor.

    carla_selection_predecessor PATH

`PATH` is the predecessor JSON. The program prints the restored module.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._selection_predecessor import selection_predecessor


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_selection_predecessor PATH", file=stderr)
    exit(2)


def main() raises:
    """Print the restored selection predecessor.

    Raises:
        Error: The command is invalid, or the predecessor changed.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(selection_predecessor(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
