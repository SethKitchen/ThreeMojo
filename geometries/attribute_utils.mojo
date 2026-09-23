# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""More of three.js's `examples/jsm/utils/BufferGeometryUtils.js`: the
functions that work on attributes, on draw modes, on groups and on morph
targets. `geometries.utils` holds the merge, the weld and the creased
normals, and `geometries.mikktspace` holds the MikkTSpace tangents.

## Attributes

`merge_attributes` joins attributes end to end. `interleave_attributes`
puts attributes side by side in one shared buffer, and
`deinterleave_attribute` and `deinterleave_geometry` take them out again.
`estimate_bytes_used` says how much memory a geometry's arrays take.

Every attribute in this port holds floats, and none is normalized, so
three.js's checks that the array types and the `normalized` flags agree
have nothing to check.

## Draw modes

three.js can draw a run of vertices as a strip or a fan of triangles, and
`to_triangles_draw_mode` turns either into a list of triangles. This
port draws lists of triangles only, and a `BufferGeometry` index holds
whole triangles, so the strip or fan comes as the vertices in order or as
an index given beside the geometry.

## Groups

`merge_groups` sorts a geometry's groups by material and joins the groups
of one material into one, reordering the index to match.

## Morphed attributes

`compute_morphed_attributes` works out where every vertex is, and which
way it faces, once the morph targets are worn and the bones have carried
it. three.js does this for a `Mesh`; here it takes the geometry, the
weights and, for a skinned mesh, one matrix per vertex. `core.scene_utils`
has the forms that take a mesh.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    GeometryGroup,
    MAX_MORPH_TARGETS,
    NORMAL,
    POSITION,
)
from core.interleaved_buffer import InterleavedBuffer
from math.matrix4 import Matrix4

# three.js's index needs four bytes an entry, not two, from this value up:
# `arrayNeedsUint32`.
comptime UINT16_LIMIT = 65535
# The bytes one float takes.
comptime FLOAT_BYTES = 4


@fieldwise_init
struct DrawMode(Equatable, ImplicitlyCopyable, Writable):
    """How a run of vertices makes triangles, three.js's draw mode
    constants, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three draw modes there are.

        Returns:
            True for `TRIANGLES_DRAW_MODE`, `TRIANGLE_STRIP_DRAW_MODE` and
            `TRIANGLE_FAN_DRAW_MODE`.
        """
        return self.value >= 0 and self.value <= 2


# Every three vertices are one triangle: three.js's `TrianglesDrawMode`.
comptime TRIANGLES_DRAW_MODE = DrawMode(0)
# Every vertex after the second makes a triangle with the two before it:
# three.js's `TriangleStripDrawMode`.
comptime TRIANGLE_STRIP_DRAW_MODE = DrawMode(1)
# Every vertex after the second makes a triangle with the one before it
# and the first: three.js's `TriangleFanDrawMode`.
comptime TRIANGLE_FAN_DRAW_MODE = DrawMode(2)


def merge_attributes(
    attributes: List[BufferAttribute],
) raises -> BufferAttribute:
    """Return attributes joined end to end, three.js's `mergeAttributes`.

    An interleaved attribute gives its own numbers, not the whole shared
    array. The result is a plain attribute that advances per vertex, as in
    three.js.

    Args:
        attributes: The attributes, one or more, all with one item size.

    Returns:
        One attribute holding every item, in order.

    Raises:
        Error: If no attribute is given, or the item sizes differ.
    """
    if len(attributes) == 0:
        raise Error("Merging needs at least one attribute")
    var size = attributes[0].item_size
    var data = List[Float32]()
    for index in range(len(attributes)):  # pragma: no branch
        # One attribute at least, so this runs.
        if attributes[index].item_size != size:
            raise Error("Merged attributes must share an item size")
        data.extend(attributes[index].packed())
    return BufferAttribute(data^, size)


