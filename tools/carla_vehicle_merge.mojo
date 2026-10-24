# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Append one glTF static mesh into a vehicle body.

    carla_vehicle_merge BASE.gltf BASE.bin EXTRA.gltf EXTRA.bin OUT.gltf OUT.bin

The extra buffer is appended after the base buffer. The base buffer is
padded with zero bytes so its length is a multiple of four. Views,
accessors, materials, meshes, nodes and scene roots are renumbered as
`export_vehicles.py` did.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tree import NOTHING, JsonTree


def merge_gltf(
    base_text: String,
    var base_bin: List[UInt8],
    extra_text: String,
    var extra_bin: List[UInt8],
) raises -> Tuple[String, List[UInt8]]:
    """Append `extra` into `base` and return the glTF text and buffer.

    Args:
        base_text: The body glTF, as `json.loads` reads it.
        base_bin: The body buffer. This function keeps the merged bytes.
        extra_text: The static mesh glTF.
        extra_bin: The static mesh buffer.

    Returns:
        The merged glTF text, as `json.dumps` writes it, and the merged
        buffer.

    Raises:
        Error: If either document is not the glTF this merge expects.
    """
    var base = JsonTree()
    var base_root = base.parse(base_text)
    var extra = JsonTree()
    var extra_root = extra.parse(extra_text)
    var shift = _pad(base_bin)
    for index in range(len(extra_bin)):
        base_bin.append(extra_bin[index])
    var view0 = _length(base, base.item(base_root, "bufferViews"))
    _append_copied(
        base,
        base.item(base_root, "bufferViews"),
        extra,
        extra.item(extra_root, "bufferViews"),
    )
    _shift_views(base, base.item(base_root, "bufferViews"), view0, shift)
    var acc0 = _length(base, base.item(base_root, "accessors"))
    _append_accessors(base, base_root, extra, extra_root, view0)
    var mat0 = _optional_length(base, base_root, "materials")
    _append_materials(base, base_root, extra, extra_root)
    var mesh0 = _length(base, base.item(base_root, "meshes"))
    _append_meshes(base, base_root, extra, extra_root, acc0, mat0)
    var node0 = _length(base, base.item(base_root, "nodes"))
    _append_nodes(base, base_root, extra, extra_root, mesh0, node0)
    _append_roots(base, base_root, extra, extra_root, node0)
    var buffers = base.item(base_root, "buffers")
    var first = _at(base, buffers, 0)
    base.set(first, "byteLength", base.integer(len(base_bin)))
    var text = base.dumps(base_root, False)
    return (text^, base_bin^)


def _pad(mut data: List[UInt8]) -> Int:
    """Pad `data` to a multiple of four and return the padded length."""
    while len(data) % 4 != 0:
        data.append(0)
    return len(data)


def _length(tree: JsonTree, node: Int) raises -> Int:
    """Return how many items an array holds."""
    return len(tree.items(node))


def _at(tree: JsonTree, node: Int, index: Int) raises -> Int:
    """Return one array item."""
    var items = tree.items(node)
    if index < 0 or index >= len(items):
        raise Error("list index out of range")
    return items[index]


def _optional_length(tree: JsonTree, root: Int, key: String) raises -> Int:
    """Return an array member's length, or 0 when the member is absent."""
    var found = tree.get(root, key)
    if found == NOTHING:
        return 0
    return _length(tree, found)


def _append_copied(
    mut base: JsonTree, into: Int, extra: JsonTree, source: Int
) raises:
    """Append a deep copy of every item in `source`."""
    var items = extra.items(source)
    for index in range(len(items)):
        base.append(into, base.adopt(extra, items[index]))


def _shift_views(mut base: JsonTree, views: Int, view0: Int, shift: Int) raises:
    """Set each appended view's buffer to 0 and move its byte offset."""
    var items = base.items(views)
    for index in range(view0, len(items)):
        var view = items[index]
        base.set(view, "buffer", base.integer(0))
        var offset = 0
        var found = base.get(view, "byteOffset")
        if found != NOTHING:
            offset = base.int_value(found)
        base.set(view, "byteOffset", base.integer(offset + shift))


def _append_accessors(
    mut base: JsonTree,
    base_root: Int,
    extra: JsonTree,
    extra_root: Int,
    view0: Int,
) raises:
    """Append accessors and move each `bufferView` by `view0`."""
    var into = base.item(base_root, "accessors")
    var source = extra.item(extra_root, "accessors")
    var items = extra.items(source)
    for index in range(len(items)):
        var copy = base.adopt(extra, items[index])
        var view = extra.int_value(extra.item(items[index], "bufferView"))
        base.set(copy, "bufferView", base.integer(view + view0))
        base.append(into, copy)


