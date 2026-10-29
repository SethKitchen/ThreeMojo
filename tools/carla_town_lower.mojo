# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Lower one town mesh to the triangle count its level allows.

    carla_town_lower FILE

`FILE` is JSON. It has the mesh, its `kind`, `mesh` path, part `index`,
mesh `total`, `masked`, `lod`, `factor` and `keep`. A zero budget keeps
nothing. A masked mesh keeps leaf cards. Any other mesh is simplified.
Level 0 keeps open edges. A later level welds corners first. `whole`
means the mesh stays as it is.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import MISSING, PY_BOOL, PY_DICT, PY_LIST, PyJson
from tools.carla_simplify_target import target_text
from tools.carla_town_budget import far_budget, near_budget
from tools.carla_town_cards import cards_text
from tools.carla_town_simplify import town_simplify_text
from tools._town_json import (
    json_compact,
    json_member,
    json_named_int,
    json_quote,
    json_text,
)


def lower_text(text: String) raises -> String:
    """Return one lowered mesh, or the decision to keep or drop it.

    Args:
        text: JSON with the mesh and the level. `lod` 0 is the near
            level. `factor` is that kind's share of the town cap.
            `keep` is the triangle floor passed to a bordered collapse.

    Returns:
        `{"action":"none"}` when the level keeps nothing.
        `{"action":"whole"}` when the mesh stays unchanged.
        `{"action":"mesh",...}` with positions, normals, texture
        coordinates and triangles when the mesh changes.

    Raises:
        Error: If the JSON is not that mesh, a count is negative, or
            the collapse cannot run.
    """
    var doc = PyJson.parse(text)
    if doc.kind(doc.root) != PY_DICT:
        raise Error("lower request is not an object")
    var kind = json_text(
        doc, json_member(doc, doc.root, "kind"), "kind is not text"
    )
    var mesh = json_text(
        doc, json_member(doc, doc.root, "mesh"), "mesh is not text"
    )
    var index = json_named_int(
        doc, json_member(doc, doc.root, "index"), "index"
    )
    var total = json_named_int(
        doc, json_member(doc, doc.root, "total"), "total"
    )
    var lod = json_named_int(doc, json_member(doc, doc.root, "lod"), "lod")
    var keep = json_named_int(doc, json_member(doc, doc.root, "keep"), "keep")
    if index < 0 or total < 0 or lod < 0 or keep < 0:
        raise Error("count is negative")
    var masked = _flag(
        doc, json_member(doc, doc.root, "masked"), "masked is not a bool"
    )
    var triangles = _listed(
        doc, doc.root, "triangles", "triangles are not a list"
    )
    var positions = _listed(
        doc, doc.root, "positions", "positions are not a list"
    )
    var normals = _listed(doc, doc.root, "normals", "normals are not a list")
    var uvs = _listed(doc, doc.root, "uvs", "uvs are not a list")
    _ = json_text(
        doc, json_member(doc, doc.root, "material"), "material is not text"
    )
    var count = doc.length(triangles)
    var budget = far_budget(kind, total, mesh)
    if lod == 0:
        budget = near_budget(kind, total, mesh)
    var chosen_text = target_text(
        '{"mode":"share","budget":'
        + String(budget)
        + ',"factor":'
        + json_compact(doc, json_member(doc, doc.root, "factor"))
        + ',"triangles":'
        + String(count)
        + ',"total":'
        + String(total)
        + ',"masked":'
        + _json_bool(masked)
        + ',"keep":'
        + String(keep)
        + "}"
    )
    var chosen = PyJson.parse(chosen_text)
    var action = json_text(
        chosen, chosen.at(chosen.root, "action"), "action is not text"
    )
    if action == "none" or action == "whole":
        return '{"action":"' + action + '"}'
    if action == "cards":
        return _cards(
            doc, positions, normals, uvs, triangles, mesh, index, lod, chosen
        )
    if action == "simplify":
        return _simplify(
            doc,
            positions,
            uvs,
            triangles,
            lod,
            keep,
            chosen,
        )
    raise Error("action is not none, whole, cards or simplify")


