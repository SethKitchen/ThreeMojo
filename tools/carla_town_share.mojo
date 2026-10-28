# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Share a town's triangle cap across its meshes.

    carla_town_share FILE

`FILE` is JSON. `grass` keeps one copy in ten, counting from `start`.
`factors` gives each kind the same share of its cap, at most 1. A kind
with no cap, or a count of 0, keeps 1. `goal` is the far building
target: at least 8, and `int(limit * factor)` otherwise. The fraction
is dropped toward 0.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float, python_repr
from tools._python_json import PY_DICT, PY_FLOAT, PY_INT, PY_LIST, PyJson


@no_inline
def _fmul(left: Float64, right: Float64) -> Float64:
    """Return one product, rounded before the next operation."""
    return left * right


@no_inline
def _fdiv(left: Float64, right: Float64) -> Float64:
    """Return one quotient, rounded before the next operation."""
    return left / right


def share_text(text: String) raises -> String:
    """Return one town-share step as JSON.

    Args:
        text: A JSON object. `mode` is `grass`, `factors` or `goal`.

    Returns:
        The kept grass indexes and the next count, the factor of each
        item, or the far building target.

    Raises:
        Error: If the JSON is not that step, or a count is negative.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("share request is not an object")
    var mode = doc.text(doc.at(root, "mode"))
    if mode == "grass":
        return _grass(doc, root)
    if mode == "factors":
        return _factors(doc, root)
    if mode == "goal":
        return _goal(doc, root)
    raise Error("share mode is not grass, factors or goal")


def _grass(doc: PyJson, root: Int) raises -> String:
    """Return the copies kept by the one-in-ten rule."""
    var start = _whole(doc, doc.at(root, "start"), "grass count")
    var count = _whole(doc, doc.at(root, "count"), "grass count")
    if start < 0 or count < 0:
        raise Error("grass count is negative")
    var out = String('{"indices":[')
    var first = True
    for index in range(count):
        if (start + index) % 10 != 0:
            continue
        if not first:
            out += ","
        first = False
        out += String(index)
    out += '],"next":'
    out += String(start + count)
    out += "}"
    return out^


def _factors(doc: PyJson, root: Int) raises -> String:
    """Return one factor for each kind and level."""
    var items = doc.at(root, "items")
    if doc.kind(items) != PY_LIST:
        raise Error("factors are not a list")
    var out = String('{"factors":[')
    for index in range(doc.length(items)):
        var item = doc.item(items, index)
        if doc.kind(item) != PY_DICT:
            raise Error("factor is not an object")
        var kind = doc.text(doc.at(item, "kind"))
        var lod = _whole(doc, doc.at(item, "lod"), "level")
        var count = _whole(doc, doc.at(item, "count"), "triangle count")
        if lod != 0 and lod != 1:
            raise Error("level is not 0 or 1")
        if count < 0:
            raise Error("triangle count is negative")
        if index > 0:
            out += ","
        out += python_repr(_factor(kind, lod, count))
    out += "]}"
    return out^


def _factor(kind: String, lod: Int, count: Int) -> Float64:
    """Return the share of one kind's cap."""
    var cap = _cap(kind, lod)
    if cap < 0 or count == 0:
        return 1.0
    var share = _fdiv(Float64(cap), Float64(count))
    if share > 1.0:
        return 1.0
    return share


def _cap(kind: String, lod: Int) -> Int:
    """Return the town cap, or -1 when the kind has none."""
    if kind == "vegetation":
        if lod == 0:
            return 1200000
        return 300000
    if kind == "building":
        if lod == 0:
            return 1500000
        return 300000
    if kind == "fence" or kind == "pole":
        if lod == 0:
            return 250000
        return 50000
    if kind == "prop":
        if lod == 0:
            return 300000
        return 1
    if kind == "parked_vehicle":
        if lod == 0:
            return 200000
        return 1
    if kind == "traffic_light":
        if lod == 0:
            return 100000
        return 20000
    return -1


def _goal(doc: PyJson, root: Int) raises -> String:
    """Return the far building triangle target."""
    var limit = _whole(doc, doc.at(root, "limit"), "triangle limit")
    if limit < 0:
        raise Error("triangle limit is negative")
    var factor = _number(doc, doc.at(root, "factor"))
    var product = _fmul(Float64(limit), factor)
    var whole = 0
    if product > 0.0:
        whole = Int(product)
    var goal = whole
    if goal < 8:
        goal = 8
    return '{"goal":' + String(goal) + "}"


def _whole(doc: PyJson, node: Int, name: String) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error(name + " is not an integer")
    var raw = doc.text(node).as_bytes()
    if len(raw) == 0:
        raise Error(name + " is not an integer")
    var index = 0
    var negative = False
    if raw[0] == 45:
        negative = True
        index = 1
    if index >= len(raw):
        raise Error(name + " is not an integer")
    var value = 0
    for offset in range(index, len(raw)):
        var byte = raw[offset]
        if byte < 48 or byte > 57:
            raise Error(name + " is not an integer")
        value = value * 10 + Int(byte - 48)
    if negative:
        return -value
    return value


def _number(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("factor is not a number")


def main() raises:
    """Print one town-share step for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_share FILE", file=stderr)
        exit(2)
    try:
        print(share_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_share:", error, file=stderr)
        exit(1)
