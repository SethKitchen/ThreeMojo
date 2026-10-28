# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Pack one town's mesh groups into a glTF buffer.

    carla_town_buffers FILE

`FILE` is JSON. It names the binary output, the mesh groups and the lamp
heads. The program writes that binary and prints the glTF tables: buffer
views, accessors, meshes, nodes and the rounded lamp positions.
"""

from std.math import isinf, isnan
from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._python_float import parse_float, python_repr
from tools._python_json import PY_DICT, PY_FLOAT, PY_INT, PY_LIST, PyJson


def buffer_text(text: String) raises -> String:
    """Write the buffer named in `text` and return its glTF tables.

    Args:
        text: A JSON object with `bin`, `name`, `groups` and `lamps`.

    Returns:
        The buffer views, accessors, meshes, nodes, scene and buffer
        record, plus the near and far triangle counts.

    Raises:
        Error: If the JSON is not that request, or a value does not fit.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("buffer request is not an object")
    var bin_path = doc.text(doc.at(root, "bin"))
    var name = doc.text(doc.at(root, "name"))
    var groups = doc.at(root, "groups")
    if doc.kind(groups) != PY_LIST:
        raise Error("groups are not a list")
    var lods = List[Int]()
    var kinds = List[String]()
    var cell_x = List[Int]()
    var cell_y = List[Int]()
    var materials = List[Int]()
    var pos_at = List[Int]()
    var pos_n = List[Int]()
    var nrm_at = List[Int]()
    var uv_at = List[Int]()
    var tri_at = List[Int]()
    var tri_n = List[Int]()
    var px = List[Float64]()
    var py = List[Float64]()
    var pz = List[Float64]()
    var nx = List[Float64]()
    var ny = List[Float64]()
    var nz = List[Float64]()
    var us = List[Float64]()
    var vs = List[Float64]()
    var indices = List[Int]()
    for index in range(doc.length(groups)):
        var group = doc.item(groups, index)
        lods.append(_whole(doc, doc.at(group, "lod")))
        kinds.append(doc.text(doc.at(group, "kind")))
        var cell = doc.at(group, "cell")
        if doc.kind(cell) != PY_LIST or doc.length(cell) != 2:
            raise Error("cell is not two integers")
        cell_x.append(_whole(doc, doc.item(cell, 0)))
        cell_y.append(_whole(doc, doc.item(cell, 1)))
        materials.append(_whole(doc, doc.at(group, "material")))
        pos_at.append(len(px))
        nrm_at.append(len(nx))
        uv_at.append(len(us))
        tri_at.append(len(indices))
        var points = _chunks3(doc, doc.at(group, "positions"), px, py, pz)
        var norms = _chunks3(doc, doc.at(group, "normals"), nx, ny, nz)
        var textures = _chunks2(doc, doc.at(group, "uvs"), us, vs)
        if points != norms or points != textures:
            raise Error("attributes differ in length")
        if points == 0:
            raise Error("empty vector")
        pos_n.append(points)
        tri_n.append(
            _chunk_tris(
                doc,
                doc.at(group, "triangles"),
                doc.at(group, "positions"),
                indices,
            )
        )
    var order = List[Int]()
    for index in range(len(lods)):
        order.append(index)
    for index in range(1, len(order)):
        var key = order[index]
        var slot = index
        while slot > 0 and _before(
            key,
            order[slot - 1],
            lods,
            kinds,
            cell_x,
            cell_y,
            materials,
        ):
            order[slot] = order[slot - 1]
            slot -= 1
        order[slot] = key
    var blob = List[UInt8]()
    var views = String("[")
    var accessors = String("[")
    var meshes = String("[")
    var nodes = String("[")
    var near = 0
    var far = 0
    for place in range(len(order)):
        var index = order[place]
        if lods[index] != 0 and lods[index] != 1:
            raise Error("level is not 0 or 1")
        if place > 0:
            views += ","
            accessors += ","
            meshes += ","
            nodes += ","
        var start = pos_at[index]
        var count = pos_n[index]
        _attribute(
            views,
            accessors,
            blob,
            px,
            py,
            pz,
            start,
            count,
            3,
            "VEC3",
            34962,
            True,
        )
        views += ","
        accessors += ","
        _attribute(
            views,
            accessors,
            blob,
            nx,
            ny,
            nz,
            nrm_at[index],
            count,
            3,
            "VEC3",
            34962,
            True,
        )
        views += ","
        accessors += ","
        _attribute(
            views,
            accessors,
            blob,
            us,
            vs,
            vs,
            uv_at[index],
            count,
            2,
            "VEC2",
            34962,
            False,
        )
        views += ","
        accessors += ","
        _pad(blob)
        var offset = len(blob)
        var tri_start = tri_at[index]
        var tri_count = tri_n[index]
        var index_view = _objects(views)
        for triangle in range(tri_count * 3):
            _u32(blob, indices[tri_start + triangle])
        var byte_length = len(blob) - offset
        views += '{"buffer":0,"byteOffset":'
        views += String(offset)
        views += ',"byteLength":'
        views += String(byte_length)
        views += ',"target":34963}'
        accessors += '{"bufferView":'
        accessors += String(index_view)
        accessors += ',"componentType":5125,"count":'
        accessors += String(tri_count * 3)
        accessors += ',"type":"SCALAR"}'
        var position = _objects(accessors) - 4
        meshes += '{"primitives":[{"attributes":{"POSITION":'
        meshes += String(position)
        meshes += ',"NORMAL":'
        meshes += String(position + 1)
        meshes += ',"TEXCOORD_0":'
        meshes += String(position + 2)
        meshes += '},"indices":'
        meshes += String(position + 3)
        meshes += ',"material":'
        meshes += String(materials[index])
        meshes += "}]}"
        nodes += '{"name":"'
        nodes += kinds[index]
        nodes += "_"
        nodes += String(cell_x[index])
        nodes += "_"
        nodes += String(cell_y[index])
        nodes += "_lod"
        nodes += String(lods[index])
        nodes += '","mesh":'
        nodes += String(place)
        nodes += ',"extras":{"carla_kind":"'
        nodes += kinds[index]
        nodes += '","carla_lod":'
        nodes += String(lods[index])
        nodes += "}}"
        if lods[index] == 0:
            near += tri_count
        else:
            far += tri_count
    views += "]"
    accessors += "]"
    meshes += "]"
    nodes += "]"
    Path(bin_path).write_bytes(Span(blob))
    var lamps = _lamps(doc, doc.at(root, "lamps"))
    var out = String('{"triangles":[')
    out += String(near)
    out += ","
    out += String(far)
    out += '],"bufferViews":'
    out += views
    out += ',"accessors":'
    out += accessors
    out += ',"meshes":'
    out += meshes
    out += ',"nodes":'
    out += nodes
    out += ',"scenes":[{"nodes":['
    for place in range(len(order)):
        if place > 0:
            out += ","
        out += String(place)
    out += '],"extras":{"carla_lamps":'
    out += lamps
    out += '}}],"buffers":[{"byteLength":'
    out += String(len(blob))
    out += ',"uri":"'
    out += name
    out += '.bin"}]}'
    return out^


