# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Place town copies and merge them by tile.

    carla_town_group FILE

`FILE` is JSON. It has `tile`, the tile width in meters, and `parts`.
Each part has `lod`, `kind`, `material`, `positions`, `normals`, `uvs`,
`triangles` and `copies`. A copy has a `matrix`. A spline copy also has
`spline`. The program places each copy. It merges copies that share a
level, a kind, a tile and a material, in the order it first sees them.
"""

from std.collections import Dict
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
from tools.carla_town_bend import bend_text
from tools.carla_town_place import cell_text, place_rigid
from tools.carla_town_spline import spline_text
from tools._town_json import (
    json_compact,
    json_member,
    json_named_int,
    json_quote,
    json_text,
)


def group_text(text: String) raises -> String:
    """Return placed copies merged by level, kind, tile and material.

    Args:
        text: JSON with `tile` and `parts`. Each part carries its mesh
            and its copies. A spline copy carries `spline`.

    Returns:
        JSON with `groups`. Each group has `lod`, `kind`, `cell`,
        `material`, and one chunk per copy for `positions`, `normals`,
        `uvs` and `triangles`.

    Raises:
        Error: If the JSON is not that request, a matrix cannot be
            placed, or a spline is not usable.
    """
    var doc = PyJson.parse(text)
    if doc.kind(doc.root) != PY_DICT:
        raise Error("group request is not an object")
    var tile = _number(
        doc, json_member(doc, doc.root, "tile"), "tile is not a number"
    )
    if not (tile > 0.0):
        raise Error("tile is not positive")
    var parts = json_member(doc, doc.root, "parts")
    if doc.kind(parts) != PY_LIST:
        raise Error("parts are not a list")
    var index_of = Dict[String, Int]()
    var lods = List[Int]()
    var kinds = List[String]()
    var columns = List[Int]()
    var cell_rows = List[Int]()
    var materials = List[Int]()
    var positions = List[List[String]]()
    var normals = List[List[String]]()
    var uvs = List[List[String]]()
    var triangles = List[List[String]]()
    for index in range(doc.length(parts)):
        var part = doc.item(parts, index)
        if doc.kind(part) != PY_DICT:
            raise Error("part is not an object")
        _place_part(
            doc,
            part,
            tile,
            index_of,
            lods,
            kinds,
            columns,
            cell_rows,
            materials,
            positions,
            normals,
            uvs,
            triangles,
        )
    return _emit(
        lods,
        kinds,
        columns,
        cell_rows,
        materials,
        positions,
        normals,
        uvs,
        triangles,
    )


def _place_part(
    doc: PyJson,
    part: Int,
    tile: Float64,
    mut index_of: Dict[String, Int],
    mut lods: List[Int],
    mut kinds: List[String],
    mut columns: List[Int],
    mut cell_rows: List[Int],
    mut materials: List[Int],
    mut positions: List[List[String]],
    mut normals: List[List[String]],
    mut uvs: List[List[String]],
    mut triangles: List[List[String]],
) raises:
    """Place one part's copies into the groups."""
    var lod = json_named_int(doc, json_member(doc, part, "lod"), "lod")
    var kind = json_text(
        doc, json_member(doc, part, "kind"), "kind is not text"
    )
    var material = json_named_int(
        doc, json_member(doc, part, "material"), "material"
    )
    var point_values = _vec3(
        doc, json_member(doc, part, "positions"), "positions are not a list"
    )
    var normal_values = _vec3(
        doc, json_member(doc, part, "normals"), "normals are not a list"
    )
    var tri_values = _tris(doc, json_member(doc, part, "triangles"))
    var uv_json = json_compact(
        doc, _listed(doc, part, "uvs", "uvs are not a list")
    )
    var copies = json_member(doc, part, "copies")
    if doc.kind(copies) != PY_LIST:
        raise Error("copies are not a list")
    for index in range(doc.length(copies)):
        var copy = doc.item(copies, index)
        if doc.kind(copy) != PY_DICT:
            raise Error("copy is not an object")
        var matrix_node = json_member(doc, copy, "matrix")
        var matrix = _matrix(doc, matrix_node)
        var placed = _place_copy(
            doc,
            copy,
            matrix,
            matrix_node,
            point_values,
            normal_values,
            tri_values,
        )
        var cell = cell_text(matrix[12], matrix[13], tile)
        var pair = _split_cell(cell)
        var key = (
            String(lod)
            + "\t"
            + kind
            + "\t"
            + String(pair[0])
            + "\t"
            + String(pair[1])
            + "\t"
            + String(material)
        )
        var slot = _slot(
            index_of,
            lods,
            kinds,
            columns,
            cell_rows,
            materials,
            positions,
            normals,
            uvs,
            triangles,
            key,
            lod,
            kind,
            pair[0],
            pair[1],
            material,
        )
        positions[slot].append(placed[0])
        normals[slot].append(placed[1])
        uvs[slot].append(uv_json)
        triangles[slot].append(placed[2])


