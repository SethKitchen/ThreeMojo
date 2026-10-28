# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the sampled graph digests.

    carla_sampled_graph_pins
    carla_sampled_graph_pins --checked

`--checked` also checks the reference names and prints the closure.
"""

from std.sys import argv, exit, stderr

from tools._sampled_graph_pins import (
    sampled_graph_pins,
    sampled_graphs_and_names,
)


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_sampled_graph_pins | carla_sampled_graph_pins --checked",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print the reference, primitive, and shared graph digests.

    Raises:
        Error: The command is invalid, or the reference names differ.
    """
    var arguments = argv()
    if len(arguments) == 2 and arguments[1] == "--checked":
        try:
            print(sampled_graphs_and_names(), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 1:
        _usage()
    print(sampled_graph_pins(), end="")
