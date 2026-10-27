# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the optional-runtime result.

    carla_optional_runtime_result PATH

`PATH` is JSON with `new_modules`. The program prints the result.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._optional_runtime_result import optional_runtime_result


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_optional_runtime_result PATH", file=stderr)
    exit(2)


def main() raises:
    """Print one optional-runtime result.

    Raises:
        Error: The command is invalid, or the module list is not a list.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(optional_runtime_result(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
