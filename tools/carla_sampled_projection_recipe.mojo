# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the sampled projection recipe.

    carla_sampled_projection_recipe
"""

from std.sys import argv, exit, stderr

from tools._sampled_projection_recipe import sampled_projection_recipe


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_sampled_projection_recipe", file=stderr)
    exit(2)


def main():
    """Print the sampled projection recipe."""
    if len(argv()) != 1:
        _usage()
    print(sampled_projection_recipe(), end="")
