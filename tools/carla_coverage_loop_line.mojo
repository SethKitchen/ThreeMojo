# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the one native-source line that contains a fragment.

    carla_coverage_loop_line FRAGMENT
"""

from std.sys import argv, exit, stderr

from tools._coverage_loop_lines import unique_source_line


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_coverage_loop_line FRAGMENT", file=stderr)
    exit(2)


def main() raises:
    """Print the line number of one unique source fragment.

    Raises:
        Error: The command is invalid, or the fragment is not unique.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(unique_source_line(arguments[1]))
    except error:
        print(String(error), file=stderr)
        exit(1)