def _attribute(
    mut views: String,
    mut accessors: String,
    mut blob: List[UInt8],
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    start: Int,
    count: Int,
    width: Int,
    kind: String,
    target: Int,
    bounds: Bool,
) raises:
    """Append one float attribute and its glTF records."""
    var view_index = _objects(views)
    _pad(blob)
    var offset = len(blob)
    var low_x = 0.0
    var low_y = 0.0
    var low_z = 0.0
    var high_x = 0.0
    var high_y = 0.0
    var high_z = 0.0
    for index in range(count):
        var x = _stored(xs[start + index])
        var y = _stored(ys[start + index])
        _pack_f32(blob, x)
        _pack_f32(blob, y)
        if width == 3:
            var z = _stored(zs[start + index])
            _pack_f32(blob, z)
            if index == 0 or x < low_x:
                low_x = x
            if index == 0 or y < low_y:
                low_y = y
            if index == 0 or z < low_z:
                low_z = z
            if index == 0 or x > high_x:
                high_x = x
            if index == 0 or y > high_y:
                high_y = y
            if index == 0 or z > high_z:
                high_z = z
    views += '{"buffer":0,"byteOffset":'
    views += String(offset)
    views += ',"byteLength":'
    views += String(len(blob) - offset)
    views += ',"target":'
    views += String(target)
    views += "}"
    accessors += '{"bufferView":'
    accessors += String(view_index)
    accessors += ',"componentType":5126,"count":'
    accessors += String(count)
    accessors += ',"type":"'
    accessors += kind
    accessors += '"'
    if bounds:
        accessors += ',"min":['
        accessors += python_repr(low_x)
        accessors += ","
        accessors += python_repr(low_y)
        accessors += ","
        accessors += python_repr(low_z)
        accessors += '],"max":['
        accessors += python_repr(high_x)
        accessors += ","
        accessors += python_repr(high_y)
        accessors += ","
        accessors += python_repr(high_z)
        accessors += "]"
    accessors += "}"


