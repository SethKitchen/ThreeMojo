# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the diagnostic rows for one module's loop lines.

    carla_diagnostic_manifest MANIFEST MODULE LINE [LINE...]

The program reads the manifest it is given. It does not change that file.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools.check_coverage_loop_fixture import diagnostic_manifest


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_diagnostic_manifest MANIFEST MODULE LINE [LINE...]",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print the selected manifest rows.

    Raises:
        Error: The command is invalid, or a requested loop line is missing.
    """
    var arguments = argv()
    if len(arguments) < 4:
        _usage()
    var lines = List[Int]()
    var index = 3
    while index < len(arguments):
        lines.append(Int(arguments[index]))
        index += 1
    try:
        print(
            diagnostic_manifest(
                Path(arguments[1]).read_text(), arguments[2], lines
            ),
            end="",
        )
    except error:
        print(String(error), file=stderr)
        exit(1)
