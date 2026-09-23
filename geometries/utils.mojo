# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Whole-geometry operations, from three.js
`examples/jsm/utils/BufferGeometryUtils.js`.

`merge_geometries` joins several geometries into one, so that many small
parts draw as one mesh. `merge_vertices` welds the vertices that agree on
every attribute and gives the result an index. `to_creased_normals` gives
a surface smooth normals across its gentle edges and sharp ones across
its creases.

The three.js methods these sit beside -- `toNonIndexed`, `center` and
`computeTangents` -- are methods of `BufferGeometry` there and here.

## Keys, not a search

Both welding functions find a vertex's partners by a key made of its
numbers rounded to a step, as three.js does, and not by comparing every
vertex with every other. The rounding is three.js's own: a number is
scaled, and truncated toward zero, which is what JavaScript's `~~` does.
Two numbers a step apart can therefore land on either side of a rounding
boundary and stay apart, in three.js and here.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    MaterialIndex,
    NORMAL,
    POSITION,
)
from math.vector3 import Vector3
from std.collections import Dict
from std.math import cos, isfinite, isnan, log10
from units.si import Angle, DEGREE

# The tolerance three.js's `mergeVertices` defaults to. A plain number and
# not a `Length`, because it is applied to every attribute in that
# attribute's own units: meters for a position, nothing for a normal or a
# texture coordinate.
comptime DEFAULT_TOLERANCE = Float64(1e-4)
# The smallest tolerance `merge_vertices` uses: JavaScript's
# `Number.EPSILON`, which three.js raises a smaller one to.
comptime EPSILON = Float64(2.220446049250313e-16)
# The angle three.js's `toCreasedNormals` defaults `creaseAngle` to: a
# third of a half turn.
comptime DEFAULT_CREASE = Angle(60.0, DEGREE)
# What `to_creased_normals` scales a position by before it truncates it:
# three.js's `(1 + 1e-10) * 1e2`. Points closer than a centimeter or so
# share a key, whatever the scale of the geometry.
comptime CREASE_HASH = Float64((1 + 1e-10) * 1e2)
# The largest magnitude a key is clamped to, so that a scaled number
# beyond what an `Int` holds still makes a key rather than an undefined
# conversion. JavaScript's `~~` wraps at two to the thirty-first instead.
comptime KEY_LIMIT = Float64(9.0e18)


def truncated(value: Float64) -> Int:
    """Return a number truncated toward zero, as JavaScript's `~~` does.

    Args:
        value: Any number.

    Returns:
        Its whole part, zero for a NaN as `~~` gives, and at most
        `KEY_LIMIT` in magnitude.
    """
    if isnan(value):
        return 0
    return Int(max(min(value, KEY_LIMIT), -KEY_LIMIT))


