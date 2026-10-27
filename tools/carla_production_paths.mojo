# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose production paths for the containing-model scan.

    carla_production_paths PATH

`PATH` is JSON with `roots` and `paths`. The program prints one boolean
per path.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._production_paths import production_paths


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_production_paths PATH", file=stderr)
    exit(2)


def main() raises:
    """Print which paths stay in the production scan.

    Raises:
        Error: The command is invalid, or the payload is missing a field.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(production_paths(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