def _cards(
    doc: PyJson,
    positions: Int,
    normals: Int,
    uvs: Int,
    triangles: Int,
    mesh: String,
    index: Int,
    lod: Int,
    chosen: PyJson,
) raises -> String:
    """Return thinned leaf cards, or `whole` when the cards stay."""
    var seed_text = cards_text(
        '{"mode":"seed","path":'
        + json_quote(mesh)
        + ',"index":'
        + String(index)
        + ',"lod":'
        + String(lod)
        + "}"
    )
    var seed_doc = PyJson.parse(seed_text)
    var seed = json_named_int(
        seed_doc, seed_doc.at(seed_doc.root, "seed"), "seed"
    )
    var thinned = cards_text(
        '{"positions":'
        + json_compact(doc, positions)
        + ',"normals":'
        + json_compact(doc, normals)
        + ',"uvs":'
        + json_compact(doc, uvs)
        + ',"triangles":'
        + json_compact(doc, triangles)
        + ',"keep":'
        + json_compact(chosen, chosen.at(chosen.root, "keep"))
        + ',"seed":'
        + String(seed)
        + "}"
    )
    var parsed = PyJson.parse(thinned)
    if parsed.get(parsed.root, "unchanged") != MISSING:
        return '{"action":"whole"}'
    return _mesh(thinned)


def _simplify(
    doc: PyJson,
    positions: Int,
    uvs: Int,
    triangles: Int,
    lod: Int,
    keep: Int,
    chosen: PyJson,
) raises -> String:
    """Return a collapsed mesh, or `whole` or `none` when it does not change."""
    var mode = String("weld")
    if lod == 0:
        mode = "border"
    var target = json_named_int(
        chosen, chosen.at(chosen.root, "target"), "target"
    )
    var small = _flag(
        chosen, chosen.at(chosen.root, "small"), "small is not a bool"
    )
    var simplified = town_simplify_text(
        '{"mode":"'
        + mode
        + '","positions":'
        + json_compact(doc, positions)
        + ',"uvs":'
        + json_compact(doc, uvs)
        + ',"triangles":'
        + json_compact(doc, triangles)
        + ',"material":'
        + json_compact(doc, json_member(doc, doc.root, "material"))
        + ',"target":'
        + String(target)
        + ',"small":'
        + _json_bool(small)
        + ',"keep":'
        + String(keep)
        + "}"
    )
    var parsed = PyJson.parse(simplified)
    if _true(parsed, "same"):
        return '{"action":"whole"}'
    if _true(parsed, "empty"):
        return '{"action":"none"}'
    return _mesh(simplified)


def _mesh(text: String) raises -> String:
    """Return a changed mesh wrapped as an action."""
    var out = String('{"action":"mesh","positions":')
    out += _array_of(text, "positions")
    out += ',"normals":'
    out += _array_of(text, "normals")
    out += ',"uvs":'
    out += _array_of(text, "uvs")
    out += ',"triangles":'
    out += _array_of(text, "triangles")
    out += "}"
    return out


def _true(doc: PyJson, key: String) raises -> Bool:
    """Return whether a bool member is present and true."""
    var node = doc.get(doc.root, key)
    if node == MISSING:
        return False
    if doc.kind(node) != PY_BOOL:
        raise Error(key + " is not a bool")
    return doc.flag(node)


def _array_of(text: String, key: String) raises -> String:
    """Return the JSON array stored at `key`."""
    var marker = String('"') + key + '":'
    var start = text.find(marker)
    if start < 0:
        raise Error("lowered mesh has no " + key)
    var raw = text.as_bytes()
    var at = start + len(marker.as_bytes())
    while at < len(raw) and raw[at] == 32:
        at += 1
    if at >= len(raw) or raw[at] != 91:
        raise Error("lowered mesh has no " + key)
    var depth = 0
    var end = at
    var found = False
    for index in range(at, len(raw)):
        var byte = raw[index]
        if byte == 91:
            depth += 1
        elif byte == 93:
            depth -= 1
            if depth == 0:
                end = index + 1
                found = True
                break
    if not found:
        raise Error("lowered mesh has no " + key)
    return String(text[byte=at:end])


def _listed(doc: PyJson, node: Int, key: String, message: String) raises -> Int:
    """Return a member that must be a list."""
    var found = json_member(doc, node, key)
    if doc.kind(found) != PY_LIST:
        raise Error(message)
    return found


def _flag(doc: PyJson, node: Int, message: String) raises -> Bool:
    """Return a JSON bool, or raise `message`."""
    if doc.kind(node) != PY_BOOL:
        raise Error(message)
    return doc.flag(node)


def _json_bool(value: Bool) -> String:
    """Return a JSON bool."""
    if value:
        return "true"
    return "false"


def main() raises:
    """Print the lowered mesh for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_lower FILE", file=stderr)
        exit(2)
    try:
        print(lower_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_lower:", error, file=stderr)
        exit(1)
