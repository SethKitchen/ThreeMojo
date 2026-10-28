# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Project the copied sampled helpers.

    carla_sampled_projection PATH
    carla_sampled_projection --with-recipe PATH
    carla_sampled_projection --after-imports PATH
    carla_sampled_projection --after-top-level PATH

PATH is JSON with `bounds` and `trig` source texts. The command prints
the projected helpers and the constant and lane statement dumps.
`--with-recipe` also prints the copy plan and the projection steps.
`--after-imports` checks the lane-value imports before that projection.
`--after-top-level` checks the helper names after that projection.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import PyJson
from tools._sampled_projection import (
    project_after_imports,
    project_after_top_level,
    project_reviewed_helpers,
    project_with_recipe,
)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_sampled_projection PATH | --with-recipe PATH |"
            " --after-imports PATH | --after-top-level PATH"
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
    if len(arguments) == 3 and arguments[1] == "--after-top-level":
        try:
            print(
                project_after_top_level(Path(arguments[2]).read_text()),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) == 3 and arguments[1] == "--after-imports":
        try:
            print(project_after_imports(Path(arguments[2]).read_text()), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
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
