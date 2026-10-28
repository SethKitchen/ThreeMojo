# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the reviewed cleanup declarations.

    carla_cleanup_declarations
    carla_cleanup_declarations --after PATH --sha HEX

The plain command prints the declaration catalog. `--after` checks the
guard-pin digest before that catalog.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._cleanup_declarations import (
    cleanup_declarations,
    cleanup_declarations_after_digest,
)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_cleanup_declarations | carla_cleanup_declarations"
            " --after PATH --sha HEX"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print the declaration catalog, or the catalog after the guard digest.

    Raises:
        Error: The command is invalid, or the guard-pin digest changed.
    """
    var arguments = argv()
    if (
        len(arguments) == 5
        and arguments[1] == "--after"
        and arguments[3] == "--sha"
    ):
        try:
            print(
                cleanup_declarations_after_digest(
                    Path(arguments[2]).read_bytes(), arguments[4]
                ),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 1:
        _usage()
    print(cleanup_declarations(), end="")
