# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Find watched model names in framed texts.

    carla_model_mentions NAMES TEXTS

`NAMES` is a JSON list. `TEXTS` is a length line and the exact bytes of
each text. The program prints one boolean per text.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._model_mentions import model_mentions


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_model_mentions NAMES TEXTS", file=stderr)
    exit(2)


def main() raises:
    """Print which texts contain a watched name.

    Raises:
        Error: The command is invalid, or a text length is invalid.
    """
    var arguments = argv()
    if len(arguments) != 3:
        _usage()
    try:
        var names = Path(arguments[1]).read_text()
        var data = Path(arguments[2]).read_bytes()
        print(model_mentions(names, String(unsafe_from_utf8=data)), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
