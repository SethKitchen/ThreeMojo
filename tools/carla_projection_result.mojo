# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the ideal-projection result or require source text.

    carla_projection_result --record PATH
    carla_projection_result --text PATH

`--record` reads a digest and prints the result JSON.
`--text` reads JSON with `text` and `message` and prints nothing when
`text` is a string.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._projection_result import projection_result, require_source_text


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_projection_result --record PATH | --text PATH",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print one projection result or require one source string.

    Raises:
        Error: The command is invalid, or the source text is not a string.
    """
    var arguments = argv()
    if len(arguments) != 3:
        _usage()
    var mode = arguments[1]
    if mode != "--record" and mode != "--text":
        _usage()
    try:
        var text = Path(arguments[2]).read_text()
        if mode == "--record":
            print(projection_result(text), end="")
            return
        require_source_text(text)
    except error:
        print(String(error), file=stderr)
        exit(1)
