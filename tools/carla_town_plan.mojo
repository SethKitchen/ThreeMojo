# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose which town meshes are drawn and which far level each uses.

    carla_town_plan FILE

`FILE` is JSON. `mode` is `select` or `jobs`. `select` drops a hidden
row, a skipped kind, and an engine mesh that is not the cube. `jobs`
keeps one grass copy in ten, shares each kind's cap, and names the far
level: a building is baked, a tree is an impostor, and any other mesh
is lowered.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float
from tools._python_json import (
    PY_BOOL,
    PY_DICT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
)
from tools.carla_town_budget import far_budget, kind_of, near_budget
from tools.carla_town_share import share_text


comptime GRID = "WorldGridMaterial"
comptime TREES = "/Vegetation/Trees/"


def plan_text(text: String) raises -> String:
    """Return the meshes to load, or the work for the meshes that loaded.

    Args:
        text: JSON with `mode` and `rows`. `select` rows have `mesh` and
            `visible`. `jobs` rows have `mesh`, `copies`, `triangles`,
            and `materials`.

    Returns:
        `select` returns the kept row indexes. `jobs` returns each row's
        grass copies, its kind, and the action of each level.

    Raises:
        Error: If the JSON is not that request, or a count is negative.
    """
    var doc = PyJson.parse(text)
    if doc.kind(doc.root) != PY_DICT:
        raise Error("plan request is not an object")
    var mode = _text(
        doc, doc.at(doc.root, "mode"), "mode is not select or jobs"
    )
    if mode == "select":
        return _select(doc)
    if mode == "jobs":
        return _jobs(doc)
    raise Error("mode is not select or jobs")


def _select(doc: PyJson) raises -> String:
    """Return the row indexes the town loads."""
    var rows = doc.at(doc.root, "rows")
    if doc.kind(rows) != PY_LIST:
        raise Error("rows are not a list")
    var out = String('{"rows":[')
    var first = True
    for index in range(doc.length(rows)):
        var row = doc.item(rows, index)
        if doc.kind(row) != PY_DICT:
            raise Error("row is not an object")
        if not _flag(doc, doc.at(row, "visible"), "visible is not a bool"):
            continue
        var mesh = _text(doc, doc.at(row, "mesh"), "mesh is not text")
        if kind_of(mesh) == "skip":
            continue
        if _starts(mesh, "/Engine/") and not _ends(mesh, "/Cube"):
            continue
        if not first:
            out += ","
        first = False
        out += String(index)
    out += "]}"
    return out^


