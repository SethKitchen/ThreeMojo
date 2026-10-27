# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the sampled input modules.

    carla_sampled_input_modules
"""

from std.sys import argv, exit, stderr

from tools._sampled_input_modules import sampled_input_modules


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_sampled_input_modules", file=stderr)
    exit(2)


def main():
    """Print the four sampled input modules."""
    if len(argv()) != 1:
        _usage()
    print(sampled_input_modules(), end="")
