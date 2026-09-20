# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Marching-tetrahedra zero set of a humanoid bone field.

Each cube of the bounding grid splits into six tetrahedra. Connectivity
comes from the field. It does not come from a deformed capsule. Normals come
from the sampled field gradient. Texture coordinates are cylindrical around
y: `u` around, `v` up.

`detail` sets how many cells run along the bone. Eight is the least.
Twenty-four is the default. Sixty-four is the most.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from extensions.humanoid.skeleton.field import DistanceField
from math.vector3 import Vector3
from std.math import atan2, max, min, pi

comptime MIN_DETAIL = 8
comptime MAX_DETAIL = 64
comptime MIN_LONG_CELLS = 24
comptime MIN_CROSS_CELLS = 12


@fieldwise_init
struct SampleGrid(ImplicitlyCopyable):
    """How a bounding box is split for marching tetrahedra."""

    var nx: Int
    var ny: Int
    var nz: Int
    var dx: Float32
    var dy: Float32
    var dz: Float32
    var sx: Int
    var sy: Int
    var sz: Int
    var span_y: Float32


def check_detail(detail: Int, bone: String) raises:
    """Refuse a mesh density a bone cannot use.

    Args:
        detail: Requested cells along the bone.
        bone: Name used in the error text.

    Raises:
        Error: If `detail` is less than eight or more than sixty-four.
    """
    if detail < MIN_DETAIL:
        raise Error("A " + bone + " needs a detail of at least eight")
    if detail > MAX_DETAIL:
        raise Error("A " + bone + "'s detail cannot exceed sixty-four")


def make_grid(low: Vector3, high: Vector3, detail: Int) -> SampleGrid:
    """Return the marching grid for a bounding box and a detail value.

    Args:
        low: Minimum corner of the solid, in meters.
        high: Maximum corner of the solid, in meters.
        detail: Requested cells along the long axis.

    Returns:
        Cell counts and sizes. The long axis is y.
    """
    var span_x = high.x - low.x
    var span_y = high.y - low.y
    var span_z = high.z - low.z
    var ny = _long_cells(detail)
    var cell = span_y / Float32(ny)
    var nx = _axis_cells(span_x, cell, MIN_CROSS_CELLS)
    var nz = _axis_cells(span_z, cell, MIN_CROSS_CELLS)
    var dx = span_x / Float32(nx)
    var dy = span_y / Float32(ny)
    var dz = span_z / Float32(nz)
    return SampleGrid(nx, ny, nz, dx, dy, dz, nx + 1, ny + 1, nz + 1, span_y)


def sample_field[
    F: DistanceField
](field: F, low: Vector3, grid: SampleGrid) -> List[Float32]:
    """Return `field.distance` at every grid vertex.

    Args:
        field: The implicit solid.
        low: Minimum corner matching `grid`.
        grid: Cell counts from `make_grid`.

    Returns:
        Distances in x-fastest, then y, then z order.
    """
    var samples = List[Float32]()
    for iz in range(grid.sz):  # pragma: no branch
        var z = low.z + Float32(iz) * grid.dz
        for iy in range(grid.sy):  # pragma: no branch
            var y = low.y + Float32(iy) * grid.dy
            for ix in range(grid.sx):  # pragma: no branch
                var x = low.x + Float32(ix) * grid.dx
                samples.append(field.distance(Vector3(x, y, z)))
    return samples^


def mesh_samples(
    samples: List[Float32],
    low: Vector3,
    grid: SampleGrid,
    bone: String,
) raises -> BufferGeometry:
    """Return the zero set of cached field samples.

    Args:
        samples: Distances from `sample_field`.
        low: Minimum corner matching `grid`.
        grid: Cell counts from `make_grid`.
        bone: Name used if the field produces no surface.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If the field produces no surface.
    """
    var positions = List[Float32]()
    var indices = List[Int]()
    for iz in range(grid.nz):  # pragma: no branch
        for iy in range(grid.ny):  # pragma: no branch
            for ix in range(grid.nx):  # pragma: no branch
                _march_cube(
                    positions,
                    indices,
                    samples,
                    low,
                    grid.dx,
                    grid.dy,
                    grid.dz,
                    grid.sx,
                    grid.sy,
                    ix,
                    iy,
                    iz,
                )
    _require_triangles(indices, bone)
    var count = len(positions) // 3
    var normals = _sampled_normals(positions, indices, samples, low, grid)
    var uvs = List[Float32]()
    var two_pi = pi * Float32(2)
    for index in range(count):  # pragma: no branch
        var px = positions[index * 3]
        var py = positions[index * 3 + 1]
        var pz = positions[index * 3 + 2]
        var u = atan2(px, pz) / two_pi
        if u < 0:
            u = u + Float32(1)
        var v = _clamp01((py - low.y) / grid.span_y)
        uvs.append(u)
        uvs.append(v)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(indices^)
    return geometry^


