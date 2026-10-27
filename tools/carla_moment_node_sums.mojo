# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the rounded stored-moment node sums.

    carla_moment_node_sums PATH

PATH is a JSON object of node and weight words. The command prints a
JSON list of exact fraction spellings.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_node_sums import moment_node_sums


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_moment_node_sums PATH", file=stderr)
    exit(2)


def main() raises:
    """Print the rounded node-sum fractions that match their pin.

    Raises:
        Error: The command is invalid, or a node-sum pin changed.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(moment_node_sums(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
