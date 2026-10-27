# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the stored-word check for one dependency.

    carla_dependency_words PATH

`PATH` is the dependency JSON. The program prints `match`, `trig`, or
`geometry`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._dependency_words import dependency_word_choice


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_dependency_words PATH", file=stderr)
    exit(2)


def main() raises:
    """Choose one dependency word check.

    Raises:
        Error: The command is invalid, or the dependency is unreviewed.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(dependency_word_choice(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
