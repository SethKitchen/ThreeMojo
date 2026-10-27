# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the frozen runtime-pin labels.

    carla_frozen_pin_labels
"""

from std.sys import argv, exit, stderr

from tools._frozen_pin_labels import frozen_pin_labels


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_frozen_pin_labels", file=stderr)
    exit(2)


def main():
    """Print the frozen runtime-pin labels."""
    if len(argv()) != 1:
        _usage()
    print(frozen_pin_labels(), end="")
