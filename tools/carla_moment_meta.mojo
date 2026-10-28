# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the stored-moment report meta.

    carla_moment_meta PATH
    carla_moment_meta --rows PATH

`PATH` is JSON with the payload, the root, the projection, the dependency
scope, and the routing and block pins. `--rows` builds that payload from
the derived rows first. The program prints the meta.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_report import moment_meta, moment_meta_from_rows


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_moment_meta PATH | carla_moment_meta --rows PATH",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print one stored-moment report meta.

    Raises:
        Error: The command is invalid, or a required field is missing.
    """
    var arguments = argv()
    if len(arguments) == 3 and arguments[1] == "--rows":
        try:
            print(moment_meta_from_rows(Path(arguments[2]).read_text()), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 2:
        _usage()
    try:
        print(moment_meta(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
