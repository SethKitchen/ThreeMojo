# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the stored-moment report.

    carla_moment_report META PIN PIN PIN

`META` is the report inputs as JSON. Each `PIN` is one pin file. The
program prints the report JSON when the payload size and pin count match.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_report import moment_report


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_moment_report META PIN PIN PIN", file=stderr)
    exit(2)


def _owned(data: Span[UInt8, _]) -> List[UInt8]:
    """Copy raw file bytes.

    Args:
        data: The file bytes.

    Returns:
        An owned copy.
    """
    var out = List[UInt8]()
    for byte in data:
        out.append(byte)
    return out^


def main() raises:
    """Build one stored-moment report.

    Raises:
        Error: The command is invalid, or the report check failed.
    """
    var arguments = argv()
    if len(arguments) < 2:
        _usage()
    var pins = List[List[UInt8]]()
    var index = 2
    while index < len(arguments):
        pins.append(_owned(Path(arguments[index]).read_bytes()))
        index += 1
    try:
        print(moment_report(Path(arguments[1]).read_text(), pins), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
