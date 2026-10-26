# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The parts of a scanned place: what stands apart from the ground, as
pieces to measure, weigh, simulate and use again.

`scan_parts` cuts an occupancy grid into parts. A part is a set of solid
voxels above the ground layer that touch each other through a face. A set
of fewer than `PartOptions.min_voxels` voxels is a floater of the scan,
and is no part. The parts are in order of size, the largest first, so
part 0 of an outside scan is its largest building. `scan_parts_on` cuts
the parts above a ground surface instead of a layer, such as the slope
of a hillside that `extensions.scan.terrain` finds.

Each part has:

- **Geometry.** Its voxels and their box, its volume and the area of its
  faces that face something other than itself. `part_grid` gives the part
  alone as a grid of its own, so that `extensions.scan.colliders` makes
  its mesh and every reader of a grid reads it.
- **Engineering.** `part_mass` weighs the part at a density: its center of
  mass and its inertia tensor about that center. A scan sees surfaces, so
  `PART_SHELL` weighs the solid voxels alone: a shell one voxel thick, the
  least that the part can weigh. `PART_SOLID` also weighs the voxels that
  the part encloses, as for a solid object such as a rock or a pier.
  `part_footing` takes the weight down to the voxels that bear on the
  ground: the area it bears on, the pressure under it, and how far its
  center of mass is from the edge of its base. The tip angle is how far
  the part can lean before its center of mass passes that edge.
- **Physics.** `part_body` makes the part a dynamic rigid body of its
  mass, for `extensions.physics`. Its shape is the convex hull of the
  corners that `part_hull` finds. `part_bed` is the ground that the body
  stands on, as a grid for a static collider.
- **Reuse.** `part_splats` copies the splats of the part out of the scan,
  harmonics and all, in scan coordinates. A `GaussianSplat` of them draws
  the part alone; a node of its own places it anywhere, in this scene or
  another, and the spherical harmonics turn with the node.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
)
from core.ordinal import ordinal_label, ordinal_valid
from extensions.physics.body import DYNAMIC, RigidBody
from extensions.physics.shape import PhysicsMaterial, Shape
from extensions.scan.clean import splat_subset
from extensions.scan.frame import ScanFrame
from extensions.scan.occupancy import OccupancyGrid, ScanRegion
from extensions.scan.terrain import GroundSurface, flat_ground, ground_grid
from generators.utils import Vec3d
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import atan2, floor, sqrt
from units.si import (
    Acceleration64,
    Angle64,
    Area64,
    Density64,
    KILOGRAM,
    KILOGRAM_PER_CUBIC_METER,
    KILOGRAM_SQUARE_METER,
    Length64,
    Mass,
    Mass64,
    METER,
    METER_PER_SECOND_SQUARED,
    PASCAL,
    Pressure64,
    Quantity,
    RADIAN,
    SQUARE_METER,
    Volume64,
    CUBIC_METER,
)

comptime MomentOfInertia64 = Quantity[2, 1, 0, 0, 0, DType.float64]
"""A moment of inertia, in `Float64`."""


@fieldwise_init
struct PartFill(Equatable, ImplicitlyCopyable, Writable):
    """What of a part `part_mass` weighs."""

    var value: Int
    """The stored ordinal."""

    def is_valid(self) -> Bool:
        """Return True if this names one of the 2 fills.

        Returns:
            Whether the value is 0 or 1.
        """
        return ordinal_valid(self.value, 2 - 1)

    def name(self) -> String:
        """Return the fill's name.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        var names: List[String] = ["shell", "solid"]
        return ordinal_label(self.is_valid(), self.value, names, "unknown")


comptime PART_SHELL = PartFill(0)
"""The solid voxels alone: what the scan saw."""
comptime PART_SOLID = PartFill(1)
"""The solid voxels and the voxels they enclose."""


@fieldwise_init
struct PartOptions(ImplicitlyCopyable):
    """How a grid is cut into parts."""

    var ground: Int
    """The ground's layer: a voxel in it or below it is ground, and no part. -1 counts no voxel as ground."""
    var min_voxels: Int
    """The fewest voxels a part has, one at least."""

    def check(self, grid: OccupancyGrid) raises:
        """Refuse options that cannot cut a grid.

        Args:
            grid: The grid.

        Raises:
            Error: If the ground is not -1 to the grid's top layer, or the
                least count is below one.
        """
        if self.ground < -1 or self.ground >= grid.nz:
            raise Error(
                "Scan parts: the ground layer must be -1 to "
                + String(grid.nz - 1)
            )
        if self.min_voxels < 1:
            raise Error("Scan parts: a part has one voxel at least")


