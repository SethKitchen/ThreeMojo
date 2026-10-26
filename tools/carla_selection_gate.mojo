# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the selection-producer tokens and phase-constant bounds.

    carla_selection_gate --grouped PATH --roundoff PATH --interval PATH --trig PATH

The program checks the texts it is given. It does not roll a successor
back to a historical source. The caller does that before it starts the
program.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._fraction import Fraction
from tools._spiral_moment_derive import stored_scalar_word
from tools._spiral_moment_words import fraction_of_word


comptime _GROUPED = (
    "a8f3beca23c8d6a84d01f5eebecb0a01cd2102aad4e226ed6a782722733a86b7"
)
comptime _ROUNDOFF = (
    "634c4f0f448b472301a42ad6065655f60cf78121f12bafa64085a1e67108fc0f"
)
comptime _INTERVAL = (
    "e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11"
)
comptime _PASS = (
    '{"status":"PASS","ordered_theta":true,"nonnegative_error":true,'
    + '"selector_endpoint_magnitude_below":4194304}'
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
        if label.byte_length() == 0:
            raise Error("Ordering or nonnegative-error arithmetic changed")
        raise Error(
            "Selection producer/input/error/phase graph changed: " + label
        )


def _positive_through(value: Fraction, high: Int) -> Bool:
    """Return whether `value` is above zero and at most `high`.

    Args:
        value: One stored constant.
        high: The upper bound.

    Returns:
        True when `0 < value <= high`.
    """
    return Fraction(0) < value and value <= Fraction(high)


def selection_finiteness(
    grouped: String, roundoff: String, interval: String, trig: String
) raises -> String:
    """Require the selection tokens and the two phase constants.

    Args:
        grouped: The grouped roundoff proof.
        roundoff: The roundoff proof.
        interval: The interval module.
        trig: The trig module.

    Returns:
        The pass record as one JSON object.

    Raises:
        Error: A token digest or a phase constant changed.
    """
    _token(
        grouped,
        _GROUPED,
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    _token(
        roundoff,
        _ROUNDOFF,
        "extensions/carla/spiral_roundoff_proof.mojo",
    )
    _token(interval, _INTERVAL, "")
    var multiplier = fraction_of_word(stored_scalar_word(trig, "_INV_HALF_PI"))
    var limit = fraction_of_word(stored_scalar_word(trig, "_PHASE_LIMIT"))
    if not _positive_through(multiplier, 1):
        raise Error("Selector multiplier bound")
    if not _positive_through(limit, 1048576):
        raise Error("Finite phase bound")
    return _PASS


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_selection_gate --grouped PATH --roundoff PATH"
            " --interval PATH --trig PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check four source files and print the pass record."""
    var grouped = String("")
    var roundoff = String("")
    var interval = String("")
    var trig = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--grouped"
            or word == "--roundoff"
            or word == "--interval"
            or word == "--trig"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--grouped":
                grouped = value
            elif word == "--roundoff":
                roundoff = value
            elif word == "--interval":
                interval = value
            else:
                trig = value
            index += 2
            continue
        _usage()
    if (
        grouped.byte_length() == 0
        or roundoff.byte_length() == 0
        or interval.byte_length() == 0
        or trig.byte_length() == 0
    ):
        _usage()
    try:
        print(
            selection_finiteness(
                Path(grouped).read_text(),
                Path(roundoff).read_text(),
                Path(interval).read_text(),
                Path(trig).read_text(),
            )
        )
    except error:
        print(String(error), file=stderr)
        exit(1)
