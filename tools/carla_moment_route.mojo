# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check one stored-moment routing document.

    carla_moment_route PATH

PATH is JSON. `mode` is `current` or `accept`. `current` needs `source`
and prints the live routing document. `accept` needs `current`,
`expected`, `message`, and `strip`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_route import moment_route_accept, moment_route_current
from tools._python_json import PyJson


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_moment_route PATH", file=stderr)
    exit(2)


def main() raises:
    """Check one routing pin, or accept the live routing document.

    Raises:
        Error: The command is invalid, or the routing check fails.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        var doc = PyJson.parse(Path(arguments[1]).read_text())
        var mode = doc.text(doc.at(doc.root, "mode"))
        if mode == "current":
            print(
                moment_route_current(doc.text(doc.at(doc.root, "source"))),
                end="",
            )
            return
        if mode == "accept":
            moment_route_accept(
                doc.text(doc.at(doc.root, "current")),
                doc.text(doc.at(doc.root, "expected")),
                doc.text(doc.at(doc.root, "message")),
                doc.flag(doc.at(doc.root, "strip")),
            )
            return
        _usage()
    except error:
        print(String(error), file=stderr)
        exit(1)
