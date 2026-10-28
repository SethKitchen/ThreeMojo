# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose how many triangles a simplified mesh keeps.

    carla_simplify_target FILE

`FILE` is JSON. `mode` is `share`, `collapse`, `weld`, or `vehicle`.
`share` is one town mesh. A zero budget keeps nothing. A masked mesh
keeps leaf cards, grown when fewer stay. `collapse` is one near mesh
whose borders stay put. A mesh under `keep` triangles stays whole unless
`small` is set. `weld` is one far mesh. Its floor is 8 triangles.
`vehicle` gives every free primitive the same share of the budget, and
at least 5 percent. The floor there is half of `keep`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float, python_repr
from tools._python_json import (
    PY_BOOL,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PyJson,
)
from tools._town_json import json_int


def target_text(text: String) raises -> String:
    """Return one simplification choice as JSON.

    Args:
        text: A JSON object. `mode` selects the choice.

    Returns:
        The action, the target, or the per-primitive targets.

    Raises:
        Error: If the JSON is not that choice, or a count is negative.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("target request is not an object")
    var mode = doc.text(doc.at(root, "mode"))
    if mode == "share":
        return _share(doc, root)
    if mode == "collapse":
        return _collapse(doc, root)
    if mode == "weld":
        return _weld(doc, root)
    if mode == "vehicle":
        return _vehicle(doc, root)
    raise Error("mode is not share, collapse, weld, or vehicle")


def _share(doc: PyJson, root: Int) raises -> String:
    """Return the town mesh's action and its raw target."""
    var budget = json_int(
        doc, doc.at(root, "budget"), "budget is not an integer"
    )
    var triangles = json_int(
        doc, doc.at(root, "triangles"), "count is not an integer"
    )
    var total = json_int(doc, doc.at(root, "total"), "count is not an integer")
    var keep = json_int(doc, doc.at(root, "keep"), "keep is not an integer")
    if budget < 0 or triangles < 0 or total < 0 or keep < 0:
        raise Error("count is negative")
    var factor = _number(doc, doc.at(root, "factor"))
    var masked = _flag(doc, doc.at(root, "masked"))
    var limit = _fmul(Float64(budget), factor)
    var small = factor < 1.0
    if limit == 0.0:
        var none = String('{"action":"none","target":0,"keep":0.0,"small":')
        none += _bool(small)
        none += "}"
        return none^
    var denom = total
    if denom < 1:
        denom = 1
    var share = _fdiv(limit, Float64(denom))
    if masked:
        var cards = _fmul(share, 1.15)
        if cards > 1.0:
            cards = 1.0
        if cards < 0.95:
            var out = String('{"action":"cards","target":0,"keep":')
            out += python_repr(cards)
            out += ',"small":'
            out += _bool(small)
            out += "}"
            return out^
        var held = String('{"action":"whole","target":0,"keep":')
        held += python_repr(cards)
        held += ',"small":'
        held += _bool(small)
        held += "}"
        return held^
    var target = _trunc(_fmul(Float64(triangles), share))
    var out = String('{"action":"simplify","target":')
    out += String(target)
    out += ',"keep":0.0,"small":'
    out += _bool(small)
    out += "}"
    return out^


def _collapse(doc: PyJson, root: Int) raises -> String:
    """Return whether a bordered mesh stays whole, and its target."""
    var triangles = json_int(
        doc, doc.at(root, "triangles"), "count is not an integer"
    )
    var target = json_int(
        doc, doc.at(root, "target"), "count is not an integer"
    )
    var keep = json_int(doc, doc.at(root, "keep"), "keep is not an integer")
    if triangles < 0 or target < 0 or keep < 0:
        raise Error("count is negative")
    var small = _flag(doc, doc.at(root, "small"))
    var floor = 8
    if not small:
        floor = keep // 2
    var gate = target
    if floor > gate:
        gate = floor
    if triangles <= gate or (not small and triangles < keep):
        return '{"whole":true,"count":0}'
    var count = floor
    if target > count:
        count = target
    var out = String('{"whole":false,"count":')
    out += String(count)
    out += "}"
    return out^


def _weld(doc: PyJson, root: Int) raises -> String:
    """Return whether a far mesh stays whole, and its target."""
    var triangles = json_int(
        doc, doc.at(root, "triangles"), "count is not an integer"
    )
    var target = json_int(
        doc, doc.at(root, "target"), "count is not an integer"
    )
    if triangles < 0 or target < 0:
        raise Error("count is negative")
    var gate = target
    if gate < 8:
        gate = 8
    if triangles <= gate:
        return '{"whole":true,"count":0}'
    var out = String('{"whole":false,"count":')
    out += String(gate)
    out += "}"
    return out^


def _vehicle(doc: PyJson, root: Int) raises -> String:
    """Return each free primitive's target triangle count."""
    var counts = doc.at(root, "counts")
    var fixed = doc.at(root, "fixed")
    if doc.kind(counts) != PY_LIST or doc.kind(fixed) != PY_LIST:
        raise Error("vehicle arrays are not lists")
    if doc.length(counts) != doc.length(fixed):
        raise Error("vehicle arrays differ in length")
    var budget = json_int(
        doc, doc.at(root, "budget"), "budget is not an integer"
    )
    var keep = json_int(doc, doc.at(root, "keep"), "keep is not an integer")
    if budget < 0 or keep < 0:
        raise Error("count is negative")
    var total = 0
    var held = 0
    var count = doc.length(counts)
    for index in range(count):
        var triangles = json_int(
            doc, doc.item(counts, index), "count is not an integer"
        )
        if triangles < 0:
            raise Error("count is negative")
        total += triangles
        if _flag(doc, doc.item(fixed, index)):
            held += triangles
    if total <= budget or total == held:
        var skipped = String('{"skip":true,"targets":[')
        for index in range(count):
            if index > 0:
                skipped += ","
            skipped += "0"
        skipped += "]}"
        return skipped^
    var ratio = _fdiv(Float64(budget - held), Float64(total - held))
    if ratio < 0.05:
        ratio = 0.05
    var floor = keep // 2
    var out = String('{"skip":false,"targets":[')
    for index in range(count):
        if index > 0:
            out += ","
        if _flag(doc, doc.item(fixed, index)):
            out += "0"
        else:
            var triangles = json_int(
                doc, doc.item(counts, index), "count is not an integer"
            )
            var target = _trunc(_fmul(Float64(triangles), ratio))
            if target < floor:
                target = floor
            out += String(target)
    out += "]}"
    return out^


def _trunc(value: Float64) -> Int:
    """Return `value` truncated toward zero."""
    if value < 0.0:
        return -Int(-value)
    return Int(value)


def _bool(value: Bool) -> String:
    """Return a JSON bool."""
    if value:
        return "true"
    return "false"


def _flag(doc: PyJson, node: Int) raises -> Bool:
    """Return a JSON bool."""
    if doc.kind(node) != PY_BOOL:
        raise Error("flag is not a bool")
    return doc.flag(node)


def _number(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number as a float."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("factor is not a number")


@no_inline
def _fmul(left: Float64, right: Float64) -> Float64:
    """Return one product, rounded before the next operation."""
    return left * right


@no_inline
def _fdiv(left: Float64, right: Float64) -> Float64:
    """Return one quotient, rounded before the next operation."""
    return left / right


def main() raises:
    """Print one simplification choice for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_simplify_target FILE", file=stderr)
        exit(2)
    try:
        print(target_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_simplify_target:", error, file=stderr)
        exit(1)
