# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the companion migration record paths.

    carla_record_paths
"""

from std.sys import argv, exit, stderr

from tools._record_paths import record_paths


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_record_paths", file=stderr)
    exit(2)


def main():
    """Print the companion migration record paths."""
    if len(argv()) != 1:
        _usage()
    print(record_paths(), end="")
