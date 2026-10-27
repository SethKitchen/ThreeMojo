# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Extend runtime-boundary edges from reviewed view steps.

    carla_runtime_edge PATH

`PATH` is one edge or several edges that share `steps`. One edge prints
its decision. Several edges print those decisions in order.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import MISSING, PyJson
from tools._runtime_edge import extend_runtime_edge, extend_runtime_edges


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_runtime_edge PATH", file=stderr)
    exit(2)


def main() raises:
    """Extend the runtime-boundary edges.

    Raises:
        Error: The command is invalid, or a step is incomplete.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        var text = Path(arguments[1]).read_text()
        var doc = PyJson.parse(text)
        if doc.get(doc.root, "items") == MISSING:
            print(extend_runtime_edge(text), end="")
        else:
            print(extend_runtime_edges(text), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
