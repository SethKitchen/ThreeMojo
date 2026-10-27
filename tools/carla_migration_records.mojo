# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the reviewed migration paths and digests.

    carla_migration_records
"""

from std.sys import argv, exit, stderr

from tools._migration_records import migration_records


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_migration_records", file=stderr)
    exit(2)


def main():
    """Print the reviewed migration paths and digests."""
    if len(argv()) != 1:
        _usage()
    print(migration_records(), end="")
