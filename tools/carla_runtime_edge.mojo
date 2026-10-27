# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Extend one runtime-boundary edge from a reviewed view step.

    carla_runtime_edge PATH

`PATH` is JSON with `path`, `edge`, and `steps`. The program prints the
decision.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._runtime_edge import extend_runtime_edge


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_runtime_edge PATH", file=stderr)
    exit(2)


def main() raises:
    """Extend one runtime-boundary edge.

    Raises:
        Error: The command is invalid, or the step is incomplete.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(extend_runtime_edge(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
