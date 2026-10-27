# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the reviewed cleanup declarations.

    carla_cleanup_declarations
"""

from std.sys import argv, exit, stderr

from tools._cleanup_declarations import cleanup_declarations


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_cleanup_declarations", file=stderr)
    exit(2)


def main():
    """Print the reviewed cleanup declarations."""
    if len(argv()) != 1:
        _usage()
    print(cleanup_declarations(), end="")
