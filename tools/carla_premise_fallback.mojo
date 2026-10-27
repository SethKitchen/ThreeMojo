# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the Map seed or lane predecessor.

    carla_premise_fallback PATH

`PATH` is JSON with `matched`, `path`, `name`, and `owner`. The program
prints `none`, `seed`, or `lane`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._premise_fallback import premise_fallback


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_premise_fallback PATH", file=stderr)
    exit(2)


def main() raises:
    """Print the premise predecessor choice.

    Raises:
        Error: The command is invalid, or a required field is missing.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(premise_fallback(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
