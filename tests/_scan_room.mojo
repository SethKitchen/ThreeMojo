# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scan of a room that is known exactly, for the scan tests.

`room_scan` places flat splats on the floor, the ceiling and the four
walls of a box room, one storey above another, as a scanner would see
them from inside. The splats are written in SuperSplat's frame: up is
the scan's -y and north its -z, one unit to the meter. The plan can be
turned about +z, so a test can check that a frame's heading turns it
back.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
)
from generators.utils import Vec3d
from std.math import cos, pi, sin


@fieldwise_init
struct RoomPlan(ImplicitlyCopyable):
    """The room: its plan, its storeys and how densely it is scanned, in
    meters."""

    # The room's extent along x and y.
    var width: Float64
    var depth: Float64
    # The floor-to-floor height of each storey.
    var storey: Float64
    # The slab thickness between storeys: the ceiling is this far below
    # the floor above.
    var slab: Float64
    # How many storeys.
    var storeys: Int
    # The distance between splats on a surface.
    var spacing: Float64
    # The plan turn, in degrees, counterclockwise about +z.
    var turn: Float64
    # The plan corner at the origin moves here.
    var corner: Vec3d


def default_room() -> RoomPlan:
    """Return a room of 4 m by 5 m, one storey of 3 m, 0.3 m slabs."""
    return RoomPlan(4, 5, 3, 0.3, 1, 0.2, 0, Vec3d(0, 0, 0))


struct _Splats(Movable):
    """The arrays of a geometry, filled one splat at a time."""

    var centers: List[Float32]
    var covariances: List[Float32]
    var colors: List[UInt8]

    def __init__(out self):
        self.centers = List[Float32]()
        self.covariances = List[Float32]()
        self.colors = List[UInt8]()

    def add(mut self, plan: RoomPlan, p: Vec3d, normal: Int):
        """Add a flat splat at a building point, thin along one building
        axis: 0 for x, 1 for y and 2 for z."""
        var turn = plan.turn * pi / 180
        var c = cos(turn)
        var s = sin(turn)
        var x = p.x * c - p.y * s + plan.corner.x
        var y = p.x * s + p.y * c + plan.corner.y
        var z = p.z + plan.corner.z
        # SuperSplat's frame: building x is scan -x, y is scan -z and z is
        # scan -y.
        self.centers.append(Float32(-x))
        self.centers.append(Float32(-z))
        self.centers.append(Float32(-y))
        var wide = (plan.spacing * 0.6) * (plan.spacing * 0.6)
        var thin = 0.004 * 0.004
        var v = List[Float64](length=3, fill=wide)
        v[normal] = thin
        # The plan block turned, then mapped to scan axes; z stays z.
        var bxx = c * c * v[0] + s * s * v[1]
        var bxy = c * s * (v[0] - v[1])
        var byy = s * s * v[0] + c * c * v[1]
        var bzz = v[2]
        # Scan (X, Y, Z) = (-x, -z, -y): xx, xy, xz, yy, yz, zz.
        self.covariances.append(Float32(bxx))
        self.covariances.append(Float32(0))
        self.covariances.append(Float32(bxy))
        self.covariances.append(Float32(bzz))
        self.covariances.append(Float32(0))
        self.covariances.append(Float32(byy))
        self.colors.append(180)
        self.colors.append(170)
        self.colors.append(160)
        self.colors.append(230)


def _steps(length: Float64, spacing: Float64) -> Int:
    """Return how many splats cover a length, ends included."""
    return Int(length / spacing + 0.5) + 1


def room_scan(plan: RoomPlan) raises -> GaussianSplatGeometry:
    """Return the splats of a room; see the module docstring."""
    var out = _Splats()
    var nx = _steps(plan.width, plan.spacing)
    var ny = _steps(plan.depth, plan.spacing)
    for level in range(plan.storeys):
        var floor = Float64(level) * plan.storey
        var ceiling = floor + plan.storey - plan.slab
        var nz = _steps(ceiling - floor, plan.spacing)
        for a in range(nx):
            for b in range(ny):
                var x = Float64(a) * plan.width / Float64(nx - 1)
                var y = Float64(b) * plan.depth / Float64(ny - 1)
                out.add(plan, Vec3d(x, y, floor), 2)
                out.add(plan, Vec3d(x, y, ceiling), 2)
        for c in range(1, nz - 1):
            var z = floor + Float64(c) * (ceiling - floor) / Float64(nz - 1)
            for a in range(nx):
                var x = Float64(a) * plan.width / Float64(nx - 1)
                out.add(plan, Vec3d(x, 0, z), 1)
                out.add(plan, Vec3d(x, plan.depth, z), 1)
            for b in range(ny):
                var y = Float64(b) * plan.depth / Float64(ny - 1)
                out.add(plan, Vec3d(0, y, z), 0)
                out.add(plan, Vec3d(plan.width, y, z), 0)
    return create_gaussian_splat_geometry(
        out.centers.copy(), out.covariances.copy(), out.colors.copy()
    )


def house_scan(plan: RoomPlan, margin: Float64) raises -> GaussianSplatGeometry:
    """Return the splats that a drone sees of a box house: the ground
    around it, `margin` wide, the outside of its walls and its roof. The
    house is one storey of `plan.storey` meters; the inside is not seen.
    """
    var out = _Splats()
    var nx = _steps(plan.width + 2 * margin, plan.spacing)
    var ny = _steps(plan.depth + 2 * margin, plan.spacing)
    for a in range(nx):
        for b in range(ny):
            var x = -margin + Float64(a) * (plan.width + 2 * margin) / Float64(
                nx - 1
            )
            var y = -margin + Float64(b) * (plan.depth + 2 * margin) / Float64(
                ny - 1
            )
            var inside = x > 0 and x < plan.width and y > 0 and y < plan.depth
            if not inside:
                out.add(plan, Vec3d(x, y, 0), 2)
    var wx = _steps(plan.width, plan.spacing)
    var wy = _steps(plan.depth, plan.spacing)
    var nz = _steps(plan.storey, plan.spacing)
    for a in range(wx):
        for b in range(wy):
            var x = Float64(a) * plan.width / Float64(wx - 1)
            var y = Float64(b) * plan.depth / Float64(wy - 1)
            out.add(plan, Vec3d(x, y, plan.storey), 2)
    for c in range(1, nz - 1):
        var z = Float64(c) * plan.storey / Float64(nz - 1)
        for a in range(wx):
            var x = Float64(a) * plan.width / Float64(wx - 1)
            out.add(plan, Vec3d(x, 0, z), 1)
            out.add(plan, Vec3d(x, plan.depth, z), 1)
        for b in range(wy):
            var y = Float64(b) * plan.depth / Float64(wy - 1)
            out.add(plan, Vec3d(0, y, z), 0)
            out.add(plan, Vec3d(plan.width, y, z), 0)
    return create_gaussian_splat_geometry(
        out.centers.copy(), out.covariances.copy(), out.colors.copy()
    )
