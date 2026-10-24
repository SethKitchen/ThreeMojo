# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read a UModel glTF mesh the way the town bake reads it.

    carla_town_mesh MESH.gltf

The program prints each primitive's positions, normals, texture
coordinates, triangles and material name. A missing normal is
`[0, 1, 0]`. A missing texture coordinate is zero. Values match NumPy's
conversion to `float64` and `int64`.
"""

from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tools import quote_ascii
from tools._json_tree import NOTHING, JsonTree
from tools._python_float import python_repr


def mesh_text(path: String) raises -> String:
    """Return the primitives of a glTF file as JSON.

    Args:
        path: The `.gltf` file. Its buffer sits beside it.

    Returns:
        A JSON array. Each object has `material`, `positions`, `normals`,
        `uvs` and `triangles`.

    Raises:
        Error: If the file, its buffer, or an accessor is not readable.
    """
    var tree = JsonTree()
    var root = tree.parse(Path(path).read_text())
    var buffers = tree.item(root, "buffers")
    var uri = tree.text(tree.item(_at(tree, buffers, 0), "uri"))
    var data = Path(_join(_directory(path), uri)).read_bytes()
    var meshes = tree.item(root, "meshes")
    var out = String("[")
    var first = True
    var mesh_items = tree.items(meshes)
    for mesh_index in range(len(mesh_items)):
        var primitives = tree.item(mesh_items[mesh_index], "primitives")
        var parts = tree.items(primitives)
        for part_index in range(len(parts)):
            if not first:
                out += ","
            first = False
            out += _primitive(tree, root, data, parts[part_index])
    out += "]"
    return out^


def _primitive(
    mut tree: JsonTree, root: Int, data: List[UInt8], primitive: Int
) raises -> String:
    """Return one primitive's JSON object."""
    var attributes = tree.item(primitive, "attributes")
    var positions = _vectors(
        tree,
        root,
        data,
        tree.int_value(tree.item(attributes, "POSITION")),
    )
    var vertex_count = len(positions) // 3
    var normals: List[Float64]
    var normal_index = tree.get(attributes, "NORMAL")
    if normal_index == NOTHING:
        normals = List[Float64]()
        for _ in range(vertex_count):
            normals.append(0.0)
            normals.append(1.0)
            normals.append(0.0)
    else:
        normals = _vectors(tree, root, data, tree.int_value(normal_index))
    var uvs: List[Float64]
    var uv_index = tree.get(attributes, "TEXCOORD_0")
    if uv_index == NOTHING:
        uvs = List[Float64]()
        for _ in range(vertex_count * 2):
            uvs.append(0.0)
    else:
        uvs = _vectors(tree, root, data, tree.int_value(uv_index))
    var indexes = _scalars(
        tree, root, data, tree.int_value(tree.item(primitive, "indices"))
    )
    var name = String("")
    var material = tree.get(primitive, "material")
    if material != NOTHING:
        var materials = tree.item(root, "materials")
        var chosen = _at(tree, materials, tree.int_value(material))
        var named = tree.get(chosen, "name")
        if named != NOTHING:
            name = tree.text(named)
    var out = String('{"material":')
    out += quote_ascii(name)
    out += ',"positions":'
    out += _grouped(positions, 3)
    out += ',"normals":'
    out += _grouped(normals, 3)
    out += ',"uvs":'
    out += _grouped(uvs, 2)
    out += ',"triangles":'
    out += _grouped_ints(indexes)
    out += "}"
    return out^


def _vectors(
    mut tree: JsonTree, root: Int, data: List[UInt8], accessor_index: Int
) raises -> List[Float64]:
    """Return an accessor's components as floats."""
    var spec = _spec(tree, root, accessor_index)
    var out = List[Float64]()
    var stride = _size(spec.component)
    for index in range(spec.count):
        out.append(_float_at(data, spec.start + index * stride, spec.component))
    return out^


def _scalars(
    mut tree: JsonTree, root: Int, data: List[UInt8], accessor_index: Int
) raises -> List[Int]:
    """Return an index accessor as integers."""
    var spec = _spec(tree, root, accessor_index)
    var out = List[Int]()
    var stride = _size(spec.component)
    for index in range(spec.count):
        out.append(_int_at(data, spec.start + index * stride, spec.component))
    return out^


struct _Spec(Movable):
    """Where an accessor's components sit in the buffer."""

    var start: Int
    """The first byte."""
    var count: Int
    """The number of components."""
    var component: Int
    """The glTF component type."""

    def __init__(out self, start: Int, count: Int, component: Int):
        """Store one accessor."""
        self.start = start
        self.count = count
        self.component = component


