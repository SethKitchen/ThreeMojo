# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the reviewed Sum2 import inventory.

    carla_sum2_imports --helpers PATH
    carla_sum2_imports --half PATH

`--helpers` reads JSON with `lane`, `bounds`, and `roundoff`.
`--half` reads JSON with `bounds` and `interval`.
The program prints nothing when the imports match.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import PyJson
from tools._sum2_helper_bindings import (
    sum2_half_import_checks,
    sum2_helper_import_checks,
)


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_sum2_imports --helpers PATH | --half PATH",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check one Sum2 import payload.

    Raises:
        Error: The command is invalid, or an import changed.
    """
    var helpers = String("")
    var half = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--helpers" or word == "--half":
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--helpers":
                helpers = value
            else:
                half = value
            index += 2
            continue
        _usage()
    if (helpers == "") == (half == ""):
        _usage()
    try:
        if helpers != "":
            var doc = PyJson.parse(Path(helpers).read_text())
            sum2_helper_import_checks(
                doc.text(doc.at(doc.root, "lane")),
                doc.text(doc.at(doc.root, "bounds")),
                doc.text(doc.at(doc.root, "roundoff")),
            )
            return
        var doc = PyJson.parse(Path(half).read_text())
        sum2_half_import_checks(
            doc.text(doc.at(doc.root, "bounds")),
            doc.text(doc.at(doc.root, "interval")),
        )
    except error:
        print(String(error), file=stderr)
        exit(1)