def merge_geometries(
    geometries: List[BufferGeometry], use_groups: Bool = False
) raises -> BufferGeometry:
    """Return one geometry holding every geometry given, three.js's
    `mergeGeometries`.

    The attributes are joined end to end, in the first geometry's order.
    An index is joined the same way, each part's entries moved past the
    vertices of the parts before it. Morph targets are joined target by
    target.

    With `use_groups`, the result has one group per part, and part `i`
    wears material `i`. The parts' own groups are not kept, as in three.js.

    Args:
        geometries: The parts, at least one. All of them must be indexed or
            none; all must carry the same attributes with the same item
            sizes, and the same morph targets.
        use_groups: Whether to add one group per part.

    Returns:
        The merged geometry.

    Raises:
        Error: If no geometry is given, if the parts do not match as above,
            if a part has no positions, or if an index entry points past
            its part's last vertex.
    """
    if len(geometries) == 0:
        raise Error("Merging needs at least one geometry")
    ref first = geometries[0]
    for part in range(1, len(geometries)):
        ref other = geometries[part]
        if other.is_indexed() != first.is_indexed():
            raise Error("Merged geometries must all be indexed, or none")
        if other.attribute_count() != first.attribute_count():
            raise Error("Merged geometries must carry the same attributes")
        for slot in range(first.attribute_count()):
            ref name = first.names[slot]
            if not other.has_attribute(name):
                raise Error("Merged geometries must carry the same attributes")
            if (
                other.attribute_view(name).item_size
                != first.values[slot].item_size
            ):
                raise Error("A merged attribute must keep its item size")
        if other.morph_count() != first.morph_count():
            raise Error("Merged geometries must carry the same morph targets")
        if other.has_morph_normals() != first.has_morph_normals():
            raise Error("Merged morph targets must all carry normals, or none")
        if other.morph_relative != first.morph_relative:
            raise Error("Merged morph targets must all be relative, or none")

    var merged = BufferGeometry()
    var index = List[Int]()
    var vertices = 0
    var stream = 0
    # The empty list was refused above, so there is a first part.
    for part in range(len(geometries)):  # pragma: no branch
        ref geometry = geometries[part]
        var count = geometry.vertex_count()
        # Runs no times for a part without an index.
        for entry in range(len(geometry.index)):
            if geometry.index[entry] >= count:
                raise Error("An index entry points past the last vertex")
            index.append(geometry.index[entry] + vertices)
        if use_groups:
            var span = geometry.stream_length()
            merged.add_group(stream, span, MaterialIndex(part))
            stream += span
        vertices += count
    # `vertex_count` raised above for a part with no attributes, so the
    # first part carries one at least.
    for slot in range(first.attribute_count()):  # pragma: no branch
        ref name = first.names[slot]
        var data = List[Float32]()
        for part in range(len(geometries)):  # pragma: no branch
            data.extend(geometries[part].attribute_view(name).data.copy())
        merged.set_attribute(
            name, BufferAttribute(data^, first.values[slot].item_size)
        )
    for target in range(first.morph_count()):
        var data = List[Float32]()
        for part in range(len(geometries)):  # pragma: no branch
            data.extend(geometries[part].morph_positions[target].data.copy())
        merged.morph_positions.append(BufferAttribute(data^, 3))
    for target in range(len(first.morph_normals)):
        var data = List[Float32]()
        for part in range(len(geometries)):  # pragma: no branch
            data.extend(geometries[part].morph_normals[target].data.copy())
        merged.morph_normals.append(BufferAttribute(data^, 3))
    merged.morph_relative = first.morph_relative
    merged.set_index(index^)
    return merged^


def merge_vertices(
    geometry: BufferGeometry, tolerance: Float64 = DEFAULT_TOLERANCE
) raises -> BufferGeometry:
    """Return a geometry with the vertices that agree on every attribute
    welded into one, three.js's `mergeVertices`.

    Every number of every attribute is scaled by one over the tolerance,
    moved by half a step and truncated, and a vertex whose numbers all
    give the same keys as an earlier vertex's is that vertex. Positions,
    normals, texture coordinates and colors all count, so two corners of a
    cube that share a place but not a normal stay apart. The morph targets
    are carried along and do not count, as in three.js.

    The result is indexed, and holds each kept vertex once, in the order
    the vertices are first met. The groups are kept as they are.

    Args:
        geometry: The geometry to weld, which must carry positions.
        tolerance: The step each number is rounded to. The same step is
            used for every attribute, in its own units; see
            `DEFAULT_TOLERANCE`. Zero is raised to `EPSILON`, as in
            three.js.

    Returns:
        The welded geometry.

    Raises:
        Error: If the tolerance is negative or not finite, if the geometry
            has no positions, or if an index entry points past an
            attribute's last item.
    """
    if not isfinite(tolerance) or tolerance < 0:
        raise Error("A weld tolerance must be a finite number, zero or more")
    var step = max(tolerance, EPSILON)
    # three.js's arithmetic, step for step, so the keys round as its do.
    var multiplier = 10.0 ** log10(1.0 / step)
    var additive = step * 0.5 * multiplier
    var count = geometry.stream_length()
    var seen = Dict[String, Int]()
    var kept = List[Int]()
    var index = List[Int]()
    for slot in range(count):
        var vertex = geometry.vertex_at(slot)
        var key = String()
        # `vertex_at` needs positions, so there is an attribute at least.
        for name in range(geometry.attribute_count()):  # pragma: no branch
            ref attribute = geometry.values[name]
            # An item size is positive: `BufferAttribute` refuses others.
            for offset in range(attribute.item_size):  # pragma: no branch
                var number = Float64(attribute.component(vertex, offset))
                key += String(truncated(number * multiplier + additive))
                key += ","
        if key in seen:
            index.append(seen[key])
        else:
            seen[key] = len(kept)
            index.append(len(kept))
            kept.append(vertex)
    var welded = BufferGeometry()
    # `stream_length` needs positions, so there is an attribute at least.
    for name in range(geometry.attribute_count()):  # pragma: no branch
        welded.set_attribute(
            geometry.names[name], geometry.values[name].gather(kept)
        )
    for target in range(geometry.morph_count()):
        welded.morph_positions.append(
            geometry.morph_positions[target].gather(kept)
        )
    for target in range(len(geometry.morph_normals)):
        welded.morph_normals.append(geometry.morph_normals[target].gather(kept))
    welded.morph_relative = geometry.morph_relative
    welded.groups = geometry.groups.copy()
    welded.set_index(index^)
    return welded^


