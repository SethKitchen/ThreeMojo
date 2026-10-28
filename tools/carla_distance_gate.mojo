# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the spiral-domain and interval token digests.

    carla_distance_gate --module PATH --interval PATH

The program checks the texts it is given. It does not roll a successor
back to a historical source. The caller does that before it starts the
program.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256


comptime _MODULE = (
    "7263f3e46da6496d3b3a6054870b4238d9f4767c07e90161065c5c87e6d18813"
)
comptime _INTERVAL = (
    "e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11"
)
comptime _PASS = (
    '{"status":"PASS","scope":"Finite ordered raw value and finite'
    " nonnegative error; original derivative and association checks"
    ' retained","provenance_authenticated":false,"original_debit_retained'
    '":true}'
)


def distance_validation(module: String, interval: String) raises -> String:
    """Require the reviewed spiral-domain and interval token digests.

    Args:
        module: The spiral-domain proof source.
        interval: The interval module source.

    Returns:
        The pass record as one JSON object.

    Raises:
        Error: A token digest changed.
    """
    if token_sha256(module) != _MODULE:
        raise Error(
            "Distance validation, derivative/association checks or"
            " debit/routing changed"
        )
    if token_sha256(interval) != _INTERVAL:
        raise Error("Ordered nonnegative-error widening operation changed")
    return _PASS


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_distance_gate --module PATH --interval PATH",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check two source files and print the pass record."""
    var module = String("")
    var interval = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--module" or word == "--interval":
            if index + 1 >= len(arguments):
                _usage()
            if word == "--module":
                module = arguments[index + 1]
            else:
                interval = arguments[index + 1]
            index += 2
            continue
        _usage()
    if module.byte_length() == 0 or interval.byte_length() == 0:
        _usage()
    try:
        print(
            distance_validation(
                Path(module).read_text(), Path(interval).read_text()
            )
        )
    except error:
        print(String(error), file=stderr)
        exit(1)
