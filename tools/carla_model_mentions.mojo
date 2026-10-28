# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Find watched model names in framed texts.

    carla_model_mentions NAMES TEXTS
    carla_model_mentions --named TEXTS COUNT

`NAMES` is a JSON list. `--named` reads the watched names first. `TEXTS`
is a length line and the exact bytes of each text. `COUNT` is the number
of texts. The program prints one boolean per text.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._model_mentions import model_mentions, named_model_mentions


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_model_mentions NAMES TEXTS", file=stderr)
    exit(2)


def _decimal(text: String) raises -> Int:
    """Read one decimal count.

    Args:
        text: The count argument.

    Returns:
        The count.

    Raises:
        Error: The count is empty or not decimal.
    """
    var data = text.as_bytes()
    if len(data) == 0:
        raise Error("invalid model text count")
    var value = 0
    var index = 0
    while index < len(data):
        var byte = data[index]
        if byte < 48 or byte > 57:
            raise Error("invalid model text count")
        value = value * 10 + Int(byte - 48)
        index += 1
    return value


def main() raises:
    """Print which texts contain a watched name.

    Raises:
        Error: The command is invalid, a text length is invalid, or the
            flag count differs.
    """
    var arguments = argv()
    if len(arguments) == 4 and arguments[1] == "--named":
        try:
            var data = Path(arguments[2]).read_bytes()
            var count = _decimal(arguments[3])
            print(
                named_model_mentions(String(unsafe_from_utf8=data), count),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 3:
        _usage()
    try:
        var names = Path(arguments[1]).read_text()
        var data = Path(arguments[2]).read_bytes()
        print(model_mentions(names, String(unsafe_from_utf8=data)), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
