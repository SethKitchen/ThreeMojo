# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the sampled reference names and the closure groups.

    carla_sampled_closure
"""

from std.sys import argv, exit, stderr

from tools._sampled_closure import sampled_closure


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_sampled_closure", file=stderr)
    exit(2)


def main():
    """Print the sampled reference names and the closure groups."""
    if len(argv()) != 1:
        _usage()
    print(sampled_closure(), end="")