@fieldwise_init
struct ScanPart(Copyable, Movable):
    """One part: its voxels and their box, in voxel indices."""

    var voxels: List[Int]
    """The part's voxels, as `OccupancyGrid.index` gives them, in order."""
    var low: SIMD[DType.int64, 4]
    """The least i, j and k of its voxels."""
    var high: SIMD[DType.int64, 4]
    """The most i, j and k of its voxels."""

    def count(self) -> Int:
        """Return how many voxels the part has.

        Returns:
            The count.
        """
        return len(self.voxels)

    def region(self, grid: OccupancyGrid) -> ScanRegion:
        """Return the box of the part, in meters.

        Args:
            grid: The grid it is a part of.

        Returns:
            From the low corner of its least voxel to the high corner of
            its most.
        """
        return ScanRegion(
            grid.corner(Int(self.low[0]), Int(self.low[1]), Int(self.low[2])),
            grid.corner(
                Int(self.high[0]) + 1,
                Int(self.high[1]) + 1,
                Int(self.high[2]) + 1,
            ),
        )

    def volume(self, grid: OccupancyGrid) -> Volume64:
        """Return the volume of the part's voxels.

        Args:
            grid: The grid it is a part of.

        Returns:
            The count times a voxel's volume.
        """
        var edge = grid.voxel.to(METER)
        return Volume64(Float64(self.count()) * edge * edge * edge, CUBIC_METER)


struct ScanParts(Movable):
    """The parts of a grid, which part each voxel is in, and the ground
    they stand on."""

    var labels: List[Int]
    """For each voxel of the grid, its part, or -1."""
    var parts: List[ScanPart]
    """The parts, the largest first."""
    var ground: GroundSurface
    """The ground that the parts were cut above."""

    def __init__(
        out self,
        var labels: List[Int],
        var parts: List[ScanPart],
        var ground: GroundSurface,
    ):
        """Hold the parts.

        Args:
            labels: Each voxel's part.
            parts: The parts.
            ground: The ground they were cut above.
        """
        self.labels = labels^
        self.parts = parts^
        self.ground = ground^

    def check(self, label: Int) raises:
        """Refuse a part that is not one of these.

        Args:
            label: Its place in `parts`.

        Raises:
            Error: If there is no such part.
        """
        if label < 0 or label >= len(self.parts):
            raise Error(
                "Scan parts: there is no part "
                + String(label)
                + " of "
                + String(len(self.parts))
            )


