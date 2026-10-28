# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Restore the historical lane-envelope capture.

    carla_restore_reference SOURCE REPLACEMENT
    carla_restore_reference --after-refusal SOURCE REPLACEMENT
    carla_restore_reference --after-refusal-syntax SOURCE REPLACEMENT

SOURCE is the current reference module. REPLACEMENT is the historical
`_try_lane_envelope_capture` function. The command removes the try-only
refusal, then replaces that capture. `--after-refusal-syntax` prepares
the Python syntax after that restored capture.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import (
    restore_reference_capture,
    restored_reference_after_refusal,
)
from tools._json_tools import quote_ascii
from tools.carla_cleanup_gate import classified_syntax_json


def restored_then_syntax(source: String, replacement: String) raises -> String:
    """Restore the historical capture, then prepare its Python syntax.

    Args:
        source: The current reference module.
        replacement: The historical `_try_lane_envelope_capture` function.

    Returns:
        JSON with `restored` and `syntax`. The refusal and the capture
        are checked before the syntax is prepared.

    Raises:
        Error: The refusal changed, the capture function is not the
            reviewed shape, or the syntax failure is unclosed or
            ambiguous. The capture is restored before the syntax is
            prepared.
    """
    var restored = restored_reference_after_refusal(source, replacement)
    var syntax = classified_syntax_json(restored)
    return '{"restored":' + quote_ascii(restored) + ',"syntax":' + syntax + "}"


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_restore_reference SOURCE REPLACEMENT |"
            " --after-refusal SOURCE REPLACEMENT |"
            " --after-refusal-syntax SOURCE REPLACEMENT"
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
    if len(arguments) == 4 and arguments[1] == "--after-refusal-syntax":
        try:
            print(
                restored_then_syntax(
                    Path(arguments[2]).read_text(),
                    Path(arguments[3]).read_text(),
                ),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
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
