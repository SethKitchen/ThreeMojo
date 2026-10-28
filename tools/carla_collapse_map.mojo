# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Keep the first corner that collapsed into each new corner.

    carla_collapse_map FILE

`FILE` is JSON with `mapping` and `count`, or with `source`, `values`
and `width`. `mapping[old]` is the new corner that old corner collapsed
into. The smallest old index wins when several corners land on one new
corner. A new corner that nobody reached stays 0. `source` then copies
that corner's texture values.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float, python_repr
from tools._python_json import (
    MISSING,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PyJson,
)


def collapse_text(text: String) raises -> String:
    """Return the surviving old corner of each new corner as JSON.

    Args:
        text: A JSON object with `mapping` and `count`.

    Returns:
        `source`, one old index for each new corner, or `values`, the
        copied texture numbers.

    Raises:
        Error: If the JSON is not that map, or an index is out of range.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("collapse map is not an object")
    if doc.get(root, "values") != MISSING:
        return _gather(doc, root)
    var mapping = doc.at(root, "mapping")
    if doc.kind(mapping) != PY_LIST:
        raise Error("mapping is not a list")
    var count = _whole(doc, doc.at(root, "count"), "count is not an integer")
    if count < 0:
        raise Error("count is negative")
    var source = List[Int]()
    for _ in range(count):
        source.append(0)
    var seen = List[Bool]()
    for _ in range(count):
        seen.append(False)
    for old in range(doc.length(mapping)):
        var new = _index(doc, doc.item(mapping, old), count)
        if not seen[new]:
            source[new] = old
            seen[new] = True
    var out = String('{"source":[')
    for index in range(count):
        if index > 0:
            out += ","
        out += String(source[index])
    out += "]}"
    return out^


def _gather(doc: PyJson, root: Int) raises -> String:
    """Copy each surviving corner's texture values."""
    var source = doc.at(root, "source")
    var values = doc.at(root, "values")
    if doc.kind(source) != PY_LIST or doc.kind(values) != PY_LIST:
        raise Error("gather arrays are not lists")
    var width = _whole(doc, doc.at(root, "width"), "width is not an integer")
    if width < 1:
        raise Error("width is not positive")
    var out = String('{"values":[')
    for corner in range(doc.length(source)):
        var old = _whole(
            doc, doc.item(source, corner), "index is not an integer"
        )
        if old < 0:
            raise Error("index out of range")
        var start = old * width
        if start < 0 or start + width > doc.length(values):
            raise Error("index out of range")
        for offset in range(width):
            if corner > 0 or offset > 0:
                out += ","
            out += python_repr(_number(doc, doc.item(values, start + offset)))
    out += "]}"
    return out^


def _number(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number as a float."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("value is not a number")


def _index(doc: PyJson, node: Int, count: Int) raises -> Int:
    """Return a new-corner index inside `count`."""
    var value = _whole(doc, node, "index is not an integer")
    if value < 0 or value >= count:
        raise Error("index out of range")
    return value


def _whole(doc: PyJson, node: Int, message: String) raises -> Int:
    """Return a JSON integer, or raise `message`."""
    if doc.kind(node) != PY_INT:
        raise Error(message)
    return Int(parse_float(doc.text(node)))


def main() raises:
    """Print the surviving corners for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_collapse_map FILE", file=stderr)
        exit(2)
    try:
        print(collapse_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_collapse_map:", error, file=stderr)
        exit(1)
