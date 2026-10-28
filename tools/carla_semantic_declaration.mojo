# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Return one semantic declaration without move sigils.

    carla_semantic_declaration PATH NAME

PATH is a module. NAME is one top-level function. The command prints that
declaration after removing postfix `^` move sigils.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import semantic_declaration
from tools._optional_runtime_messages import prefix_move_error


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_semantic_declaration PATH NAME", file=stderr)
    exit(2)


def main() raises:
    """Print one declaration without move sigils.

    Raises:
        Error: The command is invalid, or the function cannot be read.
    """
    var arguments = argv()
    if len(arguments) != 3:
        _usage()
    try:
        print(
            semantic_declaration(Path(arguments[1]).read_text(), arguments[2]),
            end="",
        )
    except error:
        print(prefix_move_error(String(error)), file=stderr)
        exit(1)
