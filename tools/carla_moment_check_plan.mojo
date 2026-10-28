# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the moment dependency record and the check messages.

    carla_moment_check_plan
    carla_moment_check_plan --with-files
"""

from std.sys import argv, exit, stderr

from tools._moment_check_plan import moment_check_plan
from tools.carla_moment_gate import moment_files


def moment_plan_with_files() -> String:
    """Read the moment check plan, then the pin file, table, and word count.

    Returns:
        JSON. `plan` is the check plan. `files` holds the pin file, the
        stored table, and the word count.
    """
    return '{"plan":' + moment_check_plan() + ',"files":' + moment_files() + "}"


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_moment_check_plan [--with-files]",
        file=stderr,
    )
    exit(2)


def main():
    """Print the moment dependency record and the check messages."""
    var arguments = argv()
    if len(arguments) == 2 and arguments[1] == "--with-files":
        print(moment_plan_with_files(), end="")
        return
    if len(arguments) != 1:
        _usage()
    print(moment_check_plan(), end="")
