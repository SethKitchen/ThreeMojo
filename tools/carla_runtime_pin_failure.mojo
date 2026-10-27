# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Decide whether a frozen runtime-pin failure is relabeled.

    carla_runtime_pin_failure PATH

`PATH` is the decision JSON. The program prints `raise`, `cause`, or
`relabel`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._runtime_pin_failure import runtime_pin_relabel


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_runtime_pin_failure PATH", file=stderr)
    exit(2)


def main() raises:
    """Print the runtime-pin failure decision.

    Raises:
        Error: The command is invalid, or the stage is unknown.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(runtime_pin_relabel(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
