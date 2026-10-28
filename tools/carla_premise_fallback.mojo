# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the Map seed or lane predecessor.

    carla_premise_fallback PATH

`PATH` is one premise or a list of premises. One premise prints `none`,
`seed`, or `lane`. A list prints those choices in order.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._premise_fallback import premise_fallback, premise_fallbacks
from tools._python_json import PY_LIST, PyJson


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_premise_fallback PATH", file=stderr)
    exit(2)


def main() raises:
    """Print each premise predecessor choice.

    Raises:
        Error: The command is invalid, or a required field is missing.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        var text = Path(arguments[1]).read_text()
        var doc = PyJson.parse(text)
        if doc.kind(doc.root) == PY_LIST:
            print(premise_fallbacks(text), end="")
        else:
            print(premise_fallback(text), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
