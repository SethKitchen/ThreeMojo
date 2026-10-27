# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check a component path or return its basename.

    carla_component_path --confine PATH
    carla_component_path --base PATH

`--confine` reads JSON with `directory` and `names` and prints nothing
when every name stays inside the directory.
`--base` reads a path and prints the text after the last `/`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._posix_path import path_basename, require_component_names


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_component_path --confine PATH | --base PATH",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check component names or print one basename.

    Raises:
        Error: The command is invalid, or a component name escapes.
    """
    var arguments = argv()
    if len(arguments) != 3:
        _usage()
    var mode = arguments[1]
    if mode != "--confine" and mode != "--base":
        _usage()
    try:
        var data = Path(arguments[2]).read_bytes()
        var text = String(unsafe_from_utf8=data)
        if mode == "--base":
            print(path_basename(text), end="")
            return
        require_component_names(text)
    except error:
        print(String(error), file=stderr)
        exit(1)
