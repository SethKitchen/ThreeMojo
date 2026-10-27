# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the coverage-invariant pin file names.

    carla_invariant_labels
"""

from std.sys import argv, exit, stderr

from tools._invariant_labels import invariant_labels


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_invariant_labels", file=stderr)
    exit(2)


def main():
    """Print the coverage-invariant pin file names."""
    if len(argv()) != 1:
        _usage()
    print(invariant_labels(), end="")
