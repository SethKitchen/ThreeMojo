# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose a dispatch source or compare premise texts.

    carla_dispatch_source --choice PATH
    carla_dispatch_source --match PATH
    carla_dispatch_source --token-match PATH
    carla_dispatch_source --labeled PATH
    carla_dispatch_source --labeled-tokens PATH

`--choice` prints `current` or `restore`. `--match` prints `true` or
`false` for one pair. A list prints those results in order.
`--token-match` compares each source pair by its significant tokens.
`--labeled` reads the dispatch labels before those source choices.
`--labeled-tokens` checks the complete tokens when every choice is current.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import significant_match_flags
from tools._dispatch_source import (
    labeled_choices_then_tokens,
    labeled_source_choices,
    reviewed_source_choice,
    reviewed_source_choices,
    texts_match,
    texts_match_all,
)
from tools._python_json import PY_LIST, PyJson


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_dispatch_source --choice PATH | --match PATH |"
            " --token-match PATH | --labeled PATH | --labeled-tokens PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Choose one dispatch source or compare premise texts.

    Raises:
        Error: The command is invalid, or the source successor is unreviewed.
    """
    var arguments = argv()
    if len(arguments) != 3:
        _usage()
    var mode = arguments[1]
    if (
        mode != "--choice"
        and mode != "--match"
        and mode != "--token-match"
        and mode != "--labeled"
        and mode != "--labeled-tokens"
    ):
        _usage()
    try:
        var text = Path(arguments[2]).read_text()
        if mode == "--labeled-tokens":
            print(labeled_choices_then_tokens(text), end="")
            return
        if mode == "--labeled":
            print(labeled_source_choices(text), end="")
            return
        if mode == "--token-match":
            print(significant_match_flags(text), end="")
            return
        var doc = PyJson.parse(text)
        if doc.kind(doc.root) == PY_LIST:
            if mode == "--choice":
                print(reviewed_source_choices(text), end="")
            else:
                print(texts_match_all(text), end="")
        elif mode == "--choice":
            print(reviewed_source_choice(text), end="")
        else:
            print(texts_match(text), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