def _append_materials(
    mut base: JsonTree, base_root: Int, extra: JsonTree, extra_root: Int
) raises:
    """Append materials, adding an empty list when the body has none."""
    var into = base.get(base_root, "materials")
    if into == NOTHING:
        into = base.array()
        base.set(base_root, "materials", into)
    var source = extra.get(extra_root, "materials")
    if source == NOTHING:
        return
    _append_copied(base, into, extra, source)


def _append_meshes(
    mut base: JsonTree,
    base_root: Int,
    extra: JsonTree,
    extra_root: Int,
    acc0: Int,
    mat0: Int,
) raises:
    """Append meshes and renumber primitive accessors and materials."""
    var into = base.item(base_root, "meshes")
    var source = extra.item(extra_root, "meshes")
    var meshes = extra.items(source)
    for index in range(len(meshes)):
        var mesh = base.adopt(extra, meshes[index])
        var primitives = base.item(mesh, "primitives")
        var parts = base.items(primitives)
        for part in range(len(parts)):
            _renumber_primitive(base, parts[part], acc0, mat0)
        base.append(into, mesh)


def _renumber_primitive(
    mut base: JsonTree, primitive: Int, acc0: Int, mat0: Int
) raises:
    """Renumber one primitive's attributes, indices and material."""
    var attributes = base.item(primitive, "attributes")
    var names = base.names(attributes)
    var fresh = base.object()
    for index in range(len(names)):
        var name = names[index]
        var value = base.int_value(base.item(attributes, name))
        base.set(fresh, name, base.integer(value + acc0))
    base.set(primitive, "attributes", fresh)
    if base.has(primitive, "indices"):
        var value = base.int_value(base.item(primitive, "indices"))
        base.set(primitive, "indices", base.integer(value + acc0))
    if base.has(primitive, "material"):
        var value = base.int_value(base.item(primitive, "material"))
        base.set(primitive, "material", base.integer(value + mat0))


def _append_nodes(
    mut base: JsonTree,
    base_root: Int,
    extra: JsonTree,
    extra_root: Int,
    mesh0: Int,
    node0: Int,
) raises:
    """Append nodes and renumber each mesh and child list."""
    var into = base.item(base_root, "nodes")
    var source = extra.item(extra_root, "nodes")
    var nodes = extra.items(source)
    for index in range(len(nodes)):
        var node = base.adopt(extra, nodes[index])
        if base.has(node, "mesh"):
            var value = base.int_value(base.item(node, "mesh"))
            base.set(node, "mesh", base.integer(value + mesh0))
        if base.has(node, "children"):
            var children = base.item(node, "children")
            var fresh = base.array()
            var items = base.items(children)
            for child in range(len(items)):
                var value = base.int_value(items[child])
                base.append(fresh, base.integer(value + node0))
            base.set(node, "children", fresh)
        base.append(into, node)


def _append_roots(
    mut base: JsonTree,
    base_root: Int,
    extra: JsonTree,
    extra_root: Int,
    node0: Int,
) raises:
    """Append the extra scene's root nodes to the body scene."""
    var extra_scene = _scene(extra, extra_root)
    var roots = extra.items(extra.item(extra_scene, "nodes"))
    var into = base.item(_scene(base, base_root), "nodes")
    for index in range(len(roots)):
        var value = extra.int_value(roots[index])
        base.append(into, base.integer(value + node0))


def _scene(tree: JsonTree, root: Int) raises -> Int:
    """Return the default scene object."""
    var index = 0
    var scene = tree.get(root, "scene")
    if scene != NOTHING:
        index = tree.int_value(scene)
    return _at(tree, tree.item(root, "scenes"), index)


def _read_bytes(path: String) raises -> List[UInt8]:
    """Read one file."""
    return Path(path).read_bytes()


def main() raises:
    """Merge the two glTF files named on the command line."""
    var arguments = argv()
    if len(arguments) != 7:
        print(
            (
                "usage: carla_vehicle_merge BASE.gltf BASE.bin EXTRA.gltf"
                " EXTRA.bin OUT.gltf OUT.bin"
            ),
            file=stderr,
        )
        exit(2)
    try:
        var base_text = Path(arguments[1]).read_text()
        var base_bin = _read_bytes(arguments[2])
        var extra_text = Path(arguments[3]).read_text()
        var extra_bin = _read_bytes(arguments[4])
        var merged = merge_gltf(base_text, base_bin^, extra_text, extra_bin^)
        Path(arguments[5]).write_text(merged[0])
        Path(arguments[6]).write_bytes(Span(merged[1]))
    except error:
        print("carla_vehicle_merge:", error, file=stderr)
        exit(1)
