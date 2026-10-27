# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the checker failure prefixes.

    carla_cli_failures
"""

from std.sys import argv, exit, stderr

from tools._cli_failures import cli_failures


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_cli_failures", file=stderr)
    exit(2)


def main():
    """Print the checker failure prefixes."""
    if len(argv()) != 1:
        _usage()
    print(cli_failures(), end="")
