# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Project the copied sampled helpers.

    carla_sampled_projection PATH
    carla_sampled_projection --with-recipe PATH

PATH is JSON with `bounds` and `trig` source texts. The command prints
the projected helpers and the constant and lane statement dumps.
`--with-recipe` also prints the projection steps.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import PyJson
from tools._sampled_projection import (
    project_reviewed_helpers,
    project_with_recipe,
)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_sampled_projection PATH | carla_sampled_projection"
            " --with-recipe PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print the copied helpers and the value dispatchers.

    Raises:
        Error: The command is invalid, or a helper projection fails.
    """
    var arguments = argv()
    if len(arguments) == 3 and arguments[1] == "--with-recipe":
        try:
            print(project_with_recipe(Path(arguments[2]).read_text()), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 2:
        _usage()
    try:
        var doc = PyJson.parse(Path(arguments[1]).read_text())
        print(
            project_reviewed_helpers(
                doc.text(doc.at(doc.root, "bounds")),
                doc.text(doc.at(doc.root, "trig")),
            ),
            end="",
        )
    except error:
        print(String(error), file=stderr)
        exit(1)