def _place_copy(
    doc: PyJson,
    copy: Int,
    matrix: List[Float64],
    matrix_node: Int,
    points: List[Float64],
    normals: List[Float64],
    triangles: List[Int],
) raises -> List[String]:
    """Return one copy's placed points, normals and triangles as JSON."""
    var spline = doc.get(copy, "spline")
    var placed: String
    if spline == MISSING:
        placed = place_rigid(matrix, points, normals, triangles)
    else:
        if doc.kind(spline) != PY_DICT:
            raise Error("spline is not an object")
        var bent = bend_text(_bend_request(doc, spline, points, normals))
        placed = spline_text(
            _spline_request(
                json_compact(doc, matrix_node),
                _array_of(bent, "points"),
                _array_of(bent, "normals"),
                _triangles_json(triangles),
            )
        )
    var out = List[String]()
    out.append(_array_of(placed, "points"))
    out.append(_array_of(placed, "normals"))
    out.append(_array_of(placed, "triangles"))
    return out^


def _slot(
    mut index_of: Dict[String, Int],
    mut lods: List[Int],
    mut kinds: List[String],
    mut columns: List[Int],
    mut cell_rows: List[Int],
    mut materials: List[Int],
    mut positions: List[List[String]],
    mut normals: List[List[String]],
    mut uvs: List[List[String]],
    mut triangles: List[List[String]],
    key: String,
    lod: Int,
    kind: String,
    column: Int,
    cell_row: Int,
    material: Int,
) raises -> Int:
    """Return the group for one key, creating it on the first sight."""
    if key in index_of:
        return index_of[key]
    var slot = len(lods)
    index_of[key] = slot
    lods.append(lod)
    kinds.append(kind)
    columns.append(column)
    cell_rows.append(cell_row)
    materials.append(material)
    positions.append(List[String]())
    normals.append(List[String]())
    uvs.append(List[String]())
    triangles.append(List[String]())
    return slot


def _emit(
    lods: List[Int],
    kinds: List[String],
    columns: List[Int],
    cell_rows: List[Int],
    materials: List[Int],
    positions: List[List[String]],
    normals: List[List[String]],
    uvs: List[List[String]],
    triangles: List[List[String]],
) -> String:
    """Return the groups in first-seen order."""
    var out = String('{"groups":[')
    for index in range(len(lods)):
        if index > 0:
            out += ","
        out += '{"lod":'
        out += String(lods[index])
        out += ',"kind":'
        out += json_quote(kinds[index])
        out += ',"cell":['
        out += String(columns[index])
        out += ","
        out += String(cell_rows[index])
        out += '],"material":'
        out += String(materials[index])
        out += ',"positions":'
        out += _join(positions[index])
        out += ',"normals":'
        out += _join(normals[index])
        out += ',"uvs":'
        out += _join(uvs[index])
        out += ',"triangles":'
        out += _join(triangles[index])
        out += "}"
    out += "]}"
    return out


def _bend_request(
    doc: PyJson, spline: Int, points: List[Float64], normals: List[Float64]
) raises -> String:
    """Return the bend request for one spline copy."""
    var out = String('{"points":')
    out += _vec3_json(points)
    out += ',"normals":'
    out += _vec3_json(normals)
    out += ',"forward_axis":'
    out += json_compact(doc, json_member(doc, spline, "forward_axis"))
    out += ',"start":'
    out += json_compact(doc, json_member(doc, spline, "start"))
    out += ',"end":'
    out += json_compact(doc, json_member(doc, spline, "end"))
    out += ',"start_tangent":'
    out += json_compact(doc, json_member(doc, spline, "start_tangent"))
    out += ',"end_tangent":'
    out += json_compact(doc, json_member(doc, spline, "end_tangent"))
    out += ',"start_roll":'
    out += json_compact(doc, json_member(doc, spline, "start_roll"))
    out += ',"end_roll":'
    out += json_compact(doc, json_member(doc, spline, "end_roll"))
    out += ',"start_scale":'
    out += json_compact(doc, json_member(doc, spline, "start_scale"))
    out += ',"end_scale":'
    out += json_compact(doc, json_member(doc, spline, "end_scale"))
    out += "}"
    return out


