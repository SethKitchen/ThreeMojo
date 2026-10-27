# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the reviewed roundoff envelope.

    carla_roundoff_name PATH

The program prints the function name.
"""

from std.sys import argv, exit, stderr

from tools._roundoff_name import roundoff_envelope_name


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_roundoff_name PATH", file=stderr)
    exit(2)


def main() raises:
    """Print the roundoff envelope for one module path.

    Raises:
        Error: The command is invalid.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    print(roundoff_envelope_name(arguments[1]), end="")
