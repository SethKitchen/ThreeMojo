# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the three inline sampled declarations.

    carla_sampled_declarations
"""

from std.sys import argv, exit, stderr

from tools._sampled_declarations import sampled_declarations


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_sampled_declarations", file=stderr)
    exit(2)


def main() raises:
    """Print the three sampled declarations.

    Raises:
        Error: The command is invalid, or a declaration cannot be written.
    """
    if len(argv()) != 1:
        _usage()
    try:
        print(sampled_declarations(), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