def _jobs(doc: PyJson) raises -> String:
    """Return the grass copies, the factors, and each level's action."""
    var rows = doc.at(doc.root, "rows")
    if doc.kind(rows) != PY_LIST:
        raise Error("rows are not a list")
    var meshes = List[String]()
    var copies = List[Int]()
    var totals = List[Int]()
    var kept = List[List[Int]]()
    var kinds = List[String]()
    var grass = 0
    var key_kind = List[String]()
    var key_lod = List[Int]()
    var key_count = List[Int]()
    for index in range(doc.length(rows)):
        var row = doc.item(rows, index)
        if doc.kind(row) != PY_DICT:
            raise Error("row is not an object")
        var mesh = _text(doc, doc.at(row, "mesh"), "mesh is not text")
        var count = _whole(doc, doc.at(row, "copies"), "copies")
        var triangles = _whole(doc, doc.at(row, "triangles"), "triangles")
        if count < 0:
            raise Error("copies is negative")
        if triangles < 0:
            raise Error("triangles is negative")
        var kind = kind_of(mesh)
        var use = List[Int]()
        if _has(mesh, "/Vegetation/Grass/"):
            var step = PyJson.parse(
                share_text(
                    '{"mode":"grass","start":'
                    + String(grass)
                    + ',"count":'
                    + String(count)
                    + "}"
                )
            )
            var indices = step.at(step.root, "indices")
            for item in range(step.length(indices)):
                use.append(
                    _whole(step, step.item(indices, item), "grass index")
                )
            grass = _whole(step, step.at(step.root, "next"), "grass count")
        else:
            for item in range(count):
                use.append(item)
        var near = near_budget(kind, triangles, mesh)
        var far = far_budget(kind, triangles, mesh)
        _add(key_kind, key_lod, key_count, kind, 0, near * len(use))
        _add(key_kind, key_lod, key_count, kind, 1, far * len(use))
        meshes.append(mesh)
        copies.append(count)
        totals.append(triangles)
        kept.append(use^)
        kinds.append(kind)
    var factors = _factors(key_kind, key_lod, key_count)
    var out = String('{"factors":[')
    for index in range(len(key_kind)):
        if index > 0:
            out += ","
        out += '{"kind":'
        out += _quote(key_kind[index])
        out += ',"lod":'
        out += String(key_lod[index])
        out += ',"count":'
        out += String(key_count[index])
        out += ',"factor":'
        out += factors[index]
        out += "}"
    out += '],"jobs":['
    for index in range(doc.length(rows)):
        if index > 0:
            out += ","
        out += _job(
            doc,
            doc.item(rows, index),
            meshes[index],
            kinds[index],
            totals[index],
            kept[index],
            _lookup(key_kind, key_lod, factors, kinds[index], 0),
            _lookup(key_kind, key_lod, factors, kinds[index], 1),
        )
    out += "]}"
    return out^


def _job(
    doc: PyJson,
    row: Int,
    mesh: String,
    kind: String,
    triangles: Int,
    copies: List[Int],
    near_factor: String,
    far_factor: String,
) raises -> String:
    """Return one loaded mesh's work."""
    var names = doc.at(row, "materials")
    if doc.kind(names) != PY_LIST:
        raise Error("materials are not a list")
    var first = -1
    for index in range(doc.length(names)):
        var name = _text(doc, doc.item(names, index), "material is not text")
        if name != GRID and first < 0:
            first = index
    var far_limit = far_budget(kind, triangles, mesh)
    var goal = 0
    if kind == "building":
        goal = _goal(far_limit, far_factor)
    var out = String('{"kind":')
    out += _quote(kind)
    out += ',"lamp_glass":'
    if _has(mesh, "_glass_") and _has(mesh, "/StreetLights/"):
        out += "true"
    else:
        out += "false"
    out += ',"copies":['
    for index in range(len(copies)):
        if index > 0:
            out += ","
        out += String(copies[index])
    out += '],"parts":['
    var wrote = False
    for index in range(doc.length(names)):
        var name = _text(doc, doc.item(names, index), "material is not text")
        if name == GRID:
            continue
        if wrote:
            out += ","
        wrote = True
        out += '{"index":'
        out += String(index)
        out += ',"material":'
        out += _quote(name)
        out += ',"levels":['
        out += _level(0, "lower", near_factor, 0)
        out += ","
        var action = String("lower")
        if kind == "building":
            if index == first:
                action = "baked"
            else:
                action = "skip"
        elif _has(mesh, TREES):
            if index == first:
                action = "impostor"
            else:
                action = "skip"
        out += _level(1, action, far_factor, goal)
        out += "]}"
    out += "]}"
    return out^


def _level(lod: Int, action: String, factor: String, goal: Int) -> String:
    """Return one level's action."""
    var out = String('{"lod":')
    out += String(lod)
    out += ',"action":'
    out += _quote(action)
    out += ',"factor":'
    out += factor
    if action == "baked":
        out += ',"goal":'
        out += String(goal)
    out += "}"
    return out^


