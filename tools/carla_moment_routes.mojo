# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check every stored-moment route.

    carla_moment_routes --digests PATH
    carla_moment_routes --currents PATH
    carla_moment_routes --accepts PATH
    carla_moment_routes --checked PATH

`--digests` and `--accepts` print nothing when the pins match.
`--currents` prints a JSON object of the live routing documents.
`--checked` checks the try-only refusal before the route pins.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._moment_routes import (
    moment_route_accepts,
    moment_route_checked,
    moment_route_currents,
    moment_route_digests,
)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_moment_routes --digests PATH | --currents PATH |"
            " --accepts PATH | --checked PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check stored-moment route digests, currents, or pins.

    Raises:
        Error: The command is invalid, or a routing check fails.
    """
    var arguments = argv()
    if len(arguments) != 3:
        _usage()
    var mode = arguments[1]
    if (
        mode != "--digests"
        and mode != "--currents"
        and mode != "--accepts"
        and mode != "--checked"
    ):
        _usage()
    try:
        var text = Path(arguments[2]).read_text()
        if mode == "--digests":
            moment_route_digests(text)
        elif mode == "--currents":
            print(moment_route_currents(text), end="")
        elif mode == "--accepts":
            moment_route_accepts(text)
        else:
            moment_route_checked(text)
    except error:
        print(String(error), file=stderr)
        exit(1)
