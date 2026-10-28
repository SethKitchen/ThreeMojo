# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the five reviewed cleanup premise lists.

    carla_cleanup_premises DIRECTORY
    carla_cleanup_premises --declared PATH
    carla_cleanup_premises --catalog PATH
    carla_cleanup_premises --catalog-migration PATH

`DIRECTORY` contains `sources.json` with `line`, `arc`, `bounds`, `center`,
and `outward`. `--declared` reads the declarations from the module sources
and then checks those five lists. `--catalog` reads the declaration catalog
before those premise checks.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._cleanup_premises import (
    catalog_then_frozen_migration,
    cleanup_catalog_premises,
    cleanup_declared_premises,
    prepare_cleanup_premises,
)
from tools.carla_cleanup_gate import cleanup_premises


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_cleanup_premises DIRECTORY | carla_cleanup_premises"
            " --declared PATH | carla_cleanup_premises --catalog PATH |"
            " carla_cleanup_premises --catalog-migration PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the five premise declarations.

    Raises:
        Error: The command is invalid, a function cannot be read, or a premise fragment changed.
    """
    var arguments = argv()
    if len(arguments) == 3 and arguments[1] == "--catalog-migration":
        try:
            print(
                catalog_then_frozen_migration(Path(arguments[2]).read_text()),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    var declared = String("")
    var catalog = String("")
    var directory = String("")
    if len(arguments) == 3 and arguments[1] == "--declared":
        declared = arguments[2]
    elif len(arguments) == 3 and arguments[1] == "--catalog":
        catalog = arguments[2]
    elif len(arguments) == 2:
        directory = arguments[1]
    else:
        _usage()
    try:
        if declared.byte_length() > 0:
            cleanup_declared_premises(Path(declared).read_text())
        elif catalog.byte_length() > 0:
            cleanup_catalog_premises(Path(catalog).read_text())
        else:
            prepare_cleanup_premises(directory)
            cleanup_premises(directory)
    except error:
        print(String(error), file=stderr)
        exit(1)
