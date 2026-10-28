# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check observed containing-model consumers.

    carla_optional_consumers PATH
    carla_optional_consumers --mentioned TEXTS PATHS COUNT

`PATH` is a JSON list of `path` and `text` objects. `--mentioned` reads
the watched names, then checks the framed texts whose paths are in
`PATHS`. `COUNT` is the number of texts. The program prints nothing when
the observed modules keep the reviewed names out.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._optional_model_consumers import (
    mentioned_consumers,
    require_observed_consumers,
)


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_optional_consumers PATH", file=stderr)
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
    """Check one list of observed modules.

    Raises:
        Error: The command is invalid, a text length is invalid, or a
            module names a reviewed helper.
    """
    var arguments = argv()
    if len(arguments) == 5 and arguments[1] == "--mentioned":
        try:
            var data = Path(arguments[2]).read_bytes()
            var paths = Path(arguments[3]).read_text()
            var count = _decimal(arguments[4])
            mentioned_consumers(String(unsafe_from_utf8=data), paths, count)
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 2:
        _usage()
    try:
        require_observed_consumers(Path(arguments[1]).read_text())
    except error:
        print(String(error), file=stderr)
        exit(1)
