# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read every lane-control declaration.

    carla_lane_declarations PATH
    carla_lane_declarations --match PATH
    carla_lane_declarations --texts PATH

PATH is a JSON list of declaration pins. The command prints a JSON list
of the declaration texts. `--match` prints whether each declaration has
the same significant tokens as `expected`. `--texts` prints the
declaration texts and the flags for items that include `expected`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._lane_declarations import (
    declaration_match_flags,
    declaration_texts_and_flags,
    lane_declarations,
)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_lane_declarations PATH | carla_lane_declarations"
            " --match PATH | carla_lane_declarations --texts PATH"
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
    var mode = String("declarations")
    var path = String("")
    if len(arguments) == 3 and arguments[1] == "--match":
        mode = "match"
        path = arguments[2]
    elif len(arguments) == 3 and arguments[1] == "--texts":
        mode = "texts"
        path = arguments[2]
    elif len(arguments) == 2:
        path = arguments[1]
    else:
        _usage()
    try:
        var text = Path(path).read_text()
        if mode == "match":
            print(declaration_match_flags(text), end="")
        elif mode == "texts":
            print(declaration_texts_and_flags(text), end="")
        else:
            print(lane_declarations(text), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
