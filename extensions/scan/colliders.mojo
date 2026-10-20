# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A static collider for a scanned place, from its occupancy grid.

A face of a solid voxel is exposed when the voxel beyond it is empty or
outside the grid. The exposed faces are the collider. In each slice of
the grid and for each of the six directions, the exposed faces are merged
into rectangles: a run along the first in-plane axis, then as many rows
of that run along the second axis as are all exposed. Each rectangle is
two triangles whose front faces out of the solid, as a
`extensions.physics` mesh shape reads them. A flat floor of any size is
then two triangles.

A scan only holds surfaces, so a solid voxel is a shell one voxel thick.
A fast small body can pass through such a shell between two steps. Turn
on the world's sphere-to-mesh continuous collision for one.
"""

from extensions.physics.body import BodyId, RigidBody, STATIC
from extensions.physics.shape import PhysicsMaterial, Shape
from extensions.physics.world import PhysicsWorld
from extensions.scan.occupancy import OccupancyGrid
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from units.si import KILOGRAM, Mass, METER


def _point(axis: Int, along: Float64, u: Float64, v: Float64) -> Vector3:
    """Return a point given along a face's axis and its two in-plane axes.

    Args:
        axis: The face's axis, 0 for x, 1 for y and 2 for z.
        along: The coordinate along it.
        u: The coordinate along the next axis, `(axis + 1) % 3`.
        v: The coordinate along the one after, `(axis + 2) % 3`.

    Returns:
        The point.
    """
    if axis == 0:
        return Vector3(Float32(along), Float32(u), Float32(v))
    if axis == 1:
        return Vector3(Float32(v), Float32(along), Float32(u))
    return Vector3(Float32(u), Float32(v), Float32(along))


def _cell(axis: Int, t: Int, a: Int, b: Int) -> Tuple[Int, Int, Int]:
    """Return a voxel's i, j and k from a slice and two in-plane indexes.

    Args:
        axis: The slice's axis.
        t: The index along it.
        a: The index along `(axis + 1) % 3`.
        b: The index along `(axis + 2) % 3`.

    Returns:
        The three indexes.
    """
    if axis == 0:
        return (t, a, b)
    if axis == 1:
        return (b, t, a)
    return (a, b, t)


def _exposed(
    grid: OccupancyGrid, axis: Int, step: Int, t: Int, a: Int, b: Int
) -> Bool:
    """Return True if a voxel is solid and the one beyond a face is not.

    Args:
        grid: The grid.
        axis: The face's axis.
        step: 1 for the face on the + side, -1 for the - side.
        t: The voxel's index along the axis.
        a: Its index along `(axis + 1) % 3`.
        b: Its index along `(axis + 2) % 3`.

    Returns:
        Whether the face is exposed.
    """
    var i: Int
    var j: Int
    var k: Int
    i, j, k = _cell(axis, t, a, b)
    if not grid.is_solid(i, j, k):
        return False
    var ni: Int
    var nj: Int
    var nk: Int
    ni, nj, nk = _cell(axis, t + step, a, b)
    return not grid.is_solid(ni, nj, nk)


def collision_triangles(grid: OccupancyGrid) -> List[Triangle]:
    """Return the triangles of a grid's exposed faces.

    Args:
        grid: The grid.

    Returns:
        Two triangles for each merged rectangle; none when no voxel is
        solid.
    """
    var counts: List[Int] = [grid.nx, grid.ny, grid.nz]
    var low: List[Float64] = [grid.origin.x, grid.origin.y, grid.origin.z]
    var edge = grid.voxel.to(METER)
    var triangles = List[Triangle]()
    for axis in range(3):
        var u = (axis + 1) % 3
        var v = (axis + 2) % 3
        var nu = counts[u]
        var nv = counts[v]
        for step in [1, -1]:  # pragma: no branch
            var shift = 1 if step == 1 else 0
            for t in range(counts[axis]):  # pragma: no branch
                var mask = List[Bool](length=nu * nv, fill=False)
                for b in range(nv):  # pragma: no branch
                    for a in range(nu):  # pragma: no branch
                        mask[b * nu + a] = _exposed(grid, axis, step, t, a, b)
                var along = low[axis] + Float64(t + shift) * edge
                for b in range(nv):  # pragma: no branch
                    for a in range(nu):  # pragma: no branch
                        if not mask[b * nu + a]:
                            continue
                        var width = 1
                        while a + width < nu and mask[b * nu + a + width]:
                            width += 1
                        var height = 1
                        var grow = True
                        while grow and b + height < nv:
                            for w in range(width):  # pragma: no branch
                                if not mask[(b + height) * nu + a + w]:
                                    grow = False
                            if grow:
                                height += 1
                        for h in range(height):  # pragma: no branch
                            for w in range(width):  # pragma: no branch
                                mask[(b + h) * nu + a + w] = False
                        var u0 = low[u] + Float64(a) * edge
                        var u1 = low[u] + Float64(a + width) * edge
                        var v0 = low[v] + Float64(b) * edge
                        var v1 = low[v] + Float64(b + height) * edge
                        var p0 = _point(axis, along, u0, v0)
                        var p1 = _point(axis, along, u1, v0)
                        var p2 = _point(axis, along, u1, v1)
                        var p3 = _point(axis, along, u0, v1)
                        if step == 1:
                            triangles.append(Triangle(p0, p1, p2))
                            triangles.append(Triangle(p0, p2, p3))
                        else:
                            triangles.append(Triangle(p0, p2, p1))
                            triangles.append(Triangle(p0, p3, p2))
    return triangles^


def scan_collider(
    grid: OccupancyGrid, material: PhysicsMaterial
) raises -> RigidBody:
    """Return a static body whose shape is a grid's exposed faces.

    Args:
        grid: The grid.
        material: The friction and restitution of the surfaces.

    Returns:
        The body, at the world origin. Its triangles are already in
        building coordinates.

    Raises:
        Error: If no voxel is solid, or the material is not valid.
    """
    var triangles = collision_triangles(grid)
    if len(triangles) == 0:
        raise Error("Scan collider: no voxel is solid")
    material.check()
    var body = RigidBody(
        STATIC,
        Shape.mesh(triangles^),
        Mass(0, KILOGRAM),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    body.material = material
    return body^


def add_scan_collider(
    mut world: PhysicsWorld, grid: OccupancyGrid, material: PhysicsMaterial
) raises -> BodyId:
    """Add a grid's static collider to a physics world.

    Args:
        world: The world.
        grid: The grid.
        material: The friction and restitution of the surfaces.

    Returns:
        The new body.

    Raises:
        Error: Everything that `scan_collider` and
            `PhysicsWorld.add_body` raise.
    """
    return world.add_body(scan_collider(grid, material))