def _spline_request(
    matrix_json: String,
    points_json: String,
    normals_json: String,
    triangles_json: String,
) -> String:
    """Return the spline placement request."""
    var out = String('{"matrix":')
    out += matrix_json
    out += ',"positions":'
    out += points_json
    out += ',"normals":'
    out += normals_json
    out += ',"triangles":'
    out += triangles_json
    out += "}"
    return out


def _join(chunks: List[String]) -> String:
    """Return a JSON list of JSON values."""
    var out = String("[")
    for index in range(len(chunks)):
        if index > 0:
            out += ","
        out += chunks[index]
    out += "]"
    return out


def _vec3_json(values: List[Float64]) raises -> String:
    """Return 3-vectors as compact JSON."""
    var out = String("[")
    var count = len(values) // 3
    for index in range(count):
        if index > 0:
            out += ","
        var base = index * 3
        out += "["
        out += python_repr(values[base])
        out += ","
        out += python_repr(values[base + 1])
        out += ","
        out += python_repr(values[base + 2])
        out += "]"
    out += "]"
    return out


def _triangles_json(values: List[Int]) -> String:
    """Return triangles as compact JSON."""
    var out = String("[")
    var count = len(values) // 3
    for index in range(count):
        if index > 0:
            out += ","
        var base = index * 3
        out += "["
        out += String(values[base])
        out += ","
        out += String(values[base + 1])
        out += ","
        out += String(values[base + 2])
        out += "]"
    out += "]"
    return out


def _array_of(text: String, key: String) raises -> String:
    """Return the JSON array stored at `key`."""
    var marker = String('"') + key + '":'
    var start = text.find(marker)
    if start < 0:
        raise Error("placed mesh has no " + key)
    var raw = text.as_bytes()
    var at = start + len(marker.as_bytes())
    while at < len(raw) and raw[at] == 32:
        at += 1
    if at >= len(raw) or raw[at] != 91:
        raise Error("placed mesh has no " + key)
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
        raise Error("placed mesh has no " + key)
    return String(text[byte=at:end])


def _split_cell(text: String) raises -> Tuple[Int, Int]:
    """Return the column and row in a cell answer."""
    var tab = text.find("\t")
    if tab < 0:
        raise Error("tile failed")
    var column = Int(parse_float(String(text[byte=:tab])))
    var row = Int(parse_float(String(text[byte = tab + 1 :])))
    return (column, row)


def _matrix(doc: PyJson, node: Int) raises -> List[Float64]:
    """Read a 4 by 4 matrix in row-major order."""
    if doc.kind(node) != PY_LIST or doc.length(node) != 4:
        raise Error("a placement matrix has 4 rows")
    var out = List[Float64]()
    for row in range(4):
        var line = doc.item(node, row)
        if doc.kind(line) != PY_LIST or doc.length(line) != 4:
            raise Error("a placement matrix has 4 columns")
        for column in range(4):
            out.append(
                _number(
                    doc, doc.item(line, column), "coordinate is not a number"
                )
            )
    return out^


def _vec3(doc: PyJson, node: Int, message: String) raises -> List[Float64]:
    """Read an array of 3-vectors."""
    if doc.kind(node) != PY_LIST:
        raise Error(message)
    var out = List[Float64]()
    for index in range(doc.length(node)):
        var line = doc.item(node, index)
        if doc.kind(line) != PY_LIST or doc.length(line) != 3:
            raise Error("a vector needs three numbers")
        for column in range(3):
            out.append(
                _number(
                    doc, doc.item(line, column), "coordinate is not a number"
                )
            )
    return out^


def _tris(doc: PyJson, node: Int) raises -> List[Int]:
    """Read an array of triangles."""
    if doc.kind(node) != PY_LIST:
        raise Error("triangles are not a list")
    var out = List[Int]()
    for index in range(doc.length(node)):
        var line = doc.item(node, index)
        if doc.kind(line) != PY_LIST or doc.length(line) != 3:
            raise Error("a triangle needs three indexes")
        for column in range(3):
            out.append(json_named_int(doc, doc.item(line, column), "index"))
    return out^


def _listed(doc: PyJson, node: Int, key: String, message: String) raises -> Int:
    """Return a member that must be a list."""
    var found = json_member(doc, node, key)
    if doc.kind(found) != PY_LIST:
        raise Error(message)
    return found


def _number(doc: PyJson, node: Int, message: String) raises -> Float64:
    """Return a JSON number as a float."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error(message)


def main() raises:
    """Print the merged groups for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_group FILE", file=stderr)
        exit(2)
    try:
        print(group_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_group:", error, file=stderr)
        exit(1)
