# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Bind one optional-runtime group and check its edges.

    carla_semantic_step PATH

PATH is a JSON step. The command prints the new declaration texts.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._semantic_declarations import semantic_step


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_semantic_step PATH", file=stderr)
    exit(2)


def main() raises:
    """Print the declarations after the group's edges match.

    Raises:
        Error: The command is invalid, or the step fails.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(semantic_step(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
