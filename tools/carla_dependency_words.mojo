# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the stored-word check for each dependency.

    carla_dependency_words PATH
    carla_dependency_words --checked PATH

`PATH` is the dependency JSON. One object prints `match`, `trig`, or
`geometry`. A list prints those names in order. `--checked` chooses
every dependency, then checks the selected stored words.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._dependency_words import (
    checked_dependency_words,
    dependency_word_choice,
    dependency_word_choices,
)
from tools._python_json import PY_LIST, PyJson


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_dependency_words PATH | carla_dependency_words"
            " --checked PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Choose the dependency word checks.

    Raises:
        Error: The command is invalid, or a dependency is unreviewed.
    """
    var arguments = argv()
    if len(arguments) == 3 and arguments[1] == "--checked":
        try:
            checked_dependency_words(Path(arguments[2]).read_text())
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 2:
        _usage()
    try:
        var text = Path(arguments[1]).read_text()
        var doc = PyJson.parse(text)
        if doc.kind(doc.root) == PY_LIST:
            print(dependency_word_choices(text), end="")
        else:
            print(dependency_word_choice(text), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
