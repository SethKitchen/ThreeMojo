# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Compare two reviewed Sum2 function graphs.

    carla_sum2_graph PATH

`PATH` is JSON with `left`, `left_name`, `right`, `right_name`, and
`message`. Optional `rename`, `drop_first`, and `expect_first` apply to
the left function. The program prints nothing when the graphs match.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_expr import sum2_graphs_match


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_sum2_graph PATH", file=stderr)
    exit(2)


def main() raises:
    """Compare one pair of Sum2 function dumps.

    Raises:
        Error: The command is invalid, or the graphs differ.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        sum2_graphs_match(Path(arguments[1]).read_text())
    except error:
        print(String(error), file=stderr)
        exit(1)
