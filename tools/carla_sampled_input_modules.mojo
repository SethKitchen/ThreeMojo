# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the sampled input modules.

    carla_sampled_input_modules
    carla_sampled_input_modules --plan

The plain command prints the four module names. `--plan` reads those
modules before the package path.
"""

from std.sys import argv, exit, stderr

from tools._sampled_input_modules import (
    sampled_input_modules,
    sampled_input_plan,
)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_sampled_input_modules | carla_sampled_input_modules"
            " --plan"
        ),
        file=stderr,
    )
    exit(2)


def main():
    """Print the four sampled input modules, or the modules and package."""
    var arguments = argv()
    if len(arguments) == 2 and arguments[1] == "--plan":
        print(sampled_input_plan(), end="")
        return
    if len(arguments) != 1:
        _usage()
    print(sampled_input_modules(), end="")
