# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read every lane-control declaration.

    carla_lane_declarations PATH
    carla_lane_declarations --match PATH

PATH is a JSON list of declaration pins. The command prints a JSON list
of the declaration texts. `--match` prints whether each declaration has
the same significant tokens as `expected`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._lane_declarations import declaration_match_flags, lane_declarations


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_lane_declarations PATH | carla_lane_declarations"
            " --match PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print the declarations or their token comparisons.

    Raises:
        Error: The command is invalid, or a function cannot be read.
    """
    var arguments = argv()
    var compare = False
    var path = String("")
    if len(arguments) == 3 and arguments[1] == "--match":
        compare = True
        path = arguments[2]
    elif len(arguments) == 2:
        path = arguments[1]
    else:
        _usage()
    try:
        var text = Path(path).read_text()
        if compare:
            print(declaration_match_flags(text), end="")
        else:
            print(lane_declarations(text), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
