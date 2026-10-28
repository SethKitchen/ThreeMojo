# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the fresh producer and the lane-search edges.

    carla_runtime_search_edges SOURCE NAME MODE
    carla_runtime_search_edges --after-declaration PATH NAME

`SOURCE` is the run declaration. `MODE` is `fresh` or `search`.
`--after-declaration` reads the declaration in `PATH` before the search
edges. `NAME` is the run function.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_expr import require_fragment_checks
from tools._optional_runtime_edges import search_edge_payload
from tools._optional_runtime_messages import prefix_fragment_error
from tools._search_declaration import search_edges_after_declaration


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_runtime_search_edges SOURCE NAME MODE",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check one run declaration's fresh or search edges.

    Raises:
        Error: The command is invalid, or a fragment check fails.
    """
    var arguments = argv()
    if len(arguments) == 4 and arguments[1] == "--after-declaration":
        try:
            search_edges_after_declaration(
                Path(arguments[2]).read_text(), arguments[3]
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 4:
        _usage()
    try:
        require_fragment_checks(
            search_edge_payload(
                Path(arguments[1]).read_text(), arguments[2], arguments[3]
            )
        )
    except error:
        print(prefix_fragment_error(String(error)), file=stderr)
        exit(1)
