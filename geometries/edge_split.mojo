# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Split the vertices of a surface where it creases, from three.js
`examples/jsm/modifiers/EdgeSplitModifier.js`.

A vertex that several triangles share gets one normal, so the surface
shades smooth across it. At a sharp edge that is wrong. This gives each
triangle a flat normal, and at each vertex puts the triangles in groups
whose normals turn from each other by less than the cut-off angle. Every
group after the largest gets a copy of the vertex of its own. If the
surface had normals, they are then worked out again from the triangles,
and each vertex that was not split keeps the normal it had.

## As three.js does it

A surface without an index is welded first with `merge_vertices`, with
its normals left out. Each copy of a vertex is put at the end, after a
run as long as the index, and not after the last vertex. So the result
has vertices between that no triangle uses: they hold zeros, and their
normals are zero, as in three.js.

The vertices that keep their normals are found by three.js's rule, which
marks the corner of a triangle and not the vertex: a vertex keeps its
normal unless its number is the number of the first corner of a group
that split. This port keeps that rule, because it is what three.js gives.

Only the index and the attributes are kept. The groups and the morph
targets are dropped, as in three.js.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from geometries.utils import merge_vertices
from std.math import cos, isfinite, sqrt
from units.si import Angle


@fieldwise_init
struct _Split(Copyable, Movable):
    """One group of corners that get a vertex of their own: three.js's
    `{ original, indexes }`."""

    # The corner whose vertex is copied.
    var original: Int
    # The corners that take the copy.
    var indexes: List[Int]


@fieldwise_init
struct _Groups(Copyable, Movable):
    """The corners that stay with one corner, and those that split off:
    three.js's `edgeSplitToGroups` result."""

    var split_group: List[Int]
    var current_group: List[Int]


def _unit(normals: List[Float32], corner: Int) -> SIMD[DType.float64, 4]:
    """Return one corner's normal in doubles, made unit length as
    three.js's `normalize` does."""
    var v = SIMD[DType.float64, 4](
        Float64(normals[corner * 3]),
        Float64(normals[corner * 3 + 1]),
        Float64(normals[corner * 3 + 2]),
        0,
    )
    var length = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    return v * (1.0 / (length if length != 0 else 1.0))


def _to_groups(
    normals: List[Float32], indexes: List[Int], cut_off: Float64, first: Int
) -> _Groups:
    """Return the corners that face within the cut-off of `first` and
    those that do not, three.js's `edgeSplitToGroups`."""
    var a = _unit(normals, first)
    var result = _Groups(List[Int](), [first])
    for index in range(len(indexes)):  # pragma: no branch
        # `first` is one of `indexes`, so this runs.
        var j = indexes[index]
        if j == first:
            continue
        var b = _unit(normals, j)
        if b[0] * a[0] + b[1] * a[1] + b[2] * a[2] < cut_off:
            result.split_group.append(j)
        else:
            result.current_group.append(j)
    return result^


def _edge_split(
    normals: List[Float32],
    indexes: List[Int],
    cut_off: Float64,
    original: Optional[Int],
    mut splits: List[_Split],
):
    """Split one vertex's corners into groups, three.js's `edgeSplit`.

    Args:
        normals: Each corner's flat normal.
        indexes: The corners to split, one or more.
        cut_off: The dot product below which two corners part.
        original: The corner whose vertex the groups copy, or none for
            the first call on a vertex.
        splits: The groups that take a copy, appended to.
    """
    var best = _to_groups(normals, indexes, cut_off, indexes[0])
    for index in range(1, len(indexes)):
        var groups = _to_groups(normals, indexes, cut_off, indexes[index])
        if len(groups.current_group) > len(best.current_group):
            best = groups^
    if Bool(original):
        splits.append(_Split(original.value(), best.current_group.copy()))
    if len(best.split_group) > 0:
        # three.js passes `original || currentGroup[0]`, so a first
        # corner of zero counts as none.
        var next = best.current_group[0]
        if Bool(original) and original.value() != 0:
            next = original.value()
        _edge_split(normals, best.split_group, cut_off, next, splits)


