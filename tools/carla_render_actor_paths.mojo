# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the render-actor module and bound tests.

    carla_render_actor_paths
"""

from std.sys import argv, exit, stderr

from tools.carla_render_actor_gate import render_actor_paths


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_render_actor_paths", file=stderr)
    exit(2)


def main() raises:
    """Print the render-actor module and its three bound tests.

    Raises:
        Error: The command is invalid, or the lists cannot be written.
    """
    if len(argv()) != 1:
        _usage()
    try:
        print(render_actor_paths(), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
