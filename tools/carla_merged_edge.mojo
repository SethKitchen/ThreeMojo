# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Put a module path on each runtime-boundary edge.

    carla_merged_edge PATH

`PATH` is one edge or a list of edges. One edge prints that edge. A list
prints those edges in order.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._merged_edge import merged_edge, merged_edges
from tools._python_json import PY_LIST, PyJson


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_merged_edge PATH", file=stderr)
    exit(2)


def main() raises:
    """Print each edge with its module path.

    Raises:
        Error: The command is invalid, or an edge is missing.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        var text = Path(arguments[1]).read_text()
        var doc = PyJson.parse(text)
        if doc.kind(doc.root) == PY_LIST:
            print(merged_edges(text), end="")
        else:
            print(merged_edge(text), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