def mesh_field[
    F: DistanceField
](
    field: F, low: Vector3, high: Vector3, detail: Int, bone: String
) raises -> BufferGeometry:
    """Sample `field` and return its marching-tetrahedra surface.

    Args:
        field: The implicit solid.
        low: Minimum corner of the solid.
        high: Maximum corner of the solid.
        detail: Cells along the bone. Must already pass `check_detail`.
        bone: Name used if the field produces no surface.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If the field produces no surface.
    """
    var grid = make_grid(low, high, detail)
    return mesh_samples(sample_field(field, low, grid), low, grid, bone)


def _clamp01(value: Float32) -> Float32:
    """Return `value` held to 0 through 1."""
    if value < 0:
        return 0
    if value > 1:
        return 1
    return value


def _long_cells(detail: Int) -> Int:
    """Return how many cells run along the bone for `detail`."""
    var ny = detail * 3
    if ny < MIN_LONG_CELLS:
        return MIN_LONG_CELLS
    return ny


def _axis_cells(span: Float32, cell: Float32, least: Int) -> Int:
    """Return how many cells of size `cell` fit in `span`, at least `least`."""
    var n = Int(span / cell + Float32(0.5))
    if n < least:
        return least
    return n


def _require_triangles(indices: List[Int], bone: String) raises:
    """Refuse an empty isosurface."""
    if len(indices) == 0:
        raise Error("A " + bone + " field produced no surface")


