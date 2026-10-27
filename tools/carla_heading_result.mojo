# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the fresh heading correspondence result.

    carla_heading_result PATH

`PATH` is JSON with integer `consumers`. The program prints the result.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._heading_result import heading_result


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_heading_result PATH", file=stderr)
    exit(2)


def main() raises:
    """Print one heading correspondence result.

    Raises:
        Error: The command is invalid, or the consumer count is not an
            integer.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(heading_result(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
