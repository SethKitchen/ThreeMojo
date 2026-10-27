# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Hash length-framed source bytes.

    carla_source_sha256 PATH

`PATH` is a length line and the exact bytes of each payload. The program
prints one SHA-256 digest per payload.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._framed_sha256 import framed_sha256


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_source_sha256 PATH", file=stderr)
    exit(2)


def main() raises:
    """Print one digest per framed payload.

    Raises:
        Error: The command is invalid, or a length line is invalid.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(framed_sha256(Path(arguments[1]).read_bytes()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
