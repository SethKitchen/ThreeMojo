# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A disk and a washer, from three.js `src/geometries/CircleGeometry.js` and
`src/geometries/RingGeometry.js`.

Both lie in the xy plane facing +z and are centered on the origin, as the
plane is. A circle is a fan: one vertex at the center, a rim of vertices
around it, and one triangle per segment. A ring is the plane's grid bent
around the center: a row of vertices at each radius from the inner edge to
the outer, a column at each angle, and two triangles per cell.

A circle with a partial sweep is a pie slice and a ring with one is an arc.
The sweep starts at `theta_start`, measured counter-clockwise from +x, and
runs for `theta_length`. A full turn puts the first and last vertex of a rim
in the same place. three.js emits both, and so does this, so that a rim is
one run of `segments + 1` vertices and the index one plain sequence whether
the sweep closes or not. The two seam vertices carry the same texture
coordinate, because the coordinates come from the position and not from the
angle; the sphere's seam, whose u comes from the angle, is the one that
needs two vertices to hold both zero and one.

Texture coordinates map the bounding square of the outer radius onto the
image: the center is (0.5, 0.5) and the rim of a full circle touches the four
edges. A pie slice or an arc shows only its part of the image, which is what
three.js does and what keeps a texture still when the sweep animates.

A ring with an inner radius of zero is a disk, as three.js's `RingGeometry`
accepts it. Its inner row is then every vertex at the center, and the first
triangle of each inner cell has two corners there and no area. A rasterizer
draws nothing for such a triangle, so the disk looks as `circle` draws it.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from std.math import cos, sin
from units.si import Angle, Length, RADIAN, TURN

# A whole circle: the default sweep, and the most a sweep can be, because
# more than a turn lays the rim over itself.
comptime FULL_TURN = Angle(1.0, TURN)


def check_sweep(sweep: Angle) raises:
    """Refuse a sweep that is not positive or is more than a full turn.

    Shared by every builder that takes a start angle and a sweep, so they all
    draw the line in the same place.

    Args:
        sweep: How far around the shape runs.

    Raises:
        Error: If the sweep is zero or negative, or more than one turn,
            which would lay the shape over itself.
    """
    if sweep.value <= 0:
        raise Error("A sweep must be positive")
    if sweep.value > FULL_TURN.value:
        raise Error("A sweep cannot be more than a full turn")


def _append_flat_vertex(
    mut data: List[Float32],
    mut normals: List[Float32],
    mut uvs: List[Float32],
    x: Float32,
    y: Float32,
    outer: Float32,
):
    """Append a vertex at (x, y, 0) facing +z.

    Its texture coordinate is where it lies in the square of half-width
    `outer` around the origin: the center maps to (0.5, 0.5).
    """
    data.append(x)
    data.append(y)
    data.append(Float32(0))
    normals.append(Float32(0))
    normals.append(Float32(0))
    normals.append(Float32(1))
    uvs.append((x / outer + 1) / 2)
    uvs.append((y / outer + 1) / 2)


def circle(
    radius: Length,
    segments: Int = 32,
    theta_start: Angle = Angle(0.0, RADIAN),
    theta_length: Angle = FULL_TURN,
) raises -> BufferGeometry:
    """Return a disk in the xy plane, facing +z, centered on the origin.

    Args:
        radius: How far the rim lies from the center.
        segments: How many triangles the fan has; at least three.
        theta_start: Where the rim starts, counter-clockwise from +x.
        theta_length: How far the rim sweeps. A full turn, the default,
            closes the disk; less makes a pie slice.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer, wound counter-clockwise seen from +z. The center is
        vertex zero and the rim follows it, `segments + 1` vertices long.

    Raises:
        Error: If the radius is not positive, there are fewer than three
            segments, or the sweep is not positive or is more than a turn.
    """
    if radius.value <= 0:
        raise Error("A circle needs a positive radius")
    if segments < 3:
        raise Error("A circle needs at least three segments")
    check_sweep(theta_length)

    var r = radius.value
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    # The center first, then the rim: one vertex more than there are
    # segments, so a full turn has a vertex on each side of the seam. The
    # segment count was checked above, so the loop always runs.
    _append_flat_vertex(data, normals, uvs, 0, 0, r)
    for step in range(segments + 1):  # pragma: no branch
        var theta = (
            theta_start.value
            + Float32(step) / Float32(segments) * theta_length.value
        )
        _append_flat_vertex(
            data, normals, uvs, r * cos(theta), r * sin(theta), r
        )

    var index = List[Int]()
    for step in range(1, segments + 1):  # pragma: no branch
        # A rim vertex, the next one around, then the center: counter-
        # clockwise seen from +z, in the order three.js emits them.
        index.append(step)
        index.append(step + 1)
        index.append(0)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(index^)
    return geometry^


def ring(
    inner_radius: Length,
    outer_radius: Length,
    theta_segments: Int = 32,
    phi_segments: Int = 1,
    theta_start: Angle = Angle(0.0, RADIAN),
    theta_length: Angle = FULL_TURN,
) raises -> BufferGeometry:
    """Return a flat ring in the xy plane, facing +z, centered on the origin.

    Args:
        inner_radius: Where the hole ends; zero or more. Zero makes a
            disk, as in three.js.
        outer_radius: Where the ring ends; more than the inner radius.
        theta_segments: How many cells around; at least three.
        phi_segments: How many cells from the inner edge to the outer; at
            least one.
        theta_start: Where the sweep starts, counter-clockwise from +x.
        theta_length: How far it sweeps. A full turn, the default, closes
            the ring; less makes an arc.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer, wound counter-clockwise seen from +z. Vertices run in
        rows from the inner edge outwards, `theta_segments + 1` to a row.

    Raises:
        Error: If the inner radius is negative, the outer radius is not
            more than it, either segment count is too small, or the sweep
            is not positive or is more than a turn.
    """
    if inner_radius.value < 0:
        raise Error("A ring's inner radius cannot be negative")
    if outer_radius.value <= inner_radius.value:
        raise Error("A ring's outer radius must be more than its inner radius")
    if theta_segments < 3:
        raise Error("A ring needs at least three segments around")
    if phi_segments < 1:
        raise Error("A ring needs at least one segment across")
    check_sweep(theta_length)

    var outer = outer_radius.value
    var radius_step = (outer - inner_radius.value) / Float32(phi_segments)
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    # Rows from the inner edge outwards, each one vertex longer than the
    # number of cells around so the seam has a vertex on each side. The
    # segment counts were checked above, so every loop runs.
    for row in range(phi_segments + 1):  # pragma: no branch
        var radius = inner_radius.value + Float32(row) * radius_step
        for column in range(theta_segments + 1):  # pragma: no branch
            var theta = (
                theta_start.value
                + Float32(column) / Float32(theta_segments) * theta_length.value
            )
            _append_flat_vertex(
                data,
                normals,
                uvs,
                radius * cos(theta),
                radius * sin(theta),
                outer,
            )

    var stride = theta_segments + 1
    var index = List[Int]()
    for row in range(phi_segments):  # pragma: no branch
        for column in range(theta_segments):  # pragma: no branch
            var a = row * stride + column
            var b = a + stride
            var c = b + 1
            var d = a + 1
            # Two triangles per cell, each counter-clockwise from the front:
            # inner, outer, next inner, then outer, next outer, next inner.
            index.append(a)
            index.append(b)
            index.append(d)
            index.append(b)
            index.append(c)
            index.append(d)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(index^)
    return geometry^