def interleave_attributes(
    attributes: List[BufferAttribute],
) raises -> List[BufferAttribute]:
    """Return attributes laid side by side in one shared buffer, three.js's
    `interleaveAttributes`.

    The stride is the sum of the item sizes, and each attribute's items
    start where the item sizes before it end. The attributes that come
    back advance per vertex, as in three.js.

    three.js sizes the buffer by the length of each attribute's array, which
    is the whole shared array for one that is interleaved already. This
    sizes it by the items, which is the same for a plain attribute.

    Args:
        attributes: The attributes, one or more, each with one to four
            numbers an item, all with the same number of items.

    Returns:
        One interleaved attribute for each attribute given, on one buffer.

    Raises:
        Error: If no attribute is given, the counts differ, or an item size
            is more than four. three.js writes only the first four numbers
            with `setX` through `setW`, and stops at a fifth.
    """
    if len(attributes) == 0:
        raise Error("Interleaving needs at least one attribute")
    var count = attributes[0].count()
    var stride = 0
    for index in range(len(attributes)):  # pragma: no branch
        # One attribute at least, so this runs.
        if attributes[index].count() != count:
            raise Error("Interleaved attributes must have the same count")
        if attributes[index].item_size > 4:
            raise Error("An interleaved attribute holds at most four numbers")
        stride += attributes[index].item_size
    var array = List[Float32](length=count * stride, fill=0)
    var offset = 0
    for index in range(len(attributes)):  # pragma: no branch
        # One attribute at least, so this runs.
        ref attribute = attributes[index]
        for item in range(count):
            for axis in range(attribute.item_size):  # pragma: no branch
                # An item size is positive.
                array[item * stride + offset + axis] = attribute.component(
                    item, axis
                )
        offset += attribute.item_size
    var buffer = InterleavedBuffer(array^, stride)
    var out = List[BufferAttribute]()
    offset = 0
    for index in range(len(attributes)):  # pragma: no branch
        # One attribute at least, so this runs.
        var size = attributes[index].item_size
        out.append(BufferAttribute(buffer, size, offset))
        offset += size
    return out^


def deinterleave_attribute(
    attribute: BufferAttribute,
) raises -> BufferAttribute:
    """Return an interleaved attribute with an array of its own, three.js's
    `deinterleaveAttribute`.

    One that advances per instance still does. three.js copies only the
    first four numbers of an item, with `setX` through `setW`, and leaves
    any more at zero; so does this.

    Args:
        attribute: The interleaved attribute.

    Returns:
        A plain attribute with the same items.

    Raises:
        Error: If the attribute is not interleaved. three.js fails on one
            that is not.
    """
    if not attribute.is_interleaved():
        raise Error("Only an interleaved attribute is deinterleaved")
    var size = attribute.item_size
    var data = List[Float32](length=attribute.count() * size, fill=0)
    for item in range(attribute.count()):
        for axis in range(min(size, 4)):  # pragma: no branch
            # An item size is positive.
            data[item * size + axis] = attribute.component(item, axis)
    if attribute.is_instanced():
        return BufferAttribute(
            data^, size, mesh_per_attribute=attribute.mesh_per_attribute()
        )
    return BufferAttribute(data^, size)


def deinterleave_geometry(mut geometry: BufferGeometry) raises:
    """Give every interleaved attribute of a geometry an array of its own,
    three.js's `deinterleaveGeometry`.

    The morph targets are deinterleaved too. three.js means to, but reads
    `geometry.morphTargets`, which a geometry does not have, and so leaves
    them.

    Args:
        geometry: The geometry, changed in place.

    Raises:
        Error: Never for an attribute that was constructed.
    """
    for slot in range(len(geometry.values)):
        if geometry.values[slot].is_interleaved():
            geometry.values[slot] = deinterleave_attribute(
                geometry.values[slot]
            )
    for target in range(len(geometry.morph_positions)):
        if geometry.morph_positions[target].is_interleaved():
            geometry.morph_positions[target] = deinterleave_attribute(
                geometry.morph_positions[target]
            )
    for target in range(len(geometry.morph_normals)):
        if geometry.morph_normals[target].is_interleaved():
            geometry.morph_normals[target] = deinterleave_attribute(
                geometry.morph_normals[target]
            )


