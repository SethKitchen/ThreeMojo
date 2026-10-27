# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the ideal half projection.

    carla_moment_projection PATH

PATH is a JSON object with the legacy spiral, the live spiral, and the
stored-half helper. The command prints the projection record.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_projection import moment_projection


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
        print(moment_projection(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
