# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Copy the consumer prefix before the first definition.

    carla_import_scopes PATH

`PATH` is a JSON list of module texts. The program prints those prefixes
in order.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import import_scope_prefixes


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_import_scopes PATH", file=stderr)
    exit(2)


def main() raises:
    """Print every consumer import scope.

    Raises:
        Error: The command is invalid, or an item is not a string.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(import_scope_prefixes(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
