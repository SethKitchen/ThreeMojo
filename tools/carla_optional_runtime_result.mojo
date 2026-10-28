# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the optional-runtime result.

    carla_optional_runtime_result PATH
    carla_optional_runtime_result --with-modules
    carla_optional_runtime_result --after-refusal PATH

`PATH` is JSON with `new_modules`. `--with-modules` reads the reviewed
module names first. The program prints the result.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._optional_runtime_result import (
    optional_runtime_result,
    optional_runtime_result_from_modules,
    try_only_then_result,
)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_optional_runtime_result PATH | --with-modules |"
            " --after-refusal PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print one optional-runtime result.

    Raises:
        Error: The command is invalid, or the module list is not a list.
    """
    var arguments = argv()
    if len(arguments) == 3 and arguments[1] == "--after-refusal":
        try:
            print(try_only_then_result(Path(arguments[2]).read_text()), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) == 2 and arguments[1] == "--with-modules":
        try:
            print(optional_runtime_result_from_modules(), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 2:
        _usage()
    try:
        print(optional_runtime_result(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
