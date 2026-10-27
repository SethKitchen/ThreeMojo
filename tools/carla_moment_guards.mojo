# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check one stored-moment guard.

    carla_moment_guards --count PATH
    carla_moment_guards --names PATH
    carla_moment_guards --output PATH

`PATH` is the JSON payload for that guard. The program prints nothing
when the guard matches.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_guards import (
    require_member,
    require_name_set,
    require_same_count,
    require_separate_output,
)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_moment_guards --count PATH | --names PATH | --member"
            " PATH | --output PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check one stored-moment guard.

    Raises:
        Error: The command is invalid, or the guard failed.
    """
    var arguments = argv()
    if len(arguments) != 3:
        _usage()
    var mode = arguments[1]
    if (
        mode != "--count"
        and mode != "--names"
        and mode != "--member"
        and mode != "--output"
    ):
        _usage()
    try:
        var text = Path(arguments[2]).read_text()
        if mode == "--count":
            require_same_count(text)
        elif mode == "--names":
            require_name_set(text)
        elif mode == "--member":
            require_member(text)
        else:
            require_separate_output(text)
    except error:
        print(String(error), file=stderr)
        exit(1)
