# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the runtime-support result.

    carla_runtime_support_result PATH

`PATH` holds the repository root and the check records. The program
prints the result.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._runtime_support_result import runtime_support_result


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_runtime_support_result PATH", file=stderr)
    exit(2)


def main() raises:
    """Print one runtime-support result.

    Raises:
        Error: The command is invalid, or a required field is missing.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(runtime_support_result(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
