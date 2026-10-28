# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the coverage-invariant pin file names.

    carla_invariant_labels
    carla_invariant_labels --with-migration

`--with-migration` reads the labels before the migration record.
"""

from std.sys import argv, exit, stderr

from tools._invariant_labels import (
    invariant_labels,
    invariant_labels_with_migration,
)


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_invariant_labels", file=stderr)
    exit(2)


def main() raises:
    """Print the coverage-invariant pin file names.

    Raises:
        Error: The command is invalid, or the migration record cannot be read.
    """
    var arguments = argv()
    if len(arguments) == 2 and arguments[1] == "--with-migration":
        try:
            print(invariant_labels_with_migration(), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 1:
        _usage()
    print(invariant_labels(), end="")
