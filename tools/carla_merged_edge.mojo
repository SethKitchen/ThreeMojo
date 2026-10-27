# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Put a module path on a runtime-boundary edge.

    carla_merged_edge PATH

`PATH` is JSON with `path` and `edge`. The program prints the edge.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._merged_edge import merged_edge


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_merged_edge PATH", file=stderr)
    exit(2)


def main() raises:
    """Print one edge with its module path.

    Raises:
        Error: The command is invalid, or the edge is missing.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(merged_edge(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
