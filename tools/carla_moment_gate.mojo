# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the moment producer tokens and stored coefficient bounds.

    carla_moment_gate --module PATH --interval PATH --geometry PATH --trig PATH
    carla_moment_gate --rows PATH
    carla_moment_gate --decimal-rows PATH
    carla_moment_gate --coefficient-words PATH
    carla_moment_gate --verified-table PATH
    carla_moment_gate --node-sums PATH
    carla_moment_gate --fractions PATH

The program checks the texts it is given. It does not roll a successor
back to a historical source. The caller does that before it starts the
program.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._fraction import Fraction
from tools._spiral_moment_derive import (
    coefficient_rows_from_decimals,
    coefficient_rows_payload,
    coefficient_words_json,
    stored_coefficient_words,
    verified_table_integers,
)
from tools._spiral_moment_words import (
    fraction_of_word,
    fraction_texts_payload,
    rounded_node_sums_payload,
)


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


def moment_sources() -> String:
    """Return the moment proof path, the interval path, and their tokens.

    Returns:
        JSON with `module`, `interval`, `module_token`, and `interval_token`.
    """
    return (
        '{"module":"extensions/carla/spiral_moment_proof.mojo","interval":'
        + '"extensions/carla/curve_interval.mojo","module_token":"'
        + _MODULE
        + '","interval_token":"'
        + _INTERVAL
        + '"}'
    )


def moment_files() -> String:
    """Return the pin file, the stored table, and the word count.

    Returns:
        JSON with `pins`, `table`, and `words`.
    """
    return (
        '{"pins":"tools/carla_lane_oracle/spiral-moment-pins.json",'
        + '"table":"extensions/carla/spiral_moment_table_data.mojo",'
        + '"words":2816}'
    )


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_moment_gate --module PATH --interval PATH"
            " --geometry PATH --trig PATH | --rows PATH | --decimal-rows PATH |"
            " --coefficient-words PATH | --verified-table PATH | --node-sums"
            " PATH | --fractions PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check four source files, or print rows, words, node sums, or fractions.

    Raises:
        Error: The command is invalid, or a moment check fails.
    """
    var module = String("")
    var interval = String("")
    var geometry = String("")
    var trig = String("")
    var rows = String("")
    var decimal_rows = String("")
    var coefficient_words = String("")
    var verified_table = String("")
    var node_sums = String("")
    var fractions = String("")
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
            or word == "--decimal-rows"
            or word == "--coefficient-words"
            or word == "--verified-table"
            or word == "--node-sums"
            or word == "--fractions"
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
            elif word == "--decimal-rows":
                decimal_rows = value
            elif word == "--coefficient-words":
                coefficient_words = value
            elif word == "--verified-table":
                verified_table = value
            elif word == "--node-sums":
                node_sums = value
            elif word == "--fractions":
                fractions = value
            else:
                trig = value
            index += 2
            continue
        _usage()
    var single = 0
    if rows.byte_length() > 0:
        single += 1
    if decimal_rows.byte_length() > 0:
        single += 1
    if coefficient_words.byte_length() > 0:
        single += 1
    if verified_table.byte_length() > 0:
        single += 1
    if node_sums.byte_length() > 0:
        single += 1
    if fractions.byte_length() > 0:
        single += 1
    if single > 0:
        if (
            single != 1
            or module.byte_length() > 0
            or interval.byte_length() > 0
            or geometry.byte_length() > 0
            or trig.byte_length() > 0
        ):
            _usage()
        try:
            if fractions.byte_length() > 0:
                print(
                    fraction_texts_payload(Path(fractions).read_text()),
                    end="",
                )
            elif node_sums.byte_length() > 0:
                print(
                    rounded_node_sums_payload(Path(node_sums).read_text()),
                    end="",
                )
            elif coefficient_words.byte_length() > 0:
                print(
                    coefficient_words_json(Path(coefficient_words).read_text()),
                    end="",
                )
            elif verified_table.byte_length() > 0:
                print(
                    verified_table_integers(Path(verified_table).read_text()),
                    end="",
                )
            elif decimal_rows.byte_length() > 0:
                print(
                    coefficient_rows_from_decimals(
                        Path(decimal_rows).read_text()
                    ),
                    end="",
                )
            else:
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