def estimate_bytes_used(geometry: BufferGeometry) -> Int:
    """Return how many bytes a geometry's attributes and index take,
    three.js's `estimateBytesUsed`.

    Each attribute takes four bytes a number, for its own items only. The
    index takes two bytes an entry, or four if an entry is 65535 or more,
    as three.js's `setIndex` of a plain array chooses.

    Args:
        geometry: The geometry.

    Returns:
        The number of bytes.
    """
    var total = 0
    for slot in range(len(geometry.values)):
        ref attribute = geometry.values[slot]
        total += attribute.count() * attribute.item_size * FLOAT_BYTES
    var entry = 2
    for index in range(len(geometry.index)):
        if geometry.index[index] >= UINT16_LIMIT:
            entry = 4
    return total + len(geometry.index) * entry


def to_triangles_draw_mode(
    geometry: BufferGeometry, draw_mode: DrawMode, strip: List[Int]
) raises -> BufferGeometry:
    """Return a geometry whose index lists the triangles a strip or a fan
    makes, three.js's `toTrianglesDrawMode`.

    A strip's odd triangles are turned round, so that every triangle faces
    the way the first does. The groups are cleared, as in three.js.

    Args:
        geometry: The geometry whose vertices the strip or fan reads.
        draw_mode: `TRIANGLE_STRIP_DRAW_MODE` or `TRIANGLE_FAN_DRAW_MODE`.
            `TRIANGLES_DRAW_MODE` gives back a copy, as three.js gives back
            the geometry.
        strip: The vertices of the strip or the fan, in order, three or
            more. Read only for a strip or a fan.

    Returns:
        The geometry with a list of triangles for its index.

    Raises:
        Error: If the draw mode is not valid, the strip has fewer than
            three entries, or an entry is not a vertex of the geometry.
    """
    if not draw_mode.is_valid():
        raise Error("A draw mode must be one of the three there are")
    if draw_mode == TRIANGLES_DRAW_MODE:
        return geometry.clone()
    if len(strip) < 3:
        raise Error("A strip or a fan needs three vertices at least")
    var count = geometry.vertex_count()
    for entry in range(len(strip)):  # pragma: no branch
        # Three entries at least, so this runs.
        if strip[entry] < 0 or strip[entry] >= count:
            raise Error("A strip names a vertex the geometry does not have")
    var triangles = len(strip) - 2
    var index = List[Int](capacity=triangles * 3)
    if draw_mode == TRIANGLE_FAN_DRAW_MODE:
        for i in range(1, triangles + 1):  # pragma: no branch
            # One triangle at least, so this runs.
            index.extend([strip[0], strip[i], strip[i + 1]])
    else:
        for i in range(triangles):  # pragma: no branch
            # One triangle at least, so this runs.
            if i % 2 == 0:
                index.extend([strip[i], strip[i + 1], strip[i + 2]])
            else:
                index.extend([strip[i + 2], strip[i + 1], strip[i]])
    var result = geometry.clone()
    result.set_index(index^)
    result.clear_groups()
    return result^


def to_triangles_draw_mode(
    geometry: BufferGeometry, draw_mode: DrawMode
) raises -> BufferGeometry:
    """Return a geometry whose index lists the triangles its strip or fan
    makes, three.js's `toTrianglesDrawMode`.

    The strip or fan is the geometry's own index if it has one, or its
    vertices in order, as three.js makes one when there is no index.

    Args:
        geometry: The geometry.
        draw_mode: How its vertices make triangles.

    Returns:
        The geometry with a list of triangles for its index.

    Raises:
        Error: If the draw mode is not valid, or the strip has fewer than
            three entries or names a vertex the geometry does not have.
    """
    if geometry.is_indexed():
        return to_triangles_draw_mode(geometry, draw_mode, geometry.index)
    var strip = List[Int]()
    for vertex in range(geometry.vertex_count()):
        strip.append(vertex)
    return to_triangles_draw_mode(geometry, draw_mode, strip)


def _after(a: GeometryGroup, b: GeometryGroup) -> Bool:
    """Return True if three.js's comparison puts `a` after `b`: a later
    material, or the same material and a later start."""
    return a.material_index.value > b.material_index.value or (
        a.material_index == b.material_index and a.start > b.start
    )


def _sorted_groups(groups: List[GeometryGroup]) -> List[GeometryGroup]:
    """Return groups sorted by material, then by start, keeping the order
    of equals: JavaScript's stable `sort` with three.js's comparison."""
    var out = List[GeometryGroup]()
    for index in range(len(groups)):  # pragma: no branch
        # The caller has refused no groups, so this runs.
        var group = groups[index]
        var at = len(out)
        while at > 0 and _after(out[at - 1], group):
            at -= 1
        out.insert(at, group)
    return out^


