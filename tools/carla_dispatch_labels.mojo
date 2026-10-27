# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the dispatch path, choice names, and premise messages.

    carla_dispatch_labels
"""

from std.sys import argv, exit, stderr

from tools._dispatch_labels import dispatch_labels


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_dispatch_labels", file=stderr)
    exit(2)


def main():
    """Print the dispatch path, choice names, and premise messages."""
    if len(argv()) != 1:
        _usage()
    print(dispatch_labels(), end="")