def _factors(
    kinds: List[String], lods: List[Int], counts: List[Int]
) raises -> List[String]:
    """Return each planned count's share, in the same order."""
    var request = String('{"mode":"factors","items":[')
    for index in range(len(kinds)):
        if index > 0:
            request += ","
        request += '{"kind":'
        request += _quote(kinds[index])
        request += ',"lod":'
        request += String(lods[index])
        request += ',"count":'
        request += String(counts[index])
        request += "}"
    request += "]}"
    var doc = PyJson.parse(share_text(request))
    var listed = doc.at(doc.root, "factors")
    var out = List[String]()
    for index in range(doc.length(listed)):
        out.append(doc.text(doc.item(listed, index)))
    return out^


def _goal(limit: Int, factor: String) raises -> Int:
    """Return the far building target."""
    var request = String('{"mode":"goal","limit":')
    request += String(limit)
    request += ',"factor":'
    request += factor
    request += "}"
    var doc = PyJson.parse(share_text(request))
    return _whole(doc, doc.at(doc.root, "goal"), "goal")


def _lookup(
    kinds: List[String],
    lods: List[Int],
    factors: List[String],
    kind: String,
    lod: Int,
) raises -> String:
    """Return the factor stored for one kind and level."""
    for index in range(len(kinds)):
        if kinds[index] == kind and lods[index] == lod:
            return factors[index]
    raise Error("factor is missing")


def _add(
    mut kinds: List[String],
    mut lods: List[Int],
    mut counts: List[Int],
    kind: String,
    lod: Int,
    amount: Int,
):
    """Add `amount` to one planned count, keeping the first-seen order."""
    for index in range(len(kinds)):
        if kinds[index] == kind and lods[index] == lod:
            counts[index] += amount
            return
    kinds.append(kind)
    lods.append(lod)
    counts.append(amount)


def _text(doc: PyJson, node: Int, message: String) raises -> String:
    """Return a JSON string, or raise `message`."""
    if doc.kind(node) != PY_STR:
        raise Error(message)
    return doc.text(node)


def _flag(doc: PyJson, node: Int, message: String) raises -> Bool:
    """Return a JSON bool, or raise `message`."""
    if doc.kind(node) != PY_BOOL:
        raise Error(message)
    return doc.flag(node)


def _whole(doc: PyJson, node: Int, message: String) raises -> Int:
    """Return a JSON integer, or raise `message`."""
    if doc.kind(node) != PY_INT:
        raise Error(message + " is not an integer")
    return Int(parse_float(doc.text(node)))


def _quote(text: String) -> String:
    """Return one JSON string."""
    var out = String('"')
    var raw = text.as_bytes()
    for index in range(len(raw)):
        var byte = raw[index]
        if byte == 34 or byte == 92:
            out += "\\"
            out += chr(Int(byte))
        else:
            out += chr(Int(byte))
    out += '"'
    return out


def _starts(text: String, prefix: String) -> Bool:
    """Return whether `text` begins with `prefix`."""
    var raw = text.as_bytes()
    var head = prefix.as_bytes()
    if len(raw) < len(head):
        return False
    for index in range(len(head)):
        if raw[index] != head[index]:
            return False
    return True


def _ends(text: String, suffix: String) -> Bool:
    """Return whether `text` ends with `suffix`."""
    var raw = text.as_bytes()
    var tail = suffix.as_bytes()
    if len(raw) < len(tail):
        return False
    var start = len(raw) - len(tail)
    for index in range(len(tail)):
        if raw[start + index] != tail[index]:
            return False
    return True


def _has(text: String, needle: String) -> Bool:
    """Return whether `needle` occurs in `text`."""
    var raw = text.as_bytes()
    var want = needle.as_bytes()
    if len(want) == 0 or len(want) > len(raw):
        return False
    for start in range(len(raw) - len(want) + 1):
        var same = True
        for offset in range(len(want)):
            if raw[start + offset] != want[offset]:
                same = False
                break
        if same:
            return True
    return False


def main() raises:
    """Print the plan for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_plan FILE", file=stderr)
        exit(2)
    try:
        print(plan_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_plan:", error, file=stderr)
        exit(1)
