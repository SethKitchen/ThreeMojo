# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the moment producer tokens and stored coefficient bounds.

    carla_moment_gate --module PATH --interval PATH --geometry PATH --trig PATH
    carla_moment_gate --rows PATH

The program checks the texts it is given. It does not roll a successor
back to a historical source. The caller does that before it starts the
program.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._fraction import Fraction
from tools._spiral_moment_derive import (
    coefficient_rows_payload,
    stored_coefficient_words,
)
from tools._spiral_moment_words import fraction_of_word


comptime _MODULE = (
    "9001f34d01c28de8dcf85af0bec9d9b9409ef8d56e083bfc25d6342c375f80d1"
)
comptime _INTERVAL = (
    "e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11"
)
comptime _PASS = (
    '{"status":"PASS","finite_bound_exponent":410,"count_domain":'
    + '[1,64],"source_token_sha256":"'
    + _MODULE
    + '"}'
)


def _inside(
    value: Fraction, low: Int, high: Int, strict: Bool, positive: Bool
) -> Bool:
    """Return whether `value` stays inside the proof bound.

    Args:
        value: One stored coefficient.
        low: The lower bound.
        high: The upper bound.
        strict: True when the bounds are open.
        positive: True when the value must be above zero.

    Returns:
        True when the value meets the bound.
    """
    var lower = Fraction(low)
    var upper = Fraction(high)
    var fits: Bool
    if strict:
        fits = lower < value and value < upper
    else:
        fits = lower <= value and value <= upper
    if positive:
        fits = fits and Fraction(0) < value
    return fits


def _bound(
    source: String,
    name: String,
    size: Int,
    low: Int,
    high: Int,
    strict: Bool,
    positive: Bool,
) raises:
    """Require one stored array to stay inside its proof bound.

    Args:
        source: The module that declares the array.
        name: The array name.
        size: The declared length.
        low: The lower bound.
        high: The upper bound.
        strict: True when the bounds are open.
        positive: True when each value must be above zero.

    Raises:
        Error: A word is missing or outside the bound.
    """
    var words = stored_coefficient_words(source, name, size)
    for word in words:
        if not _inside(fraction_of_word(word), low, high, strict, positive):
            raise Error("Constant outside finite proof bound: " + name)


def moment_finiteness(
    module: String, interval: String, geometry: String, trig: String
) raises -> String:
    """Require the moment producer tokens and stored coefficient bounds.

    Args:
        module: The moment proof source.
        interval: The interval module source.
        geometry: The geometry module source.
        trig: The trig module source.

    Returns:
        The pass record as one JSON object.

    Raises:
        Error: A token digest or a stored coefficient changed.
    """
    if token_sha256(module) != _MODULE:
        raise Error("Moment producer count/work/arithmetic graph changed")
    if token_sha256(interval) != _INTERVAL:
        raise Error("Directed interval arithmetic dependency changed")
    _bound(geometry, "_GL_NODES", 5, -1, 1, True, False)
    _bound(geometry, "_GL_WEIGHTS", 5, 0, 1, False, True)
    _bound(trig, "_COS_COEFFICIENTS", 11, -1, 1, False, False)
    _bound(trig, "_SIN_COEFFICIENTS", 11, -1, 1, False, False)
    return _PASS


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_moment_gate --module PATH --interval PATH"
            " --geometry PATH --trig PATH | --rows PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check four source files, or print the derived moment rows."""
    var module = String("")
    var interval = String("")
    var geometry = String("")
    var trig = String("")
    var rows = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--module"
            or word == "--interval"
            or word == "--geometry"
            or word == "--trig"
            or word == "--rows"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--module":
                module = value
            elif word == "--interval":
                interval = value
            elif word == "--geometry":
                geometry = value
            elif word == "--rows":
                rows = value
            else:
                trig = value
            index += 2
            continue
        _usage()
    if rows.byte_length() > 0:
        if (
            module.byte_length() > 0
            or interval.byte_length() > 0
            or geometry.byte_length() > 0
            or trig.byte_length() > 0
        ):
            _usage()
        try:
            print(coefficient_rows_payload(Path(rows).read_text()), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if (
        module.byte_length() == 0
        or interval.byte_length() == 0
        or geometry.byte_length() == 0
        or trig.byte_length() == 0
    ):
        _usage()
    try:
        print(
            moment_finiteness(
                Path(module).read_text(),
                Path(interval).read_text(),
                Path(geometry).read_text(),
                Path(trig).read_text(),
            )
        )
    except error:
        print(String(error), file=stderr)
        exit(1)