def _unit_face(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
    """Return the unit geometric normal of triangle `a`, `b`, `c`."""
    var n = b - a
    var e2 = c - a
    n.cross(e2)
    if n.length() == 0:
        return Vector3(0, 1, 0)
    n.normalize()
    return n


def _sampled_normals(
    positions: List[Float32],
    mut indices: List[Int],
    samples: List[Float32],
    low: Vector3,
    grid: SampleGrid,
) -> List[Float32]:
    """Return the trilinear sampled-field gradient at each mesh vertex."""
    var normals = List[Float32]()
    for vertex in range(len(positions) // 3):  # pragma: no branch
        var gx = (positions[vertex * 3] - low.x) / grid.dx
        var gy = (positions[vertex * 3 + 1] - low.y) / grid.dy
        var gz = (positions[vertex * 3 + 2] - low.z) / grid.dz
        gx = max(Float32(0), min(Float32(grid.nx), gx))
        gy = max(Float32(0), min(Float32(grid.ny), gy))
        gz = max(Float32(0), min(Float32(grid.nz), gz))
        var ix = min(Int(gx), grid.nx - 1)
        var iy = min(Int(gy), grid.ny - 1)
        var iz = min(Int(gz), grid.nz - 1)
        var tx = gx - Float32(ix)
        var ty = gy - Float32(iy)
        var tz = gz - Float32(iz)
        var ux = Float32(1) - tx
        var uy = Float32(1) - ty
        var uz = Float32(1) - tz
        var f000 = _sample(samples, grid.sx, grid.sy, ix, iy, iz)
        var f100 = _sample(samples, grid.sx, grid.sy, ix + 1, iy, iz)
        var f010 = _sample(samples, grid.sx, grid.sy, ix, iy + 1, iz)
        var f110 = _sample(samples, grid.sx, grid.sy, ix + 1, iy + 1, iz)
        var f001 = _sample(samples, grid.sx, grid.sy, ix, iy, iz + 1)
        var f101 = _sample(samples, grid.sx, grid.sy, ix + 1, iy, iz + 1)
        var f011 = _sample(samples, grid.sx, grid.sy, ix, iy + 1, iz + 1)
        var f111 = _sample(samples, grid.sx, grid.sy, ix + 1, iy + 1, iz + 1)
        var dx = (
            uy * uz * (f100 - f000)
            + ty * uz * (f110 - f010)
            + uy * tz * (f101 - f001)
            + ty * tz * (f111 - f011)
        ) / grid.dx
        var dy = (
            ux * uz * (f010 - f000)
            + tx * uz * (f110 - f100)
            + ux * tz * (f011 - f001)
            + tx * tz * (f111 - f101)
        ) / grid.dy
        var dz = (
            ux * uy * (f001 - f000)
            + tx * uy * (f101 - f100)
            + ux * ty * (f011 - f010)
            + tx * ty * (f111 - f110)
        ) / grid.dz
        var normal = Vector3(dx, dy, dz)
        normal.normalize()
        normals.append(normal.x)
        normals.append(normal.y)
        normals.append(normal.z)
    var corner = 0
    while corner < len(indices):
        var i0 = indices[corner]
        var i1 = indices[corner + 1]
        var i2 = indices[corner + 2]
        var a = Vector3(
            positions[i0 * 3], positions[i0 * 3 + 1], positions[i0 * 3 + 2]
        )
        var b = Vector3(
            positions[i1 * 3], positions[i1 * 3 + 1], positions[i1 * 3 + 2]
        )
        var c = Vector3(
            positions[i2 * 3], positions[i2 * 3 + 1], positions[i2 * 3 + 2]
        )
        var face = _unit_face(a, b, c)
        var mean = Vector3(
            normals[i0 * 3] + normals[i1 * 3] + normals[i2 * 3],
            normals[i0 * 3 + 1] + normals[i1 * 3 + 1] + normals[i2 * 3 + 1],
            normals[i0 * 3 + 2] + normals[i1 * 3 + 2] + normals[i2 * 3 + 2],
        )
        if face.dot(mean) <= 0:
            indices[corner + 1] = i2
            indices[corner + 2] = i1
        corner += 3
    return normals^


def _sample(
    samples: List[Float32], sx: Int, sy: Int, ix: Int, iy: Int, iz: Int
) -> Float32:
    """Return the cached field at grid vertex `(ix, iy, iz)`."""
    return samples[ix + iy * sx + iz * sx * sy]


def _grid_point(
    origin: Vector3,
    dx: Float32,
    dy: Float32,
    dz: Float32,
    ix: Int,
    iy: Int,
    iz: Int,
) -> Vector3:
    """Return the world position of grid vertex `(ix, iy, iz)`."""
    return Vector3(
        origin.x + Float32(ix) * dx,
        origin.y + Float32(iy) * dy,
        origin.z + Float32(iz) * dz,
    )


def _march_cube(
    mut positions: List[Float32],
    mut indices: List[Int],
    samples: List[Float32],
    origin: Vector3,
    dx: Float32,
    dy: Float32,
    dz: Float32,
    sx: Int,
    sy: Int,
    ix: Int,
    iy: Int,
    iz: Int,
):
    """Emit isosurface triangles for the six tetrahedra of one cube."""
    var p0 = _grid_point(origin, dx, dy, dz, ix, iy, iz)
    var p1 = _grid_point(origin, dx, dy, dz, ix + 1, iy, iz)
    var p2 = _grid_point(origin, dx, dy, dz, ix + 1, iy + 1, iz)
    var p3 = _grid_point(origin, dx, dy, dz, ix, iy + 1, iz)
    var p4 = _grid_point(origin, dx, dy, dz, ix, iy, iz + 1)
    var p5 = _grid_point(origin, dx, dy, dz, ix + 1, iy, iz + 1)
    var p6 = _grid_point(origin, dx, dy, dz, ix + 1, iy + 1, iz + 1)
    var p7 = _grid_point(origin, dx, dy, dz, ix, iy + 1, iz + 1)
    var d0 = _sample(samples, sx, sy, ix, iy, iz)
    var d1 = _sample(samples, sx, sy, ix + 1, iy, iz)
    var d2 = _sample(samples, sx, sy, ix + 1, iy + 1, iz)
    var d3 = _sample(samples, sx, sy, ix, iy + 1, iz)
    var d4 = _sample(samples, sx, sy, ix, iy, iz + 1)
    var d5 = _sample(samples, sx, sy, ix + 1, iy, iz + 1)
    var d6 = _sample(samples, sx, sy, ix + 1, iy + 1, iz + 1)
    var d7 = _sample(samples, sx, sy, ix, iy + 1, iz + 1)
    _clip_tetrahedron(positions, indices, p0, p1, p2, p6, d0, d1, d2, d6)
    _clip_tetrahedron(positions, indices, p0, p2, p3, p6, d0, d2, d3, d6)
    _clip_tetrahedron(positions, indices, p0, p3, p7, p6, d0, d3, d7, d6)
    _clip_tetrahedron(positions, indices, p0, p7, p4, p6, d0, d7, d4, d6)
    _clip_tetrahedron(positions, indices, p0, p4, p5, p6, d0, d4, d5, d6)
    _clip_tetrahedron(positions, indices, p0, p5, p1, p6, d0, d5, d1, d6)


def _lerp_zero(a: Vector3, b: Vector3, da: Float32, db: Float32) -> Vector3:
    """Return the zero of the field along the segment from `a` to `b`."""
    var span = da - db
    var t = Float32(0.5)
    if span != 0:
        t = da / span
        if t < 0:
            t = 0
        if t > 1:
            t = 1
    return Vector3(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
    )


def _emit_triangle(
    mut positions: List[Float32],
    mut indices: List[Int],
    p0: Vector3,
    p1: Vector3,
    p2: Vector3,
    inside: Vector3,
):
    """Append one triangle, wound so its geometric normal faces out."""
    var i0 = len(positions) // 3
    positions.append(p0.x)
    positions.append(p0.y)
    positions.append(p0.z)
    positions.append(p1.x)
    positions.append(p1.y)
    positions.append(p1.z)
    positions.append(p2.x)
    positions.append(p2.y)
    positions.append(p2.z)
    var e1 = p1 - p0
    var e2 = p2 - p0
    e1.cross(e2)
    var cx = (p0.x + p1.x + p2.x) * Float32(1.0 / 3.0)
    var cy = (p0.y + p1.y + p2.y) * Float32(1.0 / 3.0)
    var cz = (p0.z + p1.z + p2.z) * Float32(1.0 / 3.0)
    var to_inside = Vector3(inside.x - cx, inside.y - cy, inside.z - cz)
    if e1.dot(to_inside) > 0:
        indices.append(i0)
        indices.append(i0 + 2)
        indices.append(i0 + 1)
        return
    indices.append(i0)
    indices.append(i0 + 1)
    indices.append(i0 + 2)


def _mid2(a: Vector3, b: Vector3) -> Vector3:
    """Return the midpoint of `a` and `b`."""
    return Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5)


def _mid3(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
    """Return the centroid of `a`, `b` and `c`."""
    return Vector3(
        (a.x + b.x + c.x) * Float32(1.0 / 3.0),
        (a.y + b.y + c.y) * Float32(1.0 / 3.0),
        (a.z + b.z + c.z) * Float32(1.0 / 3.0),
    )


def _clip_tetrahedron(
    mut positions: List[Float32],
    mut indices: List[Int],
    a: Vector3,
    b: Vector3,
    c: Vector3,
    d: Vector3,
    da: Float32,
    db: Float32,
    dc: Float32,
    dd: Float32,
):
    """Emit the zero set of tet ABCD. Negative distance is inside."""
    var mask = 0
    if da < 0:
        mask = mask + 1
    if db < 0:
        mask = mask + 2
    if dc < 0:
        mask = mask + 4
    if dd < 0:
        mask = mask + 8
    if mask == 0:
        return
    if mask == 15:
        return
    var ab = _lerp_zero(a, b, da, db)
    var ac = _lerp_zero(a, c, da, dc)
    var ad = _lerp_zero(a, d, da, dd)
    var bc = _lerp_zero(b, c, db, dc)
    var bd = _lerp_zero(b, d, db, dd)
    var cd = _lerp_zero(c, d, dc, dd)
    if mask == 1:
        _emit_triangle(positions, indices, ab, ac, ad, a)
        return
    if mask == 2:
        _emit_triangle(positions, indices, ab, bd, bc, b)
        return
    if mask == 3:
        var ab_in = _mid2(a, b)
        _emit_triangle(positions, indices, ac, ad, bd, ab_in)
        _emit_triangle(positions, indices, ac, bd, bc, ab_in)
        return
    if mask == 4:
        _emit_triangle(positions, indices, ac, bc, cd, c)
        return
    if mask == 5:
        var ac_in = _mid2(a, c)
        _emit_triangle(positions, indices, ab, cd, ad, ac_in)
        _emit_triangle(positions, indices, ab, bc, cd, ac_in)
        return
    if mask == 6:
        var bc_in = _mid2(b, c)
        _emit_triangle(positions, indices, ab, bd, cd, bc_in)
        _emit_triangle(positions, indices, ab, cd, ac, bc_in)
        return
    if mask == 7:
        _emit_triangle(positions, indices, ad, bd, cd, _mid3(a, b, c))
        return
    if mask == 8:
        _emit_triangle(positions, indices, ad, cd, bd, d)
        return
    if mask == 9:
        var ad_in = _mid2(a, d)
        _emit_triangle(positions, indices, ab, ac, cd, ad_in)
        _emit_triangle(positions, indices, ab, cd, bd, ad_in)
        return
    if mask == 10:
        var bd_in = _mid2(b, d)
        _emit_triangle(positions, indices, ab, cd, bc, bd_in)
        _emit_triangle(positions, indices, ab, ad, cd, bd_in)
        return
    if mask == 11:
        _emit_triangle(positions, indices, ac, cd, bc, _mid3(a, b, d))
        return
    if mask == 12:
        var cd_in = _mid2(c, d)
        _emit_triangle(positions, indices, ac, bc, bd, cd_in)
        _emit_triangle(positions, indices, ac, bd, ad, cd_in)
        return
    if mask == 13:
        _emit_triangle(positions, indices, ab, bc, bd, _mid3(a, c, d))
        return
    _emit_triangle(positions, indices, ab, ad, ac, _mid3(b, c, d))
