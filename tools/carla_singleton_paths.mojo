# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the rounded LINE singleton paths.

    carla_singleton_paths
"""

from std.sys import argv, exit, stderr

from tools._singleton_paths import singleton_paths


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_singleton_paths", file=stderr)
    exit(2)


def main():
    """Print the rounded LINE singleton paths."""
    if len(argv()) != 1:
        _usage()
    print(singleton_paths(), end="")