def edge_split(
    geometry: BufferGeometry,
    cut_off_angle: Angle,
    try_keep_normals: Bool = True,
) raises -> BufferGeometry:
    """Return a surface with its vertices split where it creases,
    three.js's `EdgeSplitModifier.modify`.

    Args:
        geometry: The surface. It must carry positions of three numbers a
            vertex, every vertex must be used by a triangle, and it
            cannot be instanced.
        cut_off_angle: The turn between two triangles at and past which
            they part.
        try_keep_normals: Whether the vertices that were not split keep
            the normals they had. Only a surface with an index and normals
            keeps them, as in three.js.

    Returns:
        An indexed geometry. It has normals if the surface had them.

    Raises:
        Error: If the angle is not finite, the surface is instanced or has
            no positions of three numbers, a vertex is used by no
            triangle, or an index entry points past the last vertex.
    """
    if not isfinite(cut_off_angle.value):
        raise Error("An edge split needs a finite cut-off angle")
    if geometry.instanced:
        raise Error("An instanced geometry is not split")
    var had_normals = geometry.has_attribute(String(NORMAL))
    var old_normals = List[Float32]()
    var keep = had_normals and try_keep_normals and geometry.is_indexed()
    if keep:
        old_normals = geometry.attribute_view(String(NORMAL)).packed()
    var source = BufferGeometry()
    for slot in range(len(geometry.names)):
        if geometry.names[slot] != String(NORMAL):
            source.set_attribute(
                geometry.names[slot], geometry.values[slot].copy()
            )
    source.index = geometry.index.copy()
    if not source.is_indexed():
        source = merge_vertices(source)
    ref position = source.attribute_view(String(POSITION))
    if position.item_size != 3:
        raise Error("An edge split needs positions of three numbers")
    var count = position.count()
    ref indexes = source.index
    var corners = len(indexes)

    # Each corner's flat normal, three.js's `computeNormals`.
    var normals = List[Float32](length=corners * 3, fill=0)
    for first in range(0, corners - 2, 3):
        var p = List[SIMD[DType.float64, 4]]()
        for corner in range(3):  # pragma: no branch
            var vertex = indexes[first + corner]
            if vertex >= count:
                raise Error("An index entry points past the last vertex")
            p.append(
                SIMD[DType.float64, 4](
                    Float64(position.component(vertex, 0)),
                    Float64(position.component(vertex, 1)),
                    Float64(position.component(vertex, 2)),
                    0,
                )
            )
        var c = p[2] - p[1]
        var a = p[0] - p[1]
        var n = SIMD[DType.float64, 4](
            c[1] * a[2] - c[2] * a[1],
            c[2] * a[0] - c[0] * a[2],
            c[0] * a[1] - c[1] * a[0],
            0,
        )
        var length = sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
        n = n * (1.0 / (length if length != 0 else 1.0))
        for corner in range(3):  # pragma: no branch
            for axis in range(3):  # pragma: no branch
                normals[(first + corner) * 3 + axis] = Float32(n[axis])

    # Which corners each vertex has, three.js's `mapPositionsToIndexes`.
    var point_to_index = List[List[Int]](length=count, fill=List[Int]())
    for corner in range(corners):
        point_to_index[indexes[corner]].append(corner)

    var splits = List[_Split]()
    var cut_off = cos(Float64(cut_off_angle.value)) - 0.001
    for vertex in range(count):
        if len(point_to_index[vertex]) == 0:
            raise Error("An edge split needs every vertex in a triangle")
        _edge_split(normals, point_to_index[vertex], cut_off, None, splits)

    var result = BufferGeometry()
    var new_indexes = indexes.copy()
    for slot in range(len(source.names)):  # pragma: no branch
        # Positions are there, so this runs.
        ref old = source.values[slot]
        var size = old.item_size
        var data = old.packed()
        data.resize((corners + len(splits)) * size, 0)
        for split in range(len(splits)):
            var vertex = indexes[splits[split].original]
            for axis in range(size):  # pragma: no branch
                data[(corners + split) * size + axis] = data[
                    vertex * size + axis
                ]
        result.set_attribute(source.names[slot], BufferAttribute(data^, size))
    for split in range(len(splits)):
        # A group holds the corner it was grown from, so this runs.
        for corner in splits[split].indexes:  # pragma: no branch
            new_indexes[corner] = corners + split
    result.set_index(new_indexes^)

    if had_normals:
        result.compute_vertex_normals()
        if keep:
            var changed = List[Bool](length=len(old_normals) // 3, fill=False)
            for split in range(len(splits)):
                var original = splits[split].original
                if original < len(changed):
                    changed[original] = True
            # `compute_vertex_normals` put the normals last.
            ref normal = result.values[len(result.values) - 1]
            # A surface that keeps its normals has an index, and so
            # vertices: this runs.
            for vertex in range(len(changed)):  # pragma: no branch
                if not changed[vertex]:
                    for axis in range(3):  # pragma: no branch
                        normal.set_component(
                            vertex, axis, old_normals[vertex * 3 + axis]
                        )
    return result^
