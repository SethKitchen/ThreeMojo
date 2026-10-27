# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the ideal half projection.

    carla_moment_projection PATH

PATH is a JSON object. The direct form has `legacy`, `current`, and
`helper`. The Sum2 form has `bounds` and selects the spiral from that
module. The command prints the projection record.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_projection import moment_projection, moment_sum2_projection
from tools._python_json import MISSING, PyJson


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_moment_projection PATH", file=stderr)
    exit(2)


def main() raises:
    """Print the ideal projection record when the spirals match.

    Raises:
        Error: The command is invalid, or the projection changed.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        var text = Path(arguments[1]).read_text()
        var doc = PyJson.parse(text)
        if doc.get(doc.root, "bounds") == MISSING:
            print(moment_projection(text), end="")
        else:
            print(moment_sum2_projection(text), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
