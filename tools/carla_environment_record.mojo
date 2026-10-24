# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Round each environment position to four decimal places.

    carla_environment_record FILE

`FILE` is JSON. It has `objects`, a list of records. Each record has
`id`, `name`, `label`, and five vectors. The program prints those
records. Each position and each angle uses Python's `round` to four
decimal places, half to even.
"""

from std.ffi import external_call
from std.math import isinf, isnan
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._json_tools import quote_ascii
from tools._python_float import parse_float, python_repr
from tools._python_json import (
    MISSING,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
)


def record_text(text: String) raises -> String:
    """Return environment records with each position rounded.

    Args:
        text: JSON with `objects`. Each object has `id`, `name`, `label`,
            `location`, `rotation`, `box_center`, `box_extent` and
            `box_rotation`.

    Returns:
        The same records. Each of those five vectors is three numbers
        rounded as Python `round(value, 4)`, half to even.

    Raises:
        Error: If the JSON is not that list, a vector is not three
            numbers, or a name is not a string.
    """
    var doc = PyJson.parse(text)
    if doc.kind(doc.root) != PY_DICT:
        raise Error("environment record is not an object")
    var objects = doc.get(doc.root, "objects")
    if objects == MISSING or doc.kind(objects) != PY_LIST:
        raise Error("objects are not a list")
    var out = String('{"objects":[')
    var count = doc.length(objects)
    for index in range(count):
        if index > 0:
            out += ","
        out += _one(doc, doc.item(objects, index))
    out += "]}"
    return out


def _one(doc: PyJson, node: Int) raises -> String:
    """Return one record with its five vectors rounded."""
    if doc.kind(node) != PY_DICT:
        raise Error("record is not an object")
    var result = String('{"id":')
    result += _integer(doc, _member(doc, node, "id"))
    result += ',"name":'
    result += quote_ascii(_text(doc, _member(doc, node, "name")))
    result += ',"label":'
    result += quote_ascii(_text(doc, _member(doc, node, "label")))
    result += ',"location":'
    result += _vector(doc, _member(doc, node, "location"))
    result += ',"rotation":'
    result += _vector(doc, _member(doc, node, "rotation"))
    result += ',"box_center":'
    result += _vector(doc, _member(doc, node, "box_center"))
    result += ',"box_extent":'
    result += _vector(doc, _member(doc, node, "box_extent"))
    result += ',"box_rotation":'
    result += _vector(doc, _member(doc, node, "box_rotation"))
    result += "}"
    return result


def _vector(doc: PyJson, node: Int) raises -> String:
    """Return three rounded numbers."""
    if doc.kind(node) != PY_LIST or doc.length(node) != 3:
        raise Error("vector is not 3 numbers")
    var result = String("[")
    for index in range(3):
        if index > 0:
            result += ","
        result += _json_number(_round4(_number(doc, doc.item(node, index))))
    result += "]"
    return result


def _round4(value: Float64) raises -> Float64:
    """Return `round(value, 4)`, half to even."""
    if isnan(value) or isinf(value):
        return value
    if value == 0.0:
        return value
    var scaled = Fraction.from_float(value) * Fraction(10000)
    var parts = scaled.numerator.divmod(scaled.denominator)
    var quotient = parts[0].copy()
    var twice = parts[1] * BigInt(2)
    if twice > scaled.denominator:
        quotient = quotient + BigInt(1)
    elif twice == scaled.denominator and quotient.is_odd():
        quotient = quotient + BigInt(1)
    if quotient.is_zero():
        return external_call["copysign", Float64](Float64(0), value)
    return (Fraction(quotient) / Fraction(10000)).to_float()


def _json_number(value: Float64) raises -> String:
    """Return one number as Python's JSON writer spells a non-finite value."""
    if isnan(value):
        return "NaN"
    if isinf(value):
        if value > 0.0:
            return "Infinity"
        return "-Infinity"
    return python_repr(value)


def _number(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("vector is not 3 numbers")


def _integer(doc: PyJson, node: Int) raises -> String:
    """Return a JSON integer's original spelling."""
    if doc.kind(node) != PY_INT:
        raise Error("id is not an integer")
    return doc.text(node)


def _text(doc: PyJson, node: Int) raises -> String:
    """Return a JSON string."""
    if doc.kind(node) != PY_STR:
        raise Error("text is not a string")
    return doc.text(node)


def _member(doc: PyJson, node: Int, key: String) raises -> Int:
    """Return a member, or raise when it is absent."""
    var found = doc.get(node, key)
    if found == MISSING:
        raise Error("KeyError: '" + key + "'")
    return found


def main() raises:
    """Print the rounded records for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_environment_record FILE", file=stderr)
        exit(2)
    try:
        print(record_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_environment_record:", error, file=stderr)
        exit(1)
