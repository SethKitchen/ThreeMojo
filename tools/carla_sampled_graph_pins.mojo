# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the sampled graph digests.

    carla_sampled_graph_pins
"""

from std.sys import argv, exit, stderr

from tools._sampled_graph_pins import sampled_graph_pins


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_sampled_graph_pins", file=stderr)
    exit(2)


def main():
    """Print the reference, primitive, and shared graph digests."""
    if len(argv()) != 1:
        _usage()
    print(sampled_graph_pins(), end="")