def merge_groups(mut geometry: BufferGeometry) raises:
    """Sort a geometry's groups by material and join the groups of one
    material, three.js's `mergeGroups`.

    A geometry without an index is given one that reads its vertices in
    order. The index is then rewritten to hold each group's entries in the
    sorted order, and the groups are moved to match. A geometry without
    groups is left alone, as in three.js.

    Args:
        geometry: The geometry, changed in place.

    Raises:
        Error: If a group reaches past the end of the index, or the groups
            together do not hold whole triangles. three.js reads nothing
            past the end, and keeps an index of any length.
    """
    if len(geometry.groups) == 0:
        return
    var groups = _sorted_groups(geometry.groups)
    var index = geometry.index.copy()
    if len(index) == 0:
        for vertex in range(0, geometry.vertex_count(), 3):
            index.extend([vertex, vertex + 1, vertex + 2])
    var new_index = List[Int]()
    for group in range(len(groups)):  # pragma: no branch
        # There are groups, so this runs.
        var start = groups[group].start
        var end = start + groups[group].count
        if end > len(index):
            raise Error("A group reaches past the end of the index")
        for entry in range(start, end):
            new_index.append(index[entry])
    geometry.set_index(new_index^)
    var start = 0
    for group in range(len(groups)):  # pragma: no branch
        # There are groups, so this runs.
        groups[group].start = start
        start += groups[group].count
    geometry.groups.clear()
    geometry.groups.append(groups[0])
    for group in range(1, len(groups)):
        ref current = geometry.groups[len(geometry.groups) - 1]
        if current.material_index == groups[group].material_index:
            current.count += groups[group].count
        else:
            geometry.groups.append(groups[group])


struct MorphedAttributes(Movable):
    """A geometry's positions and normals, as modeled and as worn: the
    object three.js's `computeMorphedAttributes` returns."""

    var position: BufferAttribute
    var normal: BufferAttribute
    var morphed_position: BufferAttribute
    var morphed_normal: BufferAttribute

    def __init__(
        out self,
        var position: BufferAttribute,
        var normal: BufferAttribute,
        var morphed_position: BufferAttribute,
        var morphed_normal: BufferAttribute,
    ):
        """Hold the four attributes.

        Args:
            position: The positions as modeled.
            normal: The normals as modeled.
            morphed_position: The positions as worn.
            morphed_normal: The normals as worn.
        """
        self.position = position^
        self.normal = normal^
        self.morphed_position = morphed_position^
        self.morphed_normal = morphed_normal^


def _morphed(
    base: BufferAttribute,
    targets: List[BufferAttribute],
    relative: Bool,
    influences: SIMD[DType.float32, MAX_MORPH_TARGETS],
    vertex: Int,
) raises -> SIMD[DType.float64, 4]:
    """Return one vertex of an attribute with the morph targets worn, in
    doubles, as three.js's `_calculateMorphedAttributeData` adds them."""
    var v = SIMD[DType.float64, 4](
        Float64(base.component(vertex, 0)),
        Float64(base.component(vertex, 1)),
        Float64(base.component(vertex, 2)),
        0,
    )
    var morph = SIMD[DType.float64, 4](0)
    for target in range(len(targets)):
        var influence = Float64(influences[target])
        if influence == 0:
            continue
        var t = SIMD[DType.float64, 4](
            Float64(targets[target].component(vertex, 0)),
            Float64(targets[target].component(vertex, 1)),
            Float64(targets[target].component(vertex, 2)),
            0,
        )
        if not relative:
            t = t - v
        morph = morph + t * influence
    return v + morph


def _carried(
    carrier: Matrix4, v: SIMD[DType.float64, 4], w: Float64
) -> SIMD[DType.float64, 4]:
    """Return `v` carried by a matrix, as a point for `w` of one and as a
    direction for `w` of zero."""
    ref e = carrier.elements
    var out = SIMD[DType.float64, 4](0)
    for row in range(3):  # pragma: no branch
        out[row] = (
            Float64(e[row]) * v[0]
            + Float64(e[4 + row]) * v[1]
            + Float64(e[8 + row]) * v[2]
            + Float64(e[12 + row]) * w
        )
    return out


