# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Translate universal newlines.

    carla_universal_newlines PATH

`PATH` is a decoded text file. The program prints the translated text.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._universal_newlines import universal_newlines


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_universal_newlines PATH", file=stderr)
    exit(2)


def main() raises:
    """Translate one text file.

    Raises:
        Error: The command is invalid, or the file cannot be read.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        var data = Path(arguments[1]).read_bytes()
        print(universal_newlines(String(unsafe_from_utf8=data)), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
