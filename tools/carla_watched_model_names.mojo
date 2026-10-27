# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the watched model and removed search names.

    carla_watched_model_names
"""

from std.sys import argv, exit, stderr

from tools._watched_model_names import watched_model_names


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_watched_model_names", file=stderr)
    exit(2)


def main() raises:
    """Print the watched names.

    Raises:
        Error: The command is invalid, or the list cannot be written.
    """
    if len(argv()) != 1:
        _usage()
    try:
        print(watched_model_names(), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
