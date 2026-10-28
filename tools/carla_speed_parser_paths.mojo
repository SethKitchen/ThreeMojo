# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the speed-parser module and tests.

    carla_speed_parser_paths
    carla_speed_parser_paths --with-migration

`--with-migration` reads the module paths before the migration record.
"""

from std.sys import argv, exit, stderr

from tools.carla_speed_gate import (
    speed_parser_paths,
    speed_paths_with_migration,
)


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_speed_parser_paths", file=stderr)
    exit(2)


def main() raises:
    """Print the speed-limit module and its two correctness tests.

    Raises:
        Error: The command is invalid, or the lists cannot be written.
    """
    var arguments = argv()
    if len(arguments) == 2 and arguments[1] == "--with-migration":
        try:
            print(speed_paths_with_migration(), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 1:
        _usage()
    try:
        print(speed_parser_paths(), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
