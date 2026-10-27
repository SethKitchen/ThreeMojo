# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the five Y-finiteness token digests.

    carla_y_gate --grouped PATH --interval PATH --trig PATH --geometry PATH --sum2 PATH

The program checks the texts it is given. It does not accept a stored-word
substitute. The caller does that before it starts the program.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256


comptime _GROUPED = (
    "cd92ac2f02c75fc420920fe3a73b4ddd28a4e5cf0d97785b4ae4eb0f54f2cbd7"
)
comptime _INTERVAL = (
    "e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11"
)
comptime _TRIG = (
    "523d5700201b957152eaa79ae6cce9ca8cb9a2a0098d5b105584667360a6de7f"
)
comptime _GEOMETRY = (
    "a1979bd37d0ea725f452e0a0a269c7aaef3cda485b291e8fe79b49b35850adcb"
)
comptime _SUM2 = (
    "3fbcbb7f6ba0b9120500698665f0419acf6618d8bd34b7e18b9d10896282383d"
)
comptime _PASS = (
    '{"status":"PASS","maximum_accumulator_exponent":947,'
    + '"origin_error_refusal_unchanged":true,"y_call_and_writes_retained":true}'
)


def _token(source: String, expected: String, label: String) raises:
    """Require one module to keep its reviewed token digest.

    Args:
        source: The module text.
        expected: The reviewed digest.
        label: The path named in a failure.

    Raises:
        Error: The digest changed.
    """
    if token_sha256(source) != expected:
        raise Error(
            "Y-finiteness premise, graph, writes or ordering changed: " + label
        )


def y_finiteness(
    grouped: String,
    interval: String,
    trig: String,
    geometry: String,
    sum2: String,
) raises -> String:
    """Require the five Y-finiteness modules to keep their token digests.

    Args:
        grouped: The grouped roundoff proof.
        interval: The interval module.
        trig: The trig module.
        geometry: The geometry module.
        sum2: The sum2 module.

    Returns:
        The pass record as one JSON object.

    Raises:
        Error: A token digest changed.
    """
    _token(
        grouped,
        _GROUPED,
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    _token(interval, _INTERVAL, "extensions/carla/curve_interval.mojo")
    _token(trig, _TRIG, "extensions/carla/curve_trig.mojo")
    _token(geometry, _GEOMETRY, "extensions/carla/geometry.mojo")
    _token(sum2, _SUM2, "extensions/carla/curve_sum2.mojo")
    return _PASS


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_y_gate --grouped PATH --interval PATH --trig PATH"
            " --geometry PATH --sum2 PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check five source files and print the pass record."""
    var grouped = String("")
    var interval = String("")
    var trig = String("")
    var geometry = String("")
    var sum2 = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--grouped"
            or word == "--interval"
            or word == "--trig"
            or word == "--geometry"
            or word == "--sum2"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--grouped":
                grouped = value
            elif word == "--interval":
                interval = value
            elif word == "--trig":
                trig = value
            elif word == "--geometry":
                geometry = value
            else:
                sum2 = value
            index += 2
            continue
        _usage()
    if (
        grouped.byte_length() == 0
        or interval.byte_length() == 0
        or trig.byte_length() == 0
        or geometry.byte_length() == 0
        or sum2.byte_length() == 0
    ):
        _usage()
    try:
        print(
            y_finiteness(
                Path(grouped).read_text(),
                Path(interval).read_text(),
                Path(trig).read_text(),
                Path(geometry).read_text(),
                Path(sum2).read_text(),
            )
        )
    except error:
        print(String(error), file=stderr)
        exit(1)
