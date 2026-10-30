# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cut a mesh level, along one height, with a clean edge.

A mesh that stops where its box stops, or where whole triangles stop,
ends in a ragged edge. `clip_level` keeps the part of a mesh on one side
of a height and clips each triangle that crosses it, so the edge runs
straight round the mesh. Every attribute is carried to the new vertices
by linear interpolation, and a `normal` is scaled back to unit length.
Clip a mesh before it is skinned: bone indices cannot be mixed.

    var body = clip_level(mesh, neck_top, keep_above=False)
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from objects.skinned_mesh import SKIN_INDEX
from std.math import sqrt


def _edge_key(a: Int, b: Int, count: Int) -> Int:
    """Return one key for the edge between two vertices, either way."""
    if a < b:
        return a * count + b
    return b * count + a


def _rescale(mut values: List[Float32], at: Int, size: Int):
    """Scale `size` values from `at` to unit length, unless all are zero."""
    var total = Float32(0)
    for i in range(size):  # pragma: no branch
        total += values[at + i] * values[at + i]
    if total > 0:
        var scale = 1 / sqrt(total)
        for i in range(size):  # pragma: no branch
            values[at + i] *= scale


def clip_level(
    geometry: BufferGeometry, level: Float32, keep_above: Bool
) raises -> BufferGeometry:
    """Return the part of a mesh on one side of a height.

    A triangle wholly on the kept side is kept, and one wholly on the
    other side is dropped. A triangle that crosses the height is clipped
    along it. Two triangles that share an edge share the new vertex on it.

    Args:
        geometry: A mesh with positions, indexed or not, with no morph
            targets and no bone indices.
        level: The height, in meters.
        keep_above: Keep what lies at or above the height; False keeps
            what lies at or below it.

    Returns:
        An indexed mesh with every attribute of `geometry`.

    Raises:
        Error: If the mesh has no positions, or carries morph targets or
            bone indices, which cannot be mixed.
    """
    if len(geometry.morph_positions) > 0:
        raise Error("A mesh with morph targets cannot be clipped")
    if geometry.has_attribute(String(SKIN_INDEX)):
        raise Error("A skinned mesh cannot be clipped: bone indices do not mix")
    ref placed = geometry.attribute_view(String(POSITION))
    var count = placed.count()
    var side = List[Float32](capacity=count)
    for v in range(count):
        var y = placed.vector3(v).y
        if keep_above:
            side.append(y - level)
        else:
            side.append(level - y)
    var names = geometry.names.copy()
    var sizes = List[Int]()
    var source = List[List[Float32]]()
    var out = List[List[Float32]]()
    var normal_at = -1
    for k in range(len(names)):  # pragma: no branch
        ref attribute = geometry.attribute_view(names[k])
        sizes.append(attribute.item_size)
        source.append(attribute.packed())
        out.append(List[Float32]())
        if names[k] == String(NORMAL):
            normal_at = k
    var kept = List[Int](length=count, fill=-1)
    var edges = Dict[Int, Int]()
    var written = 0
    var index = List[Int]()
    for t in range(geometry.triangle_count()):
        var polygon = List[Int]()
        for c in range(3):  # pragma: no branch
            var a = geometry.corner_index(t, c)
            var b = geometry.corner_index(t, (c + 1) % 3)
            var inside_a = side[a] >= 0
            if inside_a:
                if kept[a] < 0:
                    for k in range(len(names)):  # pragma: no branch
                        for i in range(sizes[k]):  # pragma: no branch
                            out[k].append(source[k][a * sizes[k] + i])
                    kept[a] = written
                    written += 1
                polygon.append(kept[a])
            if inside_a != (side[b] >= 0):
                var key = _edge_key(a, b, count)
                if key not in edges:
                    # Mix from the lower index, so both triangles that share
                    # the edge make the same vertex.
                    var low = min(a, b)
                    var high = max(a, b)
                    var share = side[low] / (side[low] - side[high])
                    for k in range(len(names)):  # pragma: no branch
                        var size = sizes[k]
                        for i in range(size):  # pragma: no branch
                            var x = source[k][low * size + i]
                            var y = source[k][high * size + i]
                            out[k].append(x + (y - x) * share)
                        if k == normal_at:
                            _rescale(out[k], written * size, size)
                    edges[key] = written
                    written += 1
                polygon.append(edges[key])
        for k in range(1, len(polygon) - 1):
            index.append(polygon[0])
            index.append(polygon[k])
            index.append(polygon[k + 1])
    var mesh = BufferGeometry()
    for k in range(len(names)):  # pragma: no branch
        mesh.set_attribute(names[k], BufferAttribute(out[k].copy(), sizes[k]))
    mesh.set_index(index^)
    return mesh^
