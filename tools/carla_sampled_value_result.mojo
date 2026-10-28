# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the sampled-value result.

    carla_sampled_value_result PATH
    carla_sampled_value_result --framed FRAME META

`PATH` is JSON with the measured counts and the copied records. The program
prints the result. `--framed` hashes `FRAME` before that result. `META`
names each source.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._sampled_value_result import (
    sampled_result_from_frame,
    sampled_value_result,
)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_sampled_value_result PATH |"
            " carla_sampled_value_result --framed FRAME META"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print one sampled-value result.

    Raises:
        Error: The command is invalid, or a field has the wrong type.
    """
    var arguments = argv()
    if len(arguments) == 4 and arguments[1] == "--framed":
        try:
            print(
                sampled_result_from_frame(
                    Path(arguments[2]).read_bytes(),
                    Path(arguments[3]).read_text(),
                ),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 2:
        _usage()
    try:
        print(sampled_value_result(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
