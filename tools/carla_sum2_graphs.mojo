# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Compare the reviewed Sum2 caller graphs.

    carla_sum2_graphs PATH

PATH is JSON with `texts` and `checkpoints`. The command compares each
caller in the Sum2 plan. It prints nothing when every graph matches.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_expr import sum2_graph_batch


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_sum2_graphs PATH", file=stderr)
    exit(2)


def main() raises:
    """Compare every reviewed Sum2 caller graph.

    Raises:
        Error: The command is invalid, or a caller graph changed.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        sum2_graph_batch(Path(arguments[1]).read_text())
    except error:
        print(String(error), file=stderr)
        exit(1)
