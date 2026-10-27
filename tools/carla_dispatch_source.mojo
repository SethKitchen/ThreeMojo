# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose a dispatch source or compare premise texts.

    carla_dispatch_source --choice PATH
    carla_dispatch_source --match PATH

`--choice` prints `current` or `restore`. `--match` prints `true` or
`false` for one pair. A list prints those flags in order.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._dispatch_source import (
    reviewed_source_choice,
    texts_match,
    texts_match_all,
)
from tools._python_json import PY_LIST, PyJson


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_dispatch_source --choice PATH | --match PATH",
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
    if mode != "--choice" and mode != "--match":
        _usage()
    try:
        var text = Path(arguments[2]).read_text()
        if mode == "--choice":
            print(reviewed_source_choice(text), end="")
        else:
            var doc = PyJson.parse(text)
            if doc.kind(doc.root) == PY_LIST:
                print(texts_match_all(text), end="")
            else:
                print(texts_match(text), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