def _crease_key(point: Vector3) -> String:
    """Return the key a position is found by in `to_creased_normals`.

    Args:
        point: The position.

    Returns:
        Its three coordinates scaled by `CREASE_HASH` and truncated.
    """
    return (
        String(truncated(Float64(point.x) * CREASE_HASH))
        + ","
        + String(truncated(Float64(point.y) * CREASE_HASH))
        + ","
        + String(truncated(Float64(point.z) * CREASE_HASH))
    )


def to_creased_normals(
    geometry: BufferGeometry, crease_angle: Angle = DEFAULT_CREASE
) raises -> BufferGeometry:
    """Return a geometry with normals smooth across gentle edges and sharp
    across creases, three.js's `toCreasedNormals`.

    The geometry is made non-indexed first, so every triangle owns its
    three corners. Each corner's normal is then the sum of the normals of
    the triangles that meet at its position and turn from its own triangle
    by less than the crease angle, made unit length. A cube keeps its flat
    faces; a sphere shades smoothly; a cylinder does both.

    Positions are matched by key, not by distance: see `CREASE_HASH`.

    three.js changes a geometry without an index in place and returns it.
    This leaves the geometry given alone and returns a new one.

    Args:
        geometry: The surface, which must carry positions.
        crease_angle: The turn at and past which an edge is a crease. Sixty
            degrees unless said otherwise, as three.js defaults it.

    Returns:
        A geometry without an index, with a `normal` for every corner.

    Raises:
        Error: If the angle is negative or not finite, if the geometry has
            no positions or they hold fewer than three numbers a vertex, or
            if an index entry points past an attribute's last item.
    """
    if not isfinite(crease_angle.value) or crease_angle.value < 0:
        raise Error("A crease angle must be a finite angle, zero or more")
    var crease = cos(crease_angle.value)
    var result = geometry.to_non_indexed()
    var count = result.vertex_count()
    var faces = count // 3
    var normals = List[Vector3]()
    var keys = List[String]()
    var sharing = Dict[String, List[Int]]()
    ref positions = result.attribute_view(String(POSITION))
    for face in range(faces):
        var a = positions.vector3(face * 3)
        var b = positions.vector3(face * 3 + 1)
        var c = positions.vector3(face * 3 + 2)
        # three.js's order: from the second corner to the third, crossed
        # with from the second to the first.
        var normal = c - b
        normal.cross(a - b)
        normal.normalize()
        normals.append(normal)
        for corner in [a, b, c]:  # pragma: no branch
            var key = _crease_key(corner)
            if key not in sharing:
                sharing[key] = List[Int]()
            sharing[key].append(face)
            keys.append(key)
    # A vertex past the last whole triangle keeps a zero normal, as in
    # three.js.
    var data = List[Float32](length=count * 3, fill=0.0)
    for face in range(faces):
        var own = normals[face]
        for corner in range(3):  # pragma: no branch
            var vertex = face * 3 + corner
            var sum = Vector3(0, 0, 0)
            ref others = sharing[keys[vertex]]
            # The corner's own face is in the list, so it is never empty.
            for other in range(len(others)):  # pragma: no branch
                var normal = normals[others[other]]
                if own.dot(normal) > crease:
                    sum.add(normal)
            sum.normalize()
            data[vertex * 3] = sum.x
            data[vertex * 3 + 1] = sum.y
            data[vertex * 3 + 2] = sum.z
    result.set_attribute(String(NORMAL), BufferAttribute(data^, 3))
    return result^
