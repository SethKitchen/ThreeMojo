# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Classify a stored-moment decimal word or constant error.

    carla_moment_errors --signed PATH
    carla_moment_errors --result PATH
    carla_moment_errors --constant PATH
    carla_moment_errors --classified PATH

The program prints the decision.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_errors import (
    classified_decimal_word,
    constant_error_text,
    decimal_word_result,
    signed_zero_word,
)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_moment_errors --signed PATH | --result PATH |"
            " --constant PATH | --classified PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Classify one decimal word or constant error.

    Raises:
        Error: The command is invalid, or the word result is refused.
    """
    var arguments = argv()
    if len(arguments) != 3:
        _usage()
    var mode = arguments[1]
    if (
        mode != "--signed"
        and mode != "--result"
        and mode != "--constant"
        and mode != "--classified"
    ):
        _usage()
    try:
        var text = Path(arguments[2]).read_text()
        if mode == "--signed":
            print(signed_zero_word(text), end="")
        elif mode == "--result":
            print(decimal_word_result(text), end="")
        elif mode == "--classified":
            print(classified_decimal_word(text), end="")
        else:
            print(constant_error_text(text), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
