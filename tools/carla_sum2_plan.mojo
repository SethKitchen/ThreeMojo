# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Print the Sum2 module names and caller comparisons.

    carla_sum2_plan
    carla_sum2_plan --with-package

The plain command prints the Sum2 plan. `--with-package` reads that plan
before the package path.
"""

from std.sys import argv, exit, stderr

from tools._sum2_plan import sum2_plan, sum2_plan_with_package


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_sum2_plan | carla_sum2_plan --with-package",
        file=stderr,
    )
    exit(2)


def main():
    """Print the Sum2 plan, or the plan and the package path."""
    var arguments = argv()
    if len(arguments) == 2 and arguments[1] == "--with-package":
        print(sum2_plan_with_package(), end="")
        return
    if len(arguments) != 1:
        _usage()
    print(sum2_plan(), end="")
