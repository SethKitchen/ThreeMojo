# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Simplify one town mesh the way the town bake does.

    carla_town_simplify FILE

`FILE` is JSON. `mode` is `border` or `weld`. `border` keeps open edges
and copies texture coordinates from the first corner that collapsed.
`weld` gathers corners into cells, collapses the joined mesh, and gives
each new triangle the texture of one original triangle. `same` means the
mesh stays whole. `empty` means the far mesh has no triangles left.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from tools._process import _remove_tree

from tools._python_float import parse_float
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_INT,
    PY_LIST,
    PyJson,
)
from tools.carla_area_normals import normals_text
from tools.carla_collapse_map import collapse_text
from tools.carla_simplify import simplify_text
from tools.carla_simplify_target import target_text
from tools.carla_town_choose import choose_text
from tools.carla_town_finish import finish_text
from tools.carla_town_near import near_text
from tools.carla_town_uv import uv_text
from tools.carla_town_weld import weld_text


comptime DIVISIONS = 200
"""Cells across a far mesh, matching `CLUSTER_DIVISIONS`."""
comptime CANDIDATES = 8
"""Original triangles considered for one new face."""


def town_simplify_text(text: String) raises -> String:
    """Return one simplified town mesh as JSON.

    Args:
        text: A JSON object. `mode` is `border` or `weld`. The mesh has
            `positions`, `uvs`, `triangles`, `material` and `target`.
            `border` also reads `keep` and `small`.

    Returns:
        The simplified positions, normals, texture coordinates and
        triangles, or `same` or `empty`.

    Raises:
        Error: If the JSON is not that mesh, or an index is out of range.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("simplify request is not an object")
    var mode = doc.text(doc.at(root, "mode"))
    if mode == "border":
        return _border(doc, root)
    if mode == "weld":
        return _weld(doc, root)
    raise Error("mode is not border or weld")


def _border(doc: PyJson, root: Int) raises -> String:
    """Collapse one mesh while its open edges stay put."""
    var positions = doc.at(root, "positions")
    var uvs = doc.at(root, "uvs")
    var triangles = doc.at(root, "triangles")
    var target = _whole(doc, doc.at(root, "target"), "target is not an integer")
    var keep = _whole(doc, doc.at(root, "keep"), "keep is not an integer")
    var small = _flag(doc, doc.at(root, "small"), "small is not a bool")
    var chosen = PyJson.parse(
        target_text(
            '{"mode":"collapse","triangles":'
            + String(doc.length(triangles))
            + ',"target":'
            + String(target)
            + ',"small":'
            + _bool(small)
            + ',"keep":'
            + String(keep)
            + "}"
        )
    )
    if _flag(chosen, chosen.at(chosen.root, "whole"), "whole is not a bool"):
        return '{"same":true}'
    var count = _whole(
        chosen, chosen.at(chosen.root, "count"), "count is not an integer"
    )
    var collapsed = PyJson.parse(
        simplify_text(
            '{"points":'
            + _dump(doc, positions)
            + ',"triangles":'
            + _dump(doc, triangles)
            + ',"target":'
            + String(count)
            + ',"border":true}'
        )
    )
    var replay = PyJson.parse(
        simplify_text(
            '{"mode":"replay","points":'
            + _dump(doc, positions)
            + ',"triangles":'
            + _dump(doc, triangles)
            + ',"collapses":'
            + _dump(collapsed, collapsed.at(collapsed.root, "collapses"))
            + "}"
        )
    )
    var faces = replay.at(replay.root, "triangles")
    if replay.kind(faces) != PY_LIST or replay.length(faces) == 0:
        return '{"same":true}'
    var points = replay.at(replay.root, "points")
    var mapped = PyJson.parse(
        collapse_text(
            '{"mapping":'
            + _dump(replay, replay.at(replay.root, "mapping"))
            + ',"count":'
            + String(replay.length(points))
            + "}"
        )
    )
    var copied = PyJson.parse(
        collapse_text(
            '{"source":'
            + _dump(mapped, mapped.at(mapped.root, "source"))
            + ',"values":'
            + _flat_pairs(doc, uvs)
            + ',"width":2}'
        )
    )
    var folder = mkdtemp(prefix="town simplify ")
    var normal_path = folder + "/normals.json"
    Path(normal_path).write_text(
        '{"points":'
        + _dump(replay, points)
        + ',"faces":'
        + _dump(replay, faces)
        + "}"
    )
    var normals = PyJson.parse(normals_text(normal_path))
    _remove_tree(folder)
    var out = String('{"positions":')
    out += _dump(replay, points)
    out += ',"normals":'
    out += _dump(normals, normals.root)
    out += ',"uvs":'
    out += _pairs(_dump(copied, copied.at(copied.root, "values")))
    out += ',"triangles":'
    out += _dump(replay, faces)
    out += ',"material":'
    out += _dump(doc, doc.at(root, "material"))
    out += "}"
    return out^


def _weld(doc: PyJson, root: Int) raises -> String:
    """Gather corners into cells, then collapse the far mesh."""
    var positions = doc.at(root, "positions")
    var uvs = doc.at(root, "uvs")
    var triangles = doc.at(root, "triangles")
    var target = _whole(doc, doc.at(root, "target"), "target is not an integer")
    var chosen = PyJson.parse(
        target_text(
            '{"mode":"weld","triangles":'
            + String(doc.length(triangles))
            + ',"target":'
            + String(target)
            + "}"
        )
    )
    if _flag(chosen, chosen.at(chosen.root, "whole"), "whole is not a bool"):
        return '{"same":true}'
    var welded = PyJson.parse(
        weld_text(
            '{"positions":'
            + _dump(doc, positions)
            + ',"triangles":'
            + _dump(doc, triangles)
            + ',"divisions":'
            + String(DIVISIONS)
            + ',"minimum":0.25}'
        )
    )
    if _marked(welded):
        return '{"empty":true}'
    var joined = welded.at(welded.root, "triangles")
    if welded.kind(joined) != PY_LIST or welded.length(joined) == 0:
        return '{"empty":true}'
    var points = welded.at(welded.root, "points")
    var again = PyJson.parse(
        target_text(
            '{"mode":"weld","triangles":'
            + String(welded.length(joined))
            + ',"target":'
            + String(target)
            + "}"
        )
    )
    var prepare: String
    if not _flag(again, again.at(again.root, "whole"), "whole is not a bool"):
        var count = _whole(
            again, again.at(again.root, "count"), "count is not an integer"
        )
        var collapsed = PyJson.parse(
            simplify_text(
                '{"points":'
                + _dump(welded, points)
                + ',"triangles":'
                + _dump(welded, joined)
                + ',"target":'
                + String(count)
                + ',"border":false}'
            )
        )
        var replay = PyJson.parse(
            simplify_text(
                '{"mode":"replay","points":'
                + _dump(welded, points)
                + ',"triangles":'
                + _dump(welded, joined)
                + ',"collapses":'
                + _dump(collapsed, collapsed.at(collapsed.root, "collapses"))
                + "}"
            )
        )
        var faces = replay.at(replay.root, "triangles")
        if replay.kind(faces) != PY_LIST or replay.length(faces) == 0:
            return '{"empty":true}'
        prepare = finish_text(
            '{"mode":"prepare","points":'
            + _dump(replay, replay.at(replay.root, "points"))
            + ',"triangles":'
            + _dump(replay, faces)
            + ',"box":'
            + _dump(doc, positions)
            + "}"
        )
    else:
        prepare = finish_text(
            '{"mode":"prepare","points":'
            + _dump(welded, points)
            + ',"triangles":'
            + _dump(welded, joined)
            + "}"
        )
    var prepared = PyJson.parse(prepare)
    if _marked(prepared):
        return '{"empty":true}'
    var corners = prepared.at(prepared.root, "corners")
    var face = prepared.at(prepared.root, "normals")
    var placed = _transfer(doc, positions, uvs, triangles, prepared, corners)
    var wound = PyJson.parse(
        finish_text(
            '{"mode":"wind","corners":'
            + _dump(prepared, corners)
            + ',"normals":'
            + _dump(prepared, face)
            + ',"uvs":'
            + placed.uvs
            + ',"facing":'
            + placed.facing
            + "}"
        )
    )
    var out = String('{"positions":')
    out += _dump(wound, wound.at(wound.root, "positions"))
    out += ',"normals":'
    out += _dump(wound, wound.at(wound.root, "normals"))
    out += ',"uvs":'
    out += _dump(wound, wound.at(wound.root, "uvs"))
    out += ',"triangles":'
    out += _dump(wound, wound.at(wound.root, "triangles"))
    out += ',"material":'
    out += _dump(doc, doc.at(root, "material"))
    out += "}"
    return out^


@fieldwise_init
struct _Placed:
    var uvs: String
    var facing: String


def _transfer(
    doc: PyJson,
    positions: Int,
    uvs: Int,
    triangles: Int,
    prepared: PyJson,
    corners: Int,
) raises -> _Placed:
    """Return texture coordinates and the original normal of each new face."""
    var gathered = PyJson.parse(
        choose_text(
            '{"mode":"source","positions":'
            + _dump(doc, positions)
            + ',"triangles":'
            + _dump(doc, triangles)
            + "}"
        )
    )
    var count = CANDIDATES
    if doc.length(triangles) < count:
        count = doc.length(triangles)
    var found = PyJson.parse(
        near_text(
            '{"centers":'
            + _dump(gathered, gathered.at(gathered.root, "centers"))
            + ',"corners":'
            + _dump(prepared, corners)
            + ',"count":'
            + String(count)
            + "}"
        )
    )
    var chosen = PyJson.parse(
        choose_text(
            '{"mode":"choose","centers":'
            + _dump(gathered, gathered.at(gathered.root, "centers"))
            + ',"normals":'
            + _dump(gathered, gathered.at(gathered.root, "normals"))
            + ',"queries":'
            + _dump(found, found.at(found.root, "queries"))
            + ',"faces":'
            + _dump(prepared, prepared.at(prepared.root, "normals"))
            + ',"near":'
            + _dump(found, found.at(found.root, "near"))
            + "}"
        )
    )
    var best = chosen.at(chosen.root, "best")
    var sources = String("[")
    var texture = String("[")
    var facing = String("[")
    for index in range(chosen.length(best)):
        if index > 0:
            sources += ","
            texture += ","
            facing += ","
        var face = _whole(
            chosen, chosen.item(best, index), "index is not an integer"
        )
        sources += _face_points(doc, positions, triangles, face)
        texture += _face_uvs(doc, uvs, triangles, face)
        facing += _dump(
            gathered, gathered.item(gathered.at(gathered.root, "normals"), face)
        )
    sources += "]"
    texture += "]"
    facing += "]"
    var projected = PyJson.parse(
        uv_text(
            '{"source":'
            + sources
            + ',"uvs":'
            + texture
            + ',"corners":'
            + _dump(prepared, corners)
            + "}"
        )
    )
    return _Placed(
        _dump(projected, projected.at(projected.root, "uvs")), facing^
    )


def _face_points(
    doc: PyJson, positions: Int, triangles: Int, face: Int
) raises -> String:
    """Return the three corners of one original triangle."""
    return _face_rows(doc, positions, triangles, face)


def _face_uvs(
    doc: PyJson, uvs: Int, triangles: Int, face: Int
) raises -> String:
    """Return the three texture coordinates of one original triangle."""
    return _face_rows(doc, uvs, triangles, face)


def _face_rows(
    doc: PyJson, rows: Int, triangles: Int, face: Int
) raises -> String:
    """Return the rows named by one triangle."""
    if face < 0 or face >= doc.length(triangles):
        raise Error("index is out of range")
    var triangle = doc.item(triangles, face)
    if doc.kind(triangle) != PY_LIST or doc.length(triangle) != 3:
        raise Error("triangle is not three indices")
    var out = String("[")
    for corner in range(3):
        if corner > 0:
            out += ","
        var vertex = _whole(
            doc, doc.item(triangle, corner), "index is not an integer"
        )
        if vertex < 0 or vertex >= doc.length(rows):
            raise Error("index is out of range")
        out += _dump(doc, doc.item(rows, vertex))
    out += "]"
    return out^


def _flat_pairs(doc: PyJson, rows: Int) raises -> String:
    """Return texture coordinates as one flat list."""
    if doc.kind(rows) != PY_LIST:
        raise Error("uvs are not a list")
    var out = String("[")
    var first = True
    for index in range(doc.length(rows)):
        var pair = doc.item(rows, index)
        if doc.kind(pair) != PY_LIST or doc.length(pair) != 2:
            raise Error("uv is not 2 numbers")
        for axis in range(2):
            if not first:
                out += ","
            first = False
            out += _dump(doc, doc.item(pair, axis))
    out += "]"
    return out^


def _pairs(flat: String) raises -> String:
    """Group a flat JSON number list into pairs."""
    var doc = PyJson.parse(flat)
    if doc.kind(doc.root) != PY_LIST or doc.length(doc.root) % 2 != 0:
        raise Error("uvs do not match the points")
    var out = String("[")
    var index = 0
    while index < doc.length(doc.root):
        if index > 0:
            out += ","
        out += "["
        out += _dump(doc, doc.item(doc.root, index))
        out += ","
        out += _dump(doc, doc.item(doc.root, index + 1))
        out += "]"
        index += 2
    out += "]"
    return out^


def _dump(doc: PyJson, node: Int) raises -> String:
    """Return one value as canonical JSON."""
    return doc.subtree(node).dumps()


def _marked(doc: PyJson) -> Bool:
    """Return whether a tool answered `empty`."""
    var node = doc.find(doc.root, "empty")
    if node == MISSING or doc.kind(node) != PY_BOOL:
        return False
    return doc.flag(node)


def _flag(doc: PyJson, node: Int, message: String) raises -> Bool:
    """Return a JSON bool, or raise `message`."""
    if doc.kind(node) != PY_BOOL:
        raise Error(message)
    return doc.flag(node)


def _bool(value: Bool) -> String:
    """Return a JSON bool."""
    if value:
        return "true"
    return "false"


def _whole(doc: PyJson, node: Int, message: String) raises -> Int:
    """Return a JSON integer, or raise `message`."""
    if doc.kind(node) != PY_INT:
        raise Error(message)
    return Int(parse_float(doc.text(node)))


def main() raises:
    """Print the simplified mesh for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_simplify FILE", file=stderr)
        exit(2)
    try:
        print(town_simplify_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_simplify:", error, file=stderr)
        exit(1)
