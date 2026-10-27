# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the moment pin file, table, and word count.

    carla_moment_files
"""

from std.sys import argv, exit, stderr

from tools.carla_moment_gate import moment_files


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_moment_files", file=stderr)
    exit(2)


def main():
    """Print the pin file, the stored table, and the word count."""
    if len(argv()) != 1:
        _usage()
    print(moment_files(), end="")
