# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the selection contract path and the predecessor messages.

    carla_selection_labels
"""

from std.sys import argv, exit, stderr

from tools._selection_labels import selection_labels


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_selection_labels", file=stderr)
    exit(2)


def main():
    """Print the selection contract path and the predecessor messages."""
    if len(argv()) != 1:
        _usage()
    print(selection_labels(), end="")
