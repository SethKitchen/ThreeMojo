# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A box, from three.js `src/geometries/BoxGeometry.js`.

The box is six planes, each three.js's `buildPlane`: a grid of
`segments + 1` by `segments + 1` vertices, the planes in three.js's order
+x, -x, +y, -y, +z, -z. So a face's vertices, its triangles and its
texture coordinates are three.js's, in three.js's order, and an export or
a hit's triangle names what it names in three.js.

A corner is not shared between faces. Each face's vertices carry that
face's outward normal, which keeps a box's edges crisp when the renderer
interpolates normals across a triangle.

Each face is a group, three.js's `addGroup` in `buildPlane`, with its
material index: +x is 0, -x is 1, +y is 2, -y is 3, +z is 4 and -z is 5. A
mesh that wears a list of six materials gives each face its own, as in
three.js. With one segment a side, a face is two triangles, so the face of
triangle `t` is `t // 2`.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BOX_GEOMETRY,
    BufferGeometry,
    MaterialIndex,
    NORMAL,
    POSITION,
    UV,
)
from core.user_data import UserData
from units.si import Length, METER


struct _Planes:
    """The arrays the six planes are written into, and where the next one
    starts: three.js's `vertices`, `normals`, `uvs`, `indices`,
    `numberOfVertices` and `groupStart`."""

    var positions: List[Float32]
    var normals: List[Float32]
    var uvs: List[Float32]
    var index: List[Int]
    var vertices: Int
    var group_start: Int
    # Each face's group: its start, count and material index.
    var groups: List[Int]

    def __init__(out self):
        """Start with nothing written."""
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.uvs = List[Float32]()
        self.index = List[Int]()
        self.vertices = 0
        self.group_start = 0
        self.groups = List[Int]()


def _plane(
    mut planes: _Planes,
    u: Int,
    v: Int,
    w: Int,
    udir: Float32,
    vdir: Float32,
    width: Float32,
    height: Float32,
    depth: Float32,
    grid_x: Int,
    grid_y: Int,
    material: Int,
):
    """Write one face, three.js's `buildPlane`.

    Args:
        planes: The arrays, and where this face starts.
        u: The axis across the face: 0 for x, 1 for y and 2 for z.
        v: The axis up the face.
        w: The axis the face faces along.
        udir: The direction `u` runs in, one or minus one.
        vdir: The direction `v` runs in.
        width: The face's extent along `u`.
        height: Its extent along `v`.
        depth: How far it lies along `w`, signed: its half is the face's
            place, and its sign the normal's.
        grid_x: Segments across.
        grid_y: Segments up.
        material: The group's material index.
    """
    var segment_width = width / Float32(grid_x)
    var segment_height = height / Float32(grid_y)
    var width_half = width / 2
    var height_half = height / 2
    var depth_half = depth / 2
    var grid_x1 = grid_x + 1
    var grid_y1 = grid_y + 1
    # A box has at least one segment a side: every loop here runs.
    for iy in range(grid_y1):  # pragma: no branch
        var y = Float32(iy) * segment_height - height_half
        for ix in range(grid_x1):  # pragma: no branch
            var x = Float32(ix) * segment_width - width_half
            var vector = SIMD[DType.float32, 4](0)
            vector[u] = x * udir
            vector[v] = y * vdir
            vector[w] = depth_half
            planes.positions.extend([vector[0], vector[1], vector[2]])
            var normal = SIMD[DType.float32, 4](0)
            normal[w] = 1 if depth > 0 else -1
            planes.normals.extend([normal[0], normal[1], normal[2]])
            planes.uvs.append(Float32(ix) / Float32(grid_x))
            planes.uvs.append(1 - Float32(iy) / Float32(grid_y))
    var start = planes.vertices
    for iy in range(grid_y):  # pragma: no branch
        for ix in range(grid_x):  # pragma: no branch
            var a = start + ix + grid_x1 * iy
            var b = start + ix + grid_x1 * (iy + 1)
            var c = start + (ix + 1) + grid_x1 * (iy + 1)
            var d = start + (ix + 1) + grid_x1 * iy
            planes.index.extend([a, b, d, b, c, d])
    var count = grid_x * grid_y * 6
    planes.groups.extend([planes.group_start, count, material])
    planes.group_start += count
    planes.vertices += grid_x1 * grid_y1


def box(
    width: Length,
    height: Length,
    depth: Length,
    width_segments: Int = 1,
    height_segments: Int = 1,
    depth_segments: Int = 1,
) raises -> BufferGeometry:
    """Return a box centered on the origin, three.js's `BoxGeometry`.

    Args:
        width: Extent along x.
        height: Extent along y.
        depth: Extent along z.
        width_segments: Segments along x. One by default, as in three.js.
        height_segments: Segments along y.
        depth_segments: Segments along z.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes, an
        index, and a group per face, its faces in three.js's order: +x,
        -x, +y, -y, +z, -z.

    Raises:
        Error: If any extent is not positive, or any segment count is
            below one. three.js floors a count and takes what it gets.
    """
    if width.value <= 0 or height.value <= 0 or depth.value <= 0:
        raise Error("A box needs positive extents")
    if width_segments < 1 or height_segments < 1 or depth_segments < 1:
        raise Error("A box needs at least one segment a side")
    var x = width.value
    var y = height.value
    var z = depth.value
    var geometry = BufferGeometry()
    var planes = _Planes()
    # three.js's six calls, axis by axis: x is 0, y 1 and z 2.
    _plane(planes, 2, 1, 0, -1, -1, z, y, x, depth_segments, height_segments, 0)
    _plane(planes, 2, 1, 0, 1, -1, z, y, -x, depth_segments, height_segments, 1)
    _plane(planes, 0, 2, 1, 1, 1, x, z, y, width_segments, depth_segments, 2)
    _plane(planes, 0, 2, 1, 1, -1, x, z, -y, width_segments, depth_segments, 3)
    _plane(planes, 0, 1, 2, 1, -1, x, y, z, width_segments, height_segments, 4)
    _plane(
        planes, 0, 1, 2, -1, -1, x, y, -z, width_segments, height_segments, 5
    )
    var groups = planes.groups.copy()
    geometry.set_attribute(
        String(POSITION), BufferAttribute(planes.positions.copy(), 3)
    )
    geometry.set_attribute(
        String(NORMAL), BufferAttribute(planes.normals.copy(), 3)
    )
    geometry.set_attribute(String(UV), BufferAttribute(planes.uvs.copy(), 2))
    geometry.set_index(planes.index.copy())
    for face in range(6):  # pragma: no branch
        geometry.add_group(
            groups[face * 3],
            groups[face * 3 + 1],
            MaterialIndex(groups[face * 3 + 2]),
        )
    geometry.kind = BOX_GEOMETRY
    geometry.parameters = UserData()
    geometry.parameters.set_number("width", Float64(width.to(METER)))
    geometry.parameters.set_number("height", Float64(height.to(METER)))
    geometry.parameters.set_number("depth", Float64(depth.to(METER)))
    geometry.parameters.set_number("widthSegments", Float64(width_segments))
    geometry.parameters.set_number("heightSegments", Float64(height_segments))
    geometry.parameters.set_number("depthSegments", Float64(depth_segments))
    return geometry^


def cube(edge: Length) raises -> BufferGeometry:
    """Return a box with all three extents equal.

    Args:
        edge: The length of every edge.

    Returns:
        The geometry.

    Raises:
        Error: If `edge` is not positive.
    """
    return box(edge, edge, edge)
