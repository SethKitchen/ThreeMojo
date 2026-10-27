# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Replace the first occurrence in each text.

    carla_replace_firsts PATH

`PATH` is a JSON list. Each item has `source`, `old`, and `new`. The
program prints the replaced texts in order.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import replace_firsts


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_replace_firsts PATH", file=stderr)
    exit(2)


def main() raises:
    """Print every replaced text.

    Raises:
        Error: The command is invalid, or an item is missing a field.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(replace_firsts(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