def _worn(
    geometry: BufferGeometry,
    influences: SIMD[DType.float32, MAX_MORPH_TARGETS],
    carriers: List[Matrix4],
    skinned: Bool,
) raises -> MorphedAttributes:
    """Return a geometry's positions and normals as worn, with or without
    one carrying matrix per vertex."""
    ref positions = geometry.attribute_view(String(POSITION))
    if not geometry.has_attribute(String(NORMAL)):
        raise Error("Morphed attributes need normals")
    ref normals = geometry.attribute_view(String(NORMAL))
    if positions.item_size != 3 or normals.item_size != 3:
        raise Error("Morphed attributes need three numbers a vertex")
    var count = positions.count()
    if normals.count() != count:
        raise Error("Morphed normals must cover every vertex")
    if skinned and len(carriers) != count:
        raise Error("A skinned mesh needs one carrying matrix a vertex")
    var moved = List[Float32](length=count * 3, fill=0)
    var turned = List[Float32](length=count * 3, fill=0)
    for triangle in range(geometry.triangle_count()):
        for corner in range(3):  # pragma: no branch
            var vertex = geometry.corner_index(triangle, corner)
            var p = _morphed(
                positions,
                geometry.morph_positions,
                geometry.morph_relative,
                influences,
                vertex,
            )
            var n = _morphed(
                normals,
                geometry.morph_normals,
                geometry.morph_relative,
                influences,
                vertex,
            )
            if skinned:
                p = _carried(carriers[vertex], p, 1)
                n = _carried(carriers[vertex], n, 0)
            for axis in range(3):  # pragma: no branch
                moved[vertex * 3 + axis] = Float32(p[axis])
                turned[vertex * 3 + axis] = Float32(n[axis])
    return MorphedAttributes(
        positions.clone(),
        normals.clone(),
        BufferAttribute(moved^, 3),
        BufferAttribute(turned^, 3),
    )


def compute_morphed_attributes(
    geometry: BufferGeometry,
    influences: SIMD[DType.float32, MAX_MORPH_TARGETS],
) raises -> MorphedAttributes:
    """Return a geometry's positions and normals with its morph targets
    worn, three.js's `computeMorphedAttributes` for a `Mesh`.

    Each target adds its weight times its run from the base, or times
    itself for targets that hold offsets. A target of no weight is skipped.
    A vertex that no triangle uses stays at zero, as in three.js.

    The normals wear the normal targets. three.js wears the position
    targets on the normals as well, which moves each normal by how far its
    vertex moved; this port does not. A geometry whose targets carry no
    normals keeps its base normals.

    Args:
        geometry: The geometry, with `position` and `normal`.
        influences: How much of each target the mesh wears.

    Returns:
        The modeled attributes, copied, and the worn ones.

    Raises:
        Error: If the geometry has no positions or no normals, either
            holds other than three numbers a vertex or they differ in
            count, or an index entry points past the last vertex.
    """
    return _worn(geometry, influences, List[Matrix4](), False)


def compute_morphed_attributes(
    geometry: BufferGeometry,
    influences: SIMD[DType.float32, MAX_MORPH_TARGETS],
    carriers: List[Matrix4],
) raises -> MorphedAttributes:
    """Return a skinned geometry's positions and normals with its morph
    targets worn and its bones' carrying applied, three.js's
    `computeMorphedAttributes` for a `SkinnedMesh`.

    `carriers` holds one matrix per vertex, as `core.deform.skin_carriers`
    gives them. A position is carried as a point. A normal is carried as a
    direction and is not made unit length. three.js carries a normal as a
    point, which moves it by the bones' translation; this port does not.

    Args:
        geometry: The geometry, with `position` and `normal`.
        influences: How much of each target the mesh wears.
        carriers: One matrix per vertex.

    Returns:
        The modeled attributes, copied, and the worn ones.

    Raises:
        Error: As the form without carriers does, or if there is not one
            carrier per vertex.
    """
    return _worn(geometry, influences, carriers, True)