def _neighbor(grid: OccupancyGrid, index: Int, face: Int) -> Int:
    """Return the voxel beyond a face of a voxel, or -1 past the grid.

    Args:
        grid: The grid.
        index: The voxel.
        face: 0 to 5: +x, -x, +y, -y, +z and -z.

    Returns:
        The neighbor's index, or -1.
    """
    var i = index % grid.nx
    var j = (index // grid.nx) % grid.ny
    var k = index // (grid.nx * grid.ny)
    var axis = face // 2
    var step = 1 - 2 * (face % 2)
    if axis == 0:
        i += step
    elif axis == 1:
        j += step
    else:
        k += step
    if not grid.contains(i, j, k):
        return -1
    return grid.index(i, j, k)


def scan_parts(grid: OccupancyGrid, options: PartOptions) raises -> ScanParts:
    """Cut a grid into parts above a ground layer; see the module
    docstring.

    Args:
        grid: The grid.
        options: The ground layer and the fewest voxels of a part.

    Returns:
        The parts, the largest first; parts of one size are in the order
        of their first voxel.

    Raises:
        Error: If the options are refused.
    """
    options.check(grid)
    return scan_parts_on(
        grid, flat_ground(grid, options.ground), options.min_voxels
    )


def scan_parts_on(
    grid: OccupancyGrid, ground: GroundSurface, min_voxels: Int
) raises -> ScanParts:
    """Cut a grid into parts above a ground surface.

    A voxel in its column's ground layer or below it is ground, and no
    part.

    Args:
        grid: The grid.
        ground: The ground, from `extensions.scan.terrain`.
        min_voxels: The fewest voxels a part has, one at least.

    Returns:
        The parts, the largest first; parts of one size are in the order
        of their first voxel.

    Raises:
        Error: If the ground is not a ground of the grid, or the least
            count is below one.
    """
    ground.check(grid)
    if min_voxels < 1:
        raise Error("Scan parts: a part has one voxel at least")
    var total = grid.nx * grid.ny * grid.nz
    var columns = grid.nx * grid.ny
    # -2 is a voxel still to visit; -1 is no part.
    var labels = List[Int](length=total, fill=-1)
    for index in range(total):  # pragma: no branch
        if (
            Float64(grid.weights[index]) >= grid.solid_weight
            and index // columns > ground.layers[index % columns]
        ):
            labels[index] = -2
    var found = List[ScanPart]()
    var stack = List[Int]()
    for seed in range(total):  # pragma: no branch
        if labels[seed] != -2:
            continue
        var voxels = List[Int]()
        labels[seed] = len(found)
        stack.append(seed)
        while len(stack) > 0:
            var index = stack.pop()
            voxels.append(index)
            for face in range(6):  # pragma: no branch
                var next = _neighbor(grid, index, face)
                if next >= 0 and labels[next] == -2:
                    labels[next] = len(found)
                    stack.append(next)
        sort(voxels)
        var low = SIMD[DType.int64, 4](Int64.MAX)
        var high = SIMD[DType.int64, 4](Int64.MIN)
        for index in voxels:  # pragma: no branch
            var at = SIMD[DType.int64, 4](
                Int64(index % grid.nx),
                Int64((index // grid.nx) % grid.ny),
                Int64(index // (grid.nx * grid.ny)),
                0,
            )
            low = min(low, at)
            high = max(high, at)
        found.append(ScanPart(voxels^, low, high))
    # Keep the parts large enough, largest first, and number them again.
    var order = List[Int]()
    for label in range(len(found)):
        if found[label].count() >= min_voxels:
            order.append(label)
    for at in range(1, len(order)):
        var moving = order[at]
        var place = at
        while (
            place > 0
            and found[order[place - 1]].count() < found[moving].count()
        ):
            order[place] = order[place - 1]
            place -= 1
        order[place] = moving
    var renumber = List[Int](length=len(found), fill=-1)
    var parts = List[ScanPart]()
    for at in range(len(order)):
        renumber[order[at]] = at
        parts.append(found[order[at]].copy())
    for index in range(total):  # pragma: no branch
        if labels[index] >= 0:
            labels[index] = renumber[labels[index]]
    return ScanParts(labels^, parts^, ground.copy())


def _voxel(grid: OccupancyGrid, index: Int) -> Tuple[Int, Int, Int]:
    """Return the i, j and k of a voxel.

    Args:
        grid: The grid.
        index: The voxel's index.

    Returns:
        Its indices along x, y and z.
    """
    return (
        index % grid.nx,
        (index // grid.nx) % grid.ny,
        index // (grid.nx * grid.ny),
    )


def part_area(
    grid: OccupancyGrid, parts: ScanParts, label: Int
) raises -> Area64:
    """Return the area of a part's outer faces.

    A face is outer when the voxel beyond it is not in the part: empty,
    outside the grid, ground or another part.

    Args:
        grid: The grid.
        parts: Its parts.
        label: The part.

    Returns:
        The count of outer faces times a face's area.

    Raises:
        Error: If there is no such part.
    """
    parts.check(label)
    ref part = parts.parts[label]
    var faces = 0
    for index in part.voxels:  # pragma: no branch
        for face in range(6):  # pragma: no branch
            var next = _neighbor(grid, index, face)
            if next < 0 or parts.labels[next] != label:
                faces += 1
    var edge = grid.voxel.to(METER)
    return Area64(Float64(faces) * edge * edge, SQUARE_METER)


def part_grid(
    grid: OccupancyGrid, parts: ScanParts, label: Int
) raises -> OccupancyGrid:
    """Return a part alone, as a grid of its own box.

    Args:
        grid: The grid.
        parts: Its parts.
        label: The part.

    Returns:
        A grid with the voxel and the solid weight of `grid`, over the
        part's box, whose part voxels keep their weights and whose other
        voxels are empty.

    Raises:
        Error: If there is no such part.
    """
    parts.check(label)
    ref part = parts.parts[label]
    var low = part.low
    var size = part.high - part.low + 1
    var alone = OccupancyGrid(
        grid.corner(Int(low[0]), Int(low[1]), Int(low[2])),
        grid.voxel,
        Int(size[0]),
        Int(size[1]),
        Int(size[2]),
        grid.solid_weight,
    )
    for index in part.voxels:  # pragma: no branch
        var i: Int
        var j: Int
        var k: Int
        i, j, k = _voxel(grid, index)
        alone.weights[
            alone.index(i - Int(low[0]), j - Int(low[1]), k - Int(low[2]))
        ] = grid.weights[index]
    return alone^


def _enclosed(
    grid: OccupancyGrid, parts: ScanParts, label: Int
) raises -> List[Int]:
    """Return the voxels of a part's box that the part encloses, its own
    voxels with them.

    A voxel of the box that is not in the part, and that a path of such
    voxels joins to a face of the box, is outside. Every other voxel of
    the box is enclosed.

    Args:
        grid: The grid.
        parts: Its parts.
        label: The part.

    Returns:
        The enclosed voxels, as grid indices, in order.

    Raises:
        Error: If there is no such part.
    """
    parts.check(label)
    ref part = parts.parts[label]
    var low = part.low
    var size = part.high - part.low + 1
    var nx = Int(size[0])
    var ny = Int(size[1])
    var nz = Int(size[2])
    # 0 is not yet reached, 1 is in the part, 2 is outside.
    var state = List[UInt8](length=nx * ny * nz, fill=0)
    for index in part.voxels:  # pragma: no branch
        var i: Int
        var j: Int
        var k: Int
        i, j, k = _voxel(grid, index)
        state[
            ((k - Int(low[2])) * ny + (j - Int(low[1]))) * nx
            + (i - Int(low[0]))
        ] = 1
    var stack = List[Int]()
    for k in range(nz):  # pragma: no branch
        for j in range(ny):  # pragma: no branch
            for i in range(nx):  # pragma: no branch
                var edge = (
                    i == 0
                    or j == 0
                    or k == 0
                    or i == nx - 1
                    or j == ny - 1
                    or k == nz - 1
                )
                var at = (k * ny + j) * nx + i
                if edge and state[at] == 0:
                    state[at] = 2
                    stack.append(at)
    while len(stack) > 0:
        var at = stack.pop()
        var i = at % nx
        var j = (at // nx) % ny
        var k = at // (nx * ny)
        for face in range(6):  # pragma: no branch
            var axis = face // 2
            var step = 1 - 2 * (face % 2)
            var ni = i + step if axis == 0 else i
            var nj = j + step if axis == 1 else j
            var nk = k + step if axis == 2 else k
            if ni < 0 or nj < 0 or nk < 0 or ni >= nx or nj >= ny or nk >= nz:
                continue
            var next = (nk * ny + nj) * nx + ni
            if state[next] == 0:
                state[next] = 2
                stack.append(next)
    var inside = List[Int]()
    for at in range(len(state)):  # pragma: no branch
        if state[at] != 2:
            var i = at % nx + Int(low[0])
            var j = (at // nx) % ny + Int(low[1])
            var k = at // (nx * ny) + Int(low[2])
            inside.append(grid.index(i, j, k))
    return inside^


@fieldwise_init
struct PartMass(ImplicitlyCopyable):
    """A part's mass, its center and its inertia about that center."""

    var mass: Mass64
    """The mass."""
    var center: Vec3d
    """The center of mass, in building coordinates, in meters."""
    var xx: MomentOfInertia64
    """The inertia about the x axis through the center."""
    var yy: MomentOfInertia64
    """The inertia about the y axis through the center."""
    var zz: MomentOfInertia64
    """The inertia about the z axis through the center."""
    var xy: MomentOfInertia64
    """The xy product of inertia, `-sum(m x y)`."""
    var xz: MomentOfInertia64
    """The xz product of inertia, `-sum(m x z)`."""
    var yz: MomentOfInertia64
    """The yz product of inertia, `-sum(m y z)`."""
    var fill: PartFill
    """What was weighed."""


def part_mass(
    grid: OccupancyGrid,
    parts: ScanParts,
    label: Int,
    density: Density64,
    fill: PartFill,
) raises -> PartMass:
    """Weigh a part at a density; see the module docstring.

    Each voxel weighed is a cube of the density. The inertia sums each
    cube's own, `m a^2 / 6` about each axis for an edge `a`, and its mass
    at its center.

    Args:
        grid: The grid.
        parts: Its parts.
        label: The part.
        density: The density of what the part is made of.
        fill: Whether to weigh the shell or the solid.

    Returns:
        The mass, the center and the inertia.

    Raises:
        Error: If there is no such part, the fill is not valid, or the
            density is not positive and finite.
    """
    if not fill.is_valid():
        raise Error("Scan parts: a fill is 0 or 1, not " + String(fill.value))
    var rho = density.to(KILOGRAM_PER_CUBIC_METER)
    if not (rho > 0 and rho < Float64.MAX):
        raise Error("Scan parts: a density must be positive and finite")
    var voxels: List[Int]
    if fill == PART_SOLID:
        voxels = _enclosed(grid, parts, label)
    else:
        parts.check(label)
        voxels = parts.parts[label].voxels.copy()
    var edge = grid.voxel.to(METER)
    var cube = rho * edge * edge * edge
    var half = edge * 0.5
    var sum = Vec3d(0, 0, 0)
    for index in voxels:  # pragma: no branch
        var i: Int
        var j: Int
        var k: Int
        i, j, k = _voxel(grid, index)
        sum = sum + grid.corner(i, j, k) + Vec3d(half, half, half)
    var count = Float64(len(voxels))
    var center = sum * (1 / count)
    var xx = Float64(0)
    var yy = Float64(0)
    var zz = Float64(0)
    var xy = Float64(0)
    var xz = Float64(0)
    var yz = Float64(0)
    for index in voxels:  # pragma: no branch
        var i: Int
        var j: Int
        var k: Int
        i, j, k = _voxel(grid, index)
        var r = grid.corner(i, j, k) + Vec3d(half, half, half) - center
        xx += r.y * r.y + r.z * r.z
        yy += r.x * r.x + r.z * r.z
        zz += r.x * r.x + r.y * r.y
        xy -= r.x * r.y
        xz -= r.x * r.z
        yz -= r.y * r.z
    var own = count * edge * edge / 6
    return PartMass(
        Mass64(cube * count, KILOGRAM),
        center,
        MomentOfInertia64(cube * (xx + own), KILOGRAM_SQUARE_METER),
        MomentOfInertia64(cube * (yy + own), KILOGRAM_SQUARE_METER),
        MomentOfInertia64(cube * (zz + own), KILOGRAM_SQUARE_METER),
        MomentOfInertia64(cube * xy, KILOGRAM_SQUARE_METER),
        MomentOfInertia64(cube * xz, KILOGRAM_SQUARE_METER),
        MomentOfInertia64(cube * yz, KILOGRAM_SQUARE_METER),
        fill,
    )


@fieldwise_init
struct PartFooting(ImplicitlyCopyable):
    """How a part stands on the ground."""

    var base: Int
    """The lowest layer of the feet it bears on."""
    var area: Area64
    """The plan area of the feet it bears on."""
    var pressure: Pressure64
    """Its weight over that area."""
    var margin: Length64
    """How far the center of mass's plan point is inside the edge of the base's convex hull; negative outside it."""
    var tip: Angle64
    """How far the part can lean before its center of mass passes that edge; negative when it cannot stand."""

    def stands(self) -> Bool:
        """Return whether the center of mass is over the base.

        Returns:
            Whether the margin is above zero.
        """
        return self.margin.to(METER) > 0


def _cross(o: Vec3d, a: Vec3d, b: Vec3d) -> Float64:
    """Return the z of `(a - o) x (b - o)`.

    Args:
        o: The origin.
        a: The first point.
        b: The second point.

    Returns:
        Positive when o, a and b turn to the left.
    """
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


def _plan_hull(var points: List[Vec3d]) -> List[Vec3d]:
    """Return the convex hull of plan points, counterclockwise, Andrew's
    monotone chain.

    Args:
        points: Three points at least, not on one line; z is ignored.

    Returns:
        The hull's corners, counterclockwise, with no point on an edge.
    """
    # Sort by x, then y.
    for at in range(1, len(points)):  # pragma: no branch
        var moving = points[at]
        var place = at
        while place > 0 and (
            points[place - 1].x > moving.x
            or (
                points[place - 1].x == moving.x
                and points[place - 1].y > moving.y
            )
        ):
            points[place] = points[place - 1]
            place -= 1
        points[place] = moving
    var hull = List[Vec3d]()
    for pass_ in range(2):  # pragma: no branch
        var start = len(hull)
        for at in range(len(points)):  # pragma: no branch
            var point = (
                points[at] if pass_ == 0 else points[len(points) - 1 - at]
            )
            while (
                len(hull) >= start + 2
                and _cross(hull[len(hull) - 2], hull[len(hull) - 1], point) <= 0
            ):
                _ = hull.pop()
            hull.append(point)
        _ = hull.pop()
    return hull^


def part_footing(
    grid: OccupancyGrid,
    parts: ScanParts,
    label: Int,
    mass: PartMass,
    gravity: Acceleration64,
) raises -> PartFooting:
    """Take a part's weight down to the ground.

    The foot of a column of the part is its lowest voxel in that column.
    The part bears on each foot that is one layer above its column's
    ground layer, or higher by no more than the ground's tolerance. A
    part that touches no ground bears on its lowest layer. The margin is
    to the edge of the plan hull of those voxels, and the tip angle takes
    the height of the center of mass above the lowest of them.

    Args:
        grid: The grid.
        parts: Its parts.
        label: The part.
        mass: The part's mass, from `part_mass`.
        gravity: The acceleration of gravity.

    Returns:
        The base, its area, the pressure on it, and the center of mass's
        margin and tip angle over it.

    Raises:
        Error: If there is no such part, or the gravity is not positive
            and finite.
    """
    var g = gravity.to(METER_PER_SECOND_SQUARED)
    if not (g > 0 and g < Float64.MAX):
        raise Error("Scan parts: gravity must be positive and finite")
    parts.check(label)
    ref part = parts.parts[label]
    var columns = grid.nx * grid.ny
    var seen = List[Bool](length=columns, fill=False)
    var bearing = List[Int]()
    var base = grid.nz
    # The voxels are in order, so the foot of each column comes first.
    for index in part.voxels:  # pragma: no branch
        var column = index % columns
        if seen[column]:
            continue
        seen[column] = True
        var k = index // columns
        if k <= parts.ground.layers[column] + 1 + parts.ground.tolerance:
            bearing.append(index)
            base = min(base, k)
    if len(bearing) == 0:
        base = Int(part.low[2])
        for index in part.voxels:  # pragma: no branch
            if index // columns == base:
                bearing.append(index)
    var edge = grid.voxel.to(METER)
    var corners = List[Vec3d]()
    for index in bearing:  # pragma: no branch
        # Plan points: the feet can be in more than one layer.
        var low = grid.corner(index % grid.nx, (index // grid.nx) % grid.ny, 0)
        corners.append(low)
        corners.append(low + Vec3d(edge, 0, 0))
        corners.append(low + Vec3d(edge, edge, 0))
        corners.append(low + Vec3d(0, edge, 0))
    var hull = _plan_hull(corners^)
    var margin = Float64.MAX
    for at in range(len(hull)):  # pragma: no branch
        var a = hull[at]
        var b = hull[(at + 1) % len(hull)]
        var side = (b - a).length()
        margin = min(margin, _cross(a, b, mass.center) / side)
    var height = mass.center.z - grid.corner(0, 0, base).z
    var area = Float64(len(bearing)) * edge * edge
    return PartFooting(
        base,
        Area64(area, SQUARE_METER),
        Pressure64(mass.mass.to(KILOGRAM) * g / area, PASCAL),
        Length64(margin, METER),
        Angle64(atan2(margin, height), RADIAN),
    )


def _directions() -> List[Vec3d]:
    """Return the directions that a part's hull is taken along.

    Returns:
        Each of the 124 steps of -2 to 2 along x, y and z but none.
    """
    var out = List[Vec3d]()
    for a in range(-2, 3):  # pragma: no branch
        for b in range(-2, 3):  # pragma: no branch
            for c in range(-2, 3):  # pragma: no branch
                if a != 0 or b != 0 or c != 0:
                    out.append(Vec3d(Float64(a), Float64(b), Float64(c)))
    return out^


def part_hull(
    grid: OccupancyGrid, parts: ScanParts, label: Int
) raises -> List[Vec3d]:
    """Return the corners that a part's hull is made of.

    Along each of 124 directions, the voxel corner that reaches furthest
    is a corner of the convex hull. The hull of those corners holds every
    face of the part's box and of its 45 degree cuts, and it is a little
    inside the convex hull of every voxel.

    Args:
        grid: The grid.
        parts: Its parts.
        label: The part.

    Returns:
        The corners, each once, in building coordinates, in meters.

    Raises:
        Error: If there is no such part.
    """
    parts.check(label)
    ref part = parts.parts[label]
    var edge = grid.voxel.to(METER)
    var out = List[Vec3d]()
    for d in _directions():  # pragma: no branch
        # The corner of a voxel that reaches furthest along d.
        var offset = Vec3d(
            edge if d.x > 0 else 0,
            edge if d.y > 0 else 0,
            edge if d.z > 0 else 0,
        )
        var best = Vec3d(0, 0, 0)
        var reach = -Float64.MAX
        for index in part.voxels:  # pragma: no branch
            var i: Int
            var j: Int
            var k: Int
            i, j, k = _voxel(grid, index)
            var corner = grid.corner(i, j, k) + offset
            var along = corner.dot(d)
            if along > reach:
                reach = along
                best = corner
        var seen = False
        for point in out:
            if point == best:
                seen = True
        if not seen:
            out.append(best)
    return out^


def _hull_points(
    grid: OccupancyGrid, parts: ScanParts, label: Int, mass: PartMass
) raises -> List[Vector3]:
    """Return the corners of a part's hull, about its center of mass.

    Args:
        grid: The grid.
        parts: Its parts.
        label: The part.
        mass: The part's mass, from `part_mass`.

    Returns:
        The corners of `part_hull`, less the center of mass.

    Raises:
        Error: If there is no such part.
    """
    var points = List[Vector3]()
    for corner in part_hull(grid, parts, label):  # pragma: no branch
        points.append((corner - mass.center).vector3())
    return points^


def part_body(
    grid: OccupancyGrid,
    parts: ScanParts,
    label: Int,
    mass: PartMass,
    material: PhysicsMaterial,
) raises -> RigidBody:
    """Return a part as a dynamic rigid body, at rest where it stands.

    The body's origin is the part's center of mass. Its shape is the
    convex hull of `part_hull`, and its mass is the part's. Its center of
    mass and inertia are the hull's, as a solid of one density, which is
    what `extensions.physics` gives a convex shape.

    Args:
        grid: The grid.
        parts: Its parts.
        label: The part.
        mass: The part's mass, from `part_mass`.
        material: The friction and restitution of its surfaces.

    Returns:
        The body.

    Raises:
        Error: If there is no such part, the material is not valid, or
            `extensions.physics` refuses the hull or the mass.
    """
    material.check()
    var body = RigidBody(
        DYNAMIC,
        Shape.convex(_hull_points(grid, parts, label, mass)),
        Mass(Float32(mass.mass.to(KILOGRAM)), KILOGRAM),
        mass.center.vector3(),
        Quaternion.identity(),
    )
    body.material = material
    return body^


comptime BED_SLACK = 1e-4
"""How far into a voxel, as a share of its edge, a hull can reach and still
leave the voxel in a bed: more than the rounding of `Float32` corners."""


def part_bed(
    grid: OccupancyGrid, parts: ScanParts, label: Int, mass: PartMass
) raises -> OccupancyGrid:
    """Return the ground that a part's body stands on.

    The bed is the ground of `parts`, as `ground_grid` gives it, less each
    voxel that the hull of `part_body` overlaps. A convex body cannot hold
    the ground inside it. So it rests where its hull meets the ground, as
    in a pit cut to fit it. A voxel stays when a face of the hull, or the
    hull's box, parts them. A voxel that only an edge of the hull parts
    from it is taken out too.

    Args:
        grid: The grid.
        parts: Its parts.
        label: The part.
        mass: The part's mass, from `part_mass`. Its center places the
            hull.

    Returns:
        A grid like the one `ground_grid` gives, with each voxel that the
        hull overlaps empty.

    Raises:
        Error: If there is no such part, or `extensions.physics` refuses
            the hull.
    """
    var shape = Shape.convex(_hull_points(grid, parts, label, mass))
    ref hull = shape.polyhedron
    var bed = ground_grid(grid, parts.ground)
    var edge = grid.voxel.to(METER)
    var slack = edge * BED_SLACK
    var low = SIMD[DType.float64, 4](Float64.MAX)
    var high = SIMD[DType.float64, 4](-Float64.MAX)
    for v in hull.vertices:  # pragma: no branch
        var at = SIMD[DType.float64, 4](
            Float64(v.x), Float64(v.y), Float64(v.z), 0
        )
        low = min(low, at)
        high = max(high, at)
    # The fourth lane parts nothing.
    low[3] = -Float64.MAX
    high[3] = Float64.MAX
    for index in range(len(bed.weights)):  # pragma: no branch
        if bed.weights[index] == 0:
            continue
        var i: Int
        var j: Int
        var k: Int
        i, j, k = _voxel(grid, index)
        var c = grid.corner(i, j, k) - mass.center
        var a = SIMD[DType.float64, 4](c.x, c.y, c.z, 0)
        var apart = (
            a.ge(high - slack) | (a + edge).le(low + slack)
        ).reduce_or()
        var face = 0
        while not apart and face < hull.face_count():
            var n = hull.normals[face]
            # The least of n . x over the voxel's eight corners.
            var least = (
                Float64(n.x) * c.x
                + Float64(n.y) * c.y
                + Float64(n.z) * c.z
                + edge
                * (
                    min(Float64(n.x), 0)
                    + min(Float64(n.y), 0)
                    + min(Float64(n.z), 0)
                )
                - Float64(hull.offsets[face])
            )
            apart = least >= -slack
            face += 1
        if not apart:
            bed.weights[index] = 0
    return bed^


def part_splats(
    geometry: GaussianSplatGeometry,
    frame: ScanFrame,
    grid: OccupancyGrid,
    parts: ScanParts,
    label: Int,
    reach: Int,
) raises -> GaussianSplatGeometry:
    """Copy a part's splats out of a scan; see the module docstring.

    A splat is the part's when a voxel of the part is within `reach`
    voxels of the voxel that holds its center, along each axis. Its
    center, covariance, color and harmonics bytes are copied as they are.

    Args:
        geometry: The scan's splats.
        frame: The scan's frame, the one the grid was filled with.
        grid: The grid.
        parts: Its parts.
        label: The part.
        reach: How many voxels from its center a splat looks, 0 or more.

    Returns:
        The part's splats, in the scan's order and its coordinates.

    Raises:
        Error: If there is no such part, the reach is negative, the frame
            is refused, or no splat is the part's.
    """
    parts.check(label)
    if reach < 0:
        raise Error("Scan parts: a reach is 0 or more")
    var map = frame.map()
    var edge = grid.voxel.to(METER)
    var kept = List[Int]()
    ref c = geometry.centers
    for index in range(geometry.count()):
        var point = map.place(
            Vec3d(
                Float64(c[index * 3]),
                Float64(c[index * 3 + 1]),
                Float64(c[index * 3 + 2]),
            )
        )
        var at = (point - grid.origin) * (1 / edge)
        var i = Int(floor(at.x))
        var j = Int(floor(at.y))
        var k = Int(floor(at.z))
        var mine = False
        for dk in range(-reach, reach + 1):  # pragma: no branch
            for dj in range(-reach, reach + 1):  # pragma: no branch
                for di in range(-reach, reach + 1):  # pragma: no branch
                    if grid.contains(i + di, j + dj, k + dk) and (
                        parts.labels[grid.index(i + di, j + dj, k + dk)]
                        == label
                    ):
                        mine = True
        if mine:
            kept.append(index)
    if len(kept) == 0:
        raise Error("Scan parts: no splat is part " + String(label) + "'s")
    return splat_subset(geometry, kept)
