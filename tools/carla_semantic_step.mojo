# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Bind one optional-runtime group and check its edges.

    carla_semantic_step PATH
    carla_semantic_step --with-contract PATH

PATH is one step or several steps. One step prints its declarations.
Several steps print an empty object after every group matches.
`--with-contract` reads the contract messages before those steps.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import MISSING, PyJson
from tools._semantic_declarations import (
    semantic_step,
    semantic_steps,
    semantic_steps_with_contract,
)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_semantic_step PATH | carla_semantic_step"
            " --with-contract PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print the declarations after the group's edges match.

    Raises:
        Error: The command is invalid, or the step fails.
    """
    var arguments = argv()
    if len(arguments) == 3 and arguments[1] == "--with-contract":
        try:
            print(
                semantic_steps_with_contract(Path(arguments[2]).read_text()),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 2:
        _usage()
    try:
        var text = Path(arguments[1]).read_text()
        var doc = PyJson.parse(text)
        if doc.get(doc.root, "steps") == MISSING:
            print(semantic_step(text), end="")
        else:
            print(semantic_steps(text), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
