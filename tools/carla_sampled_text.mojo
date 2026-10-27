# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Slice or rename one sampled declaration.

    carla_sampled_text --extract PATH --name NAME
    carla_sampled_text --rename PATH

The extract mode prints one top-level function. The rename mode prints the
declaration with sampled identifiers renamed. The caller supplies the source.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._sampled_value_gate import (
    extract_sampled_function,
    rename_sampled_identifiers,
)


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_sampled_text --extract PATH --name NAME | --rename PATH",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Slice or rename one sampled declaration.

    Raises:
        Error: The command is invalid, or the function is missing.
    """
    var extract = String("")
    var rename = String("")
    var name = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--extract" or word == "--rename" or word == "--name":
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--extract":
                extract = value
            elif word == "--rename":
                rename = value
            else:
                name = value
            index += 2
            continue
        _usage()
    var modes = 0
    if extract.byte_length() > 0:
        modes += 1
    if rename.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    if extract.byte_length() > 0 and name.byte_length() == 0:
        _usage()
    if rename.byte_length() > 0 and name.byte_length() > 0:
        _usage()
    try:
        if extract.byte_length() > 0:
            print(
                extract_sampled_function(Path(extract).read_text(), name),
                end="",
            )
            return
        print(rename_sampled_identifiers(Path(rename).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
