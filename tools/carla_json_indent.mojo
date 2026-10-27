# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Write JSON with two-space indentation.

    carla_json_indent PATH

`PATH` is one JSON value. The program prints it as `json.dumps` does with
`indent=2`, without a final newline.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._carla_assets import dumps_indent
from tools._python_json import PyJson


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_json_indent PATH", file=stderr)
    exit(2)


def main() raises:
    """Print one JSON value with two-space indentation.

    Raises:
        Error: The command is invalid, or the file is not JSON.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        var doc = PyJson.parse(Path(arguments[1]).read_text())
        print(dumps_indent(doc, doc.root, 2), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
