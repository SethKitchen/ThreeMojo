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
from tools._sha256 import sha256_hex


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
comptime _RECORD_SHA256 = (
    "4b72cd07de22d61d70c7aa489e566cd25468189b6a60b5e105fa26ea726e6853"
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


def y_successor(
    migration: Span[UInt8, _],
    before: Span[UInt8, _],
    after: Span[UInt8, _],
    before_sha: String,
    after_sha: String,
    check_sources: Bool,
) raises:
    """Require the grouped Y successor record and its module bytes.

    Args:
        migration: The successor record bytes.
        before: The predecessor module bytes. Used when `check_sources` is true.
        after: The successor module bytes. Used when `check_sources` is true.
        before_sha: The required predecessor digest.
        after_sha: The required successor digest.
        check_sources: Whether to check the two module digests.

    Raises:
        Error: A digest changed.
    """
    if sha256_hex(migration) != _RECORD_SHA256:
        raise Error("Unreviewed grouped Y successor record")
    if not check_sources:
        return
    if sha256_hex(before) != before_sha or sha256_hex(after) != after_sha:
        raise Error("Grouped Y complete-module byte identity changed")


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
    """Check five source files and print the pass record.

    Raises:
        Error: The command is invalid.
    """
    var grouped = String("")
    var interval = String("")
    var trig = String("")
    var geometry = String("")
    var sum2 = String("")
    var record = String("")
    var before = String("")
    var after = String("")
    var before_sha = String("")
    var after_sha = String("")
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
            or word == "--record"
            or word == "--before"
            or word == "--after"
            or word == "--before-sha"
            or word == "--after-sha"
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
            elif word == "--sum2":
                sum2 = value
            elif word == "--record":
                record = value
            elif word == "--before":
                before = value
            elif word == "--after":
                after = value
            elif word == "--before-sha":
                before_sha = value
            else:
                after_sha = value
            index += 2
            continue
        _usage()
    var sources = (
        before.byte_length() > 0
        or after.byte_length() > 0
        or before_sha.byte_length() > 0
        or after_sha.byte_length() > 0
    )
    if record.byte_length() > 0:
        if (
            grouped.byte_length() > 0
            or interval.byte_length() > 0
            or trig.byte_length() > 0
            or geometry.byte_length() > 0
            or sum2.byte_length() > 0
            or (
                sources
                and (
                    before.byte_length() == 0
                    or after.byte_length() == 0
                    or before_sha.byte_length() == 0
                    or after_sha.byte_length() == 0
                )
            )
        ):
            _usage()
        try:
            if sources:
                y_successor(
                    Path(record).read_bytes(),
                    Path(before).read_bytes(),
                    Path(after).read_bytes(),
                    before_sha,
                    after_sha,
                    True,
                )
            else:
                y_successor(
                    Path(record).read_bytes(),
                    String("").as_bytes(),
                    String("").as_bytes(),
                    "",
                    "",
                    False,
                )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
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
