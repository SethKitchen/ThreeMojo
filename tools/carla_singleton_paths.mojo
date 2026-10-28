# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the rounded LINE singleton paths.

    carla_singleton_paths
    carla_singleton_paths --flags PATH

`--flags` reads the singleton paths, then compares each module path in
`PATH`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._singleton_paths import rounded_line_flags, singleton_paths


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_singleton_paths", file=stderr)
    exit(2)


def main() raises:
    """Print the rounded LINE singleton paths.

    Raises:
        Error: The command is invalid, or the path list cannot be read.
    """
    var arguments = argv()
    if len(arguments) == 3 and arguments[1] == "--flags":
        try:
            print(rounded_line_flags(Path(arguments[2]).read_text()), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 1:
        _usage()
    print(singleton_paths(), end="")
