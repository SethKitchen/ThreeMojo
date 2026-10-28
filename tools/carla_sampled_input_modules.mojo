# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the sampled input modules.

    carla_sampled_input_modules
    carla_sampled_input_modules --plan
    carla_sampled_input_modules --plan-graphs

The plain command prints the four module names. `--plan` reads those
modules before the package path. `--plan-graphs` reads the graph pins
after that package path.
"""

from std.sys import argv, exit, stderr

from tools._sampled_input_modules import (
    sampled_input_modules,
    sampled_input_plan,
    sampled_plan_then_graphs,
)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_sampled_input_modules | carla_sampled_input_modules"
            " --plan | carla_sampled_input_modules --plan-graphs"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print the four sampled input modules, or the modules and package.

    Raises:
        Error: The reference names differ from the graph digest keys.
    """
    var arguments = argv()
    if len(arguments) == 2 and arguments[1] == "--plan-graphs":
        try:
            print(sampled_plan_then_graphs(), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) == 2 and arguments[1] == "--plan":
        print(sampled_input_plan(), end="")
        return
    if len(arguments) != 1:
        _usage()
    print(sampled_input_modules(), end="")
