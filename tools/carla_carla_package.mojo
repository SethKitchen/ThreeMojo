# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the CARLA extension package path.

    carla_carla_package
"""

from std.sys import argv, exit, stderr

from tools._carla_package import carla_package


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_carla_package", file=stderr)
    exit(2)


def main():
    """Print the CARLA extension package path."""
    if len(argv()) != 1:
        _usage()
    print(carla_package(), end="")
