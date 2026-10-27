# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read every semantic declaration in one group.

    carla_semantic_declarations PATH

PATH is a JSON list of function pins. The command prints a JSON object
of the declarations.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._semantic_declarations import semantic_declarations


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_semantic_declarations PATH", file=stderr)
    exit(2)


def main() raises:
    """Print the declarations that match the requested functions.

    Raises:
        Error: The command is invalid, or a function cannot be read.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(semantic_declarations(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
