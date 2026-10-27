# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Group stored-moment fraction texts by array.

    carla_moment_fractions PATH

PATH is a JSON object of array word groups. The command prints a JSON
object of exact fraction spellings.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_fractions import moment_fraction_groups


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_moment_fractions PATH", file=stderr)
    exit(2)


def main() raises:
    """Print the fraction spellings for each stored array.

    Raises:
        Error: The command is invalid, or a word is not a finite encoding.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(moment_fraction_groups(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
