# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the optional-runtime module names.

    carla_optional_runtime_modules
"""

from std.sys import argv, exit, stderr

from tools._optional_runtime_modules import optional_runtime_modules


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_optional_runtime_modules", file=stderr)
    exit(2)


def main() raises:
    """Print the five optional-runtime module names.

    Raises:
        Error: The command is invalid, or the list cannot be written.
    """
    if len(argv()) != 1:
        _usage()
    try:
        print(optional_runtime_modules(), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