def _objects(text: String) -> Int:
    """Return how many objects are already open in `text`."""
    var count = 0
    var bytes = text.as_bytes()
    for index in range(len(bytes)):
        if bytes[index] == 123:
            count += 1
    return count


def _before(
    left: Int,
    right: Int,
    lods: List[Int],
    kinds: List[String],
    cell_x: List[Int],
    cell_y: List[Int],
    materials: List[Int],
) -> Bool:
    """Return whether group `left` sorts before group `right`."""
    if lods[left] != lods[right]:
        return lods[left] < lods[right]
    if kinds[left] != kinds[right]:
        return _text_before(kinds[left], kinds[right])
    if cell_x[left] != cell_x[right]:
        return cell_x[left] < cell_x[right]
    if cell_y[left] != cell_y[right]:
        return cell_y[left] < cell_y[right]
    return materials[left] < materials[right]


def _text_before(left: String, right: String) -> Bool:
    """Return whether `left` sorts before `right`, byte by byte."""
    var a = left.as_bytes()
    var b = right.as_bytes()
    var count = len(a)
    if len(b) < count:
        count = len(b)
    for index in range(count):
        if a[index] != b[index]:
            return a[index] < b[index]
    return len(a) < len(b)


def _lamps(doc: PyJson, node: Int) raises -> String:
    """Return lamp heads rounded to three decimal places."""
    if doc.kind(node) != PY_LIST:
        raise Error("lamps are not a list")
    var out = String("[")
    var first = True
    for index in range(doc.length(node)):
        var head = doc.item(node, index)
        if doc.kind(head) != PY_LIST:
            raise Error("lamp is not a list")
        for axis in range(doc.length(head)):
            if not first:
                out += ","
            first = False
            out += python_repr(_round3(_number(doc, doc.item(head, axis))))
    out += "]"
    return out^


def _round3(value: Float64) raises -> Float64:
    """Return `round(value, 3)`, half to even."""
    if isnan(value) or isinf(value):
        return value
    var scaled = Fraction.from_float(value) * Fraction(1000)
    var parts = scaled.numerator.divmod(scaled.denominator)
    var quotient = parts[0].copy()
    var twice = parts[1] * BigInt(2)
    if twice > scaled.denominator:
        quotient = quotient + BigInt(1)
    elif twice == scaled.denominator and quotient.is_odd():
        quotient = quotient + BigInt(1)
    return (Fraction(quotient) / Fraction(1000)).to_float()


def _chunks3(
    doc: PyJson,
    node: Int,
    mut xs: List[Float64],
    mut ys: List[Float64],
    mut zs: List[Float64],
) raises -> Int:
    """Append chunks of 3-vectors and return how many points were added."""
    if doc.kind(node) != PY_LIST:
        raise Error("vectors are not a list")
    var added = 0
    for index in range(doc.length(node)):
        var before = len(xs)
        _vec3(doc, doc.item(node, index), xs, ys, zs)
        added += len(xs) - before
    return added


