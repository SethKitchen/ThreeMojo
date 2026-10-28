# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose production paths for the containing-model scan.

    carla_production_paths PATH
    carla_production_paths --reviewed PATHS COUNT
    carla_production_paths --scan ROOT

`PATH` is JSON with `roots` and `paths`. `--reviewed` reads the
non-production roots first. `PATHS` is a JSON list of relative paths.
`COUNT` is the number of paths. The program prints one boolean per path.
`--scan` lists the kept Mojo files under `ROOT` in path-part order.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._production_paths import (
    production_paths,
    production_scan,
    reviewed_production_paths,
)


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_production_paths PATH", file=stderr)
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
        raise Error("invalid production path count")
    var value = 0
    var index = 0
    while index < len(data):
        var byte = data[index]
        if byte < 48 or byte > 57:
            raise Error("invalid production path count")
        value = value * 10 + Int(byte - 48)
        index += 1
    return value


def main() raises:
    """Print which paths stay in the production scan.

    Raises:
        Error: The command is invalid, or the payload is missing a field.
    """
    var arguments = argv()
    if len(arguments) == 3 and arguments[1] == "--scan":
        try:
            print(production_scan(arguments[2]), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) == 4 and arguments[1] == "--reviewed":
        try:
            var paths = Path(arguments[2]).read_text()
            var count = _decimal(arguments[3])
            print(reviewed_production_paths(paths, count), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 2:
        _usage()
    try:
        print(production_paths(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