def _spec(mut tree: JsonTree, root: Int, accessor_index: Int) raises -> _Spec:
    """Return the byte range of one accessor."""
    var accessors = tree.item(root, "accessors")
    var accessor = _at(tree, accessors, accessor_index)
    var views = tree.item(root, "bufferViews")
    var view = _at(
        tree, views, tree.int_value(tree.item(accessor, "bufferView"))
    )
    var width = _width(tree.text(tree.item(accessor, "type")))
    var component = tree.int_value(tree.item(accessor, "componentType"))
    var count = tree.int_value(tree.item(accessor, "count")) * width
    var start = _optional_int(tree, view, "byteOffset") + _optional_int(
        tree, accessor, "byteOffset"
    )
    return _Spec(start, count, component)


def _optional_int(tree: JsonTree, node: Int, key: String) raises -> Int:
    """Return an integer member, or 0 when it is absent."""
    var found = tree.get(node, key)
    if found == NOTHING:
        return 0
    return tree.int_value(found)


def _width(kind: String) raises -> Int:
    """Return how many components one element has."""
    if kind == "SCALAR":
        return 1
    if kind == "VEC2":
        return 2
    if kind == "VEC3":
        return 3
    if kind == "VEC4":
        return 4
    raise Error("unsupported accessor type")


def _size(component: Int) raises -> Int:
    """Return the byte size of one component."""
    if component == 5121:
        return 1
    if component == 5123:
        return 2
    if component == 5125 or component == 5126:
        return 4
    raise Error("unsupported component type")


def _float_at(data: List[UInt8], at: Int, component: Int) raises -> Float64:
    """Return one component as `float64`."""
    if component == 5126:
        return _f32(data, at)
    if component == 5121:
        return Float64(_u8(data, at))
    if component == 5123:
        return Float64(_u16(data, at))
    if component == 5125:
        return Float64(_u32(data, at))
    raise Error("unsupported component type")


def _int_at(data: List[UInt8], at: Int, component: Int) raises -> Int:
    """Return one component as `int64`, truncating a float toward zero."""
    if component == 5121:
        return _u8(data, at)
    if component == 5123:
        return _u16(data, at)
    if component == 5125:
        return _u32(data, at)
    if component == 5126:
        return Int(_f32(data, at))
    raise Error("unsupported component type")


def _need(data: List[UInt8], at: Int, size: Int) raises:
    """Refuse a read past the end of the buffer."""
    if at < 0 or size < 0 or at > len(data) or size > len(data) - at:
        raise Error("truncated mesh")


def _u8(data: List[UInt8], at: Int) raises -> Int:
    """Return one unsigned byte."""
    _need(data, at, 1)
    return Int(data[at])


def _u16(data: List[UInt8], at: Int) raises -> Int:
    """Return one little-endian unsigned 16-bit value."""
    _need(data, at, 2)
    return Int(data[at]) | (Int(data[at + 1]) << 8)


def _u32(data: List[UInt8], at: Int) raises -> Int:
    """Return one little-endian unsigned 32-bit value."""
    _need(data, at, 4)
    var value = Int(data[at])
    value |= Int(data[at + 1]) << 8
    value |= Int(data[at + 2]) << 16
    value |= Int(data[at + 3]) << 24
    return value


def _f32(data: List[UInt8], at: Int) raises -> Float64:
    """Return one little-endian float32, widened to float64."""
    var bits = UInt32(_u32(data, at))
    return Float64(bitcast[DType.float32](bits))


def _grouped(values: List[Float64], width: Int) raises -> String:
    """Return floats as a JSON array of arrays."""
    var out = String("[")
    var count = len(values) // width
    for index in range(count):
        if index > 0:
            out += ","
        out += "["
        for axis in range(width):
            if axis > 0:
                out += ","
            out += python_repr(values[index * width + axis])
        out += "]"
    out += "]"
    return out^


def _grouped_ints(values: List[Int]) -> String:
    """Return indexes as a JSON array of triples."""
    var out = String("[")
    var count = len(values) // 3
    for index in range(count):
        if index > 0:
            out += ","
        out += "["
        out += String(values[index * 3])
        out += ","
        out += String(values[index * 3 + 1])
        out += ","
        out += String(values[index * 3 + 2])
        out += "]"
    out += "]"
    return out^


def _at(tree: JsonTree, node: Int, index: Int) raises -> Int:
    """Return one array item."""
    var items = tree.items(node)
    if index < 0 or index >= len(items):
        raise Error("list index out of range")
    return items[index]


def _directory(path: String) -> String:
    """Return the directory that holds `path`."""
    var slash = path.rfind("/")
    if slash < 0:
        return String("")
    return String(path[byte=:slash])


def _join(directory: String, name: String) -> String:
    """Join a directory and a relative buffer name."""
    if directory.byte_length() == 0:
        return name
    return directory + "/" + name


def main() raises:
    """Print the primitives of the glTF file named on the command line."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_mesh MESH.gltf", file=stderr)
        exit(2)
    try:
        print(mesh_text(arguments[1]))
    except error:
        print("carla_town_mesh:", error, file=stderr)
        exit(1)