def _chunks2(
    doc: PyJson, node: Int, mut xs: List[Float64], mut ys: List[Float64]
) raises -> Int:
    """Append chunks of 2-vectors and return how many points were added."""
    if doc.kind(node) != PY_LIST:
        raise Error("vectors are not a list")
    var added = 0
    for index in range(doc.length(node)):
        var before = len(xs)
        _vec2(doc, doc.item(node, index), xs, ys)
        added += len(xs) - before
    return added


def _chunk_tris(
    doc: PyJson, node: Int, points: Int, mut indices: List[Int]
) raises -> Int:
    """Append each copy's triangles, shifted by the copies before it."""
    if doc.kind(node) != PY_LIST or doc.kind(points) != PY_LIST:
        raise Error("triangles are not a list")
    if doc.length(node) != doc.length(points):
        raise Error("triangles do not match the points")
    var added = 0
    var base = 0
    for index in range(doc.length(node)):
        var chunk = doc.item(node, index)
        var cloud = doc.item(points, index)
        if doc.kind(chunk) != PY_LIST or doc.kind(cloud) != PY_LIST:
            raise Error("triangles are not a list")
        for face in range(doc.length(chunk)):
            var triangle = doc.item(chunk, face)
            if doc.kind(triangle) != PY_LIST or doc.length(triangle) != 3:
                raise Error("triangle is not three indices")
            for corner in range(3):
                var value = _whole(doc, doc.item(triangle, corner)) + base
                if value < 0 or value > 4294967295:
                    raise Error("index does not fit in uint32")
                indices.append(value)
            added += 1
        base += doc.length(cloud)
    return added


def _vec3(
    doc: PyJson,
    node: Int,
    mut xs: List[Float64],
    mut ys: List[Float64],
    mut zs: List[Float64],
) raises:
    """Read a list of 3-vectors."""
    if doc.kind(node) != PY_LIST:
        raise Error("vectors are not a list")
    for index in range(doc.length(node)):
        var point = doc.item(node, index)
        if doc.kind(point) != PY_LIST or doc.length(point) != 3:
            raise Error("vector is not 3 numbers")
        xs.append(_number(doc, doc.item(point, 0)))
        ys.append(_number(doc, doc.item(point, 1)))
        zs.append(_number(doc, doc.item(point, 2)))


def _vec2(
    doc: PyJson, node: Int, mut xs: List[Float64], mut ys: List[Float64]
) raises:
    """Read a list of 2-vectors."""
    if doc.kind(node) != PY_LIST:
        raise Error("vectors are not a list")
    for index in range(doc.length(node)):
        var point = doc.item(node, index)
        if doc.kind(point) != PY_LIST or doc.length(point) != 2:
            raise Error("vector is not 2 numbers")
        xs.append(_number(doc, doc.item(point, 0)))
        ys.append(_number(doc, doc.item(point, 1)))


def _stored(value: Float64) -> Float64:
    """Return `value` rounded to float32 and back."""
    return Float64(Float32(value))


def _pack_f32(mut out: List[UInt8], value: Float64):
    """Append one little-endian float32."""
    var bits = UInt32(bitcast[DType.uint32](Float32(value)))
    out.append(UInt8(bits & 255))
    out.append(UInt8((bits >> 8) & 255))
    out.append(UInt8((bits >> 16) & 255))
    out.append(UInt8((bits >> 24) & 255))


def _u32(mut out: List[UInt8], value: Int):
    """Append one little-endian unsigned 32-bit value."""
    var rest = value
    for _ in range(4):
        out.append(UInt8(rest & 255))
        rest >>= 8


def _pad(mut data: List[UInt8]):
    """Append zero bytes until the length is a multiple of four."""
    while len(data) % 4 != 0:
        data.append(0)


def _number(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number as a float."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("coordinate is not a number")


def _whole(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error("index is not an integer")
    return Int(parse_float(doc.text(node)))


def main() raises:
    """Write the buffer for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_buffers FILE", file=stderr)
        exit(2)
    try:
        print(buffer_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_buffers:", error, file=stderr)
        exit(1)
