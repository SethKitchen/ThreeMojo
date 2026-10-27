# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the grouped-table token digest and the stored node and weight bounds.

    carla_grouped_gate --module PATH --geometry PATH

The program checks the texts it is given. It does not roll a successor
back to a historical source. The caller does that before it starts the
program.
"""

from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._fraction import Fraction
from tools._spiral_moment_derive import stored_coefficient_words
from tools._spiral_moment_words import fraction_of_word


comptime _TOKEN = (
    "3fcfc637a40c4e322b5747f27f8d77163c3f47a49d1092b37c20744cafecba40"
)
comptime _MODULE = "extensions/carla/spiral_grouped_roundoff_proof.mojo"
comptime _CONSUMER = (
    "0e42c79e3bbda283c32886e50ad8b1acd614f651f1d258f4ea4b5e4e0e139299"
)
comptime _PASS = (
    '{"status":"PASS","consumer_sha256":"'
    + _CONSUMER
    + '","runtime_arithmetic":"unchanged after impossible table refusals",'
    + '"coverage_waiver":false}'
)


def _finite(word: UInt64) -> Bool:
    """Return whether a binary64 word is finite.

    Args:
        word: One stored encoding.

    Returns:
        True when the exponent is not the nonfinite pattern.
    """
    return Int((word >> 52) & 0x7FF) != 0x7FF


def _same(left: UInt64, right: UInt64) -> Bool:
    """Return whether two words are equal as Python floats.

    Args:
        left: The first encoding.
        right: The second encoding.

    Returns:
        True when the values compare equal. `+0` equals `-0`. A NaN
        equals nothing.
    """
    return bitcast[DType.float64](left) == bitcast[DType.float64](right)


def _weights(words: List[UInt64]) raises:
    """Require the five stored weights to keep their symmetry and bounds.

    Args:
        words: The stored encodings, in order.

    Raises:
        Error: The symmetry or a bound changed.
    """
    if not (_same(words[0], words[4]) and _same(words[1], words[3])):
        raise Error("Weight symmetry changed")
    for word in words:
        if not _finite(word):
            raise Error("Invalid stored weight")
        var value = fraction_of_word(word)
        if not (Fraction(0) < value and value <= Fraction(1)):
            raise Error("Invalid stored weight")


def _nodes(words: List[UInt64]) raises:
    """Require the five stored nodes to stay inside the open unit interval.

    Args:
        words: The stored encodings, in order.

    Raises:
        Error: A node is nonfinite or outside the interval.
    """
    for word in words:
        if not _finite(word):
            raise Error("Invalid stored node")
        var value = fraction_of_word(word)
        if not (Fraction(-1) < value and value < Fraction(1)):
            raise Error("Invalid stored node")


def grouped_table(module: String, geometry: String) raises -> String:
    """Require the grouped consumer token and the stored Gauss nodes.

    Args:
        module: The grouped proof source.
        geometry: The geometry module source.

    Returns:
        The pass record as one JSON object.

    Raises:
        Error: A token digest, the weight symmetry, or a stored bound changed.
    """
    if token_sha256(module) != _TOKEN:
        raise Error("Reviewed grouped consumer graph changed")
    _weights(stored_coefficient_words(geometry, "_GL_WEIGHTS", 5))
    _nodes(stored_coefficient_words(geometry, "_GL_NODES", 5))
    return _PASS


def grouped_table_identity() -> String:
    """Return the grouped proof module and its token digest.

    Returns:
        JSON with `module`, `token`, and `consumer`.
    """
    return (
        '{"module":"'
        + _MODULE
        + '","token":"'
        + _TOKEN
        + '","consumer":"'
        + _CONSUMER
        + '"}'
    )


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_grouped_gate --module PATH --geometry PATH",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check two source files and print the pass record.

    Raises:
        Error: The command is invalid, or a grouped-table check fails.
    """
    var module = String("")
    var geometry = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--module" or word == "--geometry":
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--module":
                module = value
            else:
                geometry = value
            index += 2
            continue
        _usage()
    if module.byte_length() == 0 or geometry.byte_length() == 0:
        _usage()
    try:
        print(
            grouped_table(Path(module).read_text(), Path(geometry).read_text())
        )
    except error:
        print(String(error), file=stderr)
        exit(1)
