# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Restore the historical lane-envelope capture.

    carla_restore_reference SOURCE REPLACEMENT
    carla_restore_reference --after-refusal SOURCE REPLACEMENT

SOURCE is the current reference module. REPLACEMENT is the historical
`_try_lane_envelope_capture` function. The command removes the try-only
refusal, then replaces that capture.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import (
    restore_reference_capture,
    restored_reference_after_refusal,
)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_restore_reference SOURCE REPLACEMENT |"
            " --after-refusal SOURCE REPLACEMENT"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print the reference module with the historical capture restored.

    Raises:
        Error: The command is invalid, or the refusal or capture changed.
    """
    var arguments = argv()
    if len(arguments) == 4 and arguments[1] == "--after-refusal":
        try:
            print(
                restored_reference_after_refusal(
                    Path(arguments[2]).read_text(),
                    Path(arguments[3]).read_text(),
                ),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 3:
        _usage()
    try:
        print(
            restore_reference_capture(
                Path(arguments[1]).read_text(),
                Path(arguments[2]).read_text(),
            ),
            end="",
        )
    except error:
        print(String(error), file=stderr)
        exit(1)
