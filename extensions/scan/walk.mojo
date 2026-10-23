# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A person who walks through a scan, as a game's player does.

`Walker` is a physics world that holds the scan as a static collider and a
capsule for the walker, which cannot turn over. A step of the world is one
tick of a game loop. The walker turns toward its goal at a limited rate,
walks the way it faces at a steady speed, and the floor, the walls and the
furniture of the scan decide the rest. The camera of the game stands at
`eye` and looks along `forward`.

The goal is one of two points of the floor. They are the two clear points
that are farthest apart with a clear line between them, found from the
scan's occupancy grid in four steps.

1. A plan point is clear when no solid voxel is within the walker's radius,
   from the step height to the standing height over the floor, and the floor
   is under it.
2. The clear points are tried on a lattice, `spacing` apart.
3. The first end is the clear point nearest the middle of the clear points.
4. The second is the clear point farthest from the first with a clear line
   of walking to it, and then the first moves to the point farthest from the
   second in the same way.

The walker walks to one end and then back, and turns round at each.
"""

from extensions.physics.body import (
    BodyId,
    DYNAMIC,
    RigidBody,
    locked_inverse_inertia,
)
from extensions.physics.shape import PhysicsMaterial, Shape
from extensions.physics.world import PhysicsWorld
from extensions.scan.colliders import add_scan_collider
from extensions.scan.occupancy import OccupancyGrid
from generators.utils import Vec3d
from math.finite import require_finite, require_positive_finite
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import atan2, ceil, cos, floor, pi, sin, sqrt
from units.si import (
    Angle64,
    Duration,
    KILOGRAM,
    Length,
    Length64,
    Mass,
    METER,
    METER_PER_SECOND,
    RADIAN,
    SECOND,
    Velocity64,
)

comptime WALK_TURN_LIMIT = 0.6
"""The walker stops and turns where its way is more than this many radians
from the goal."""


@fieldwise_init
struct WalkOptions(ImplicitlyCopyable):
    """The walker's size, its pace and what the path may pass."""

    var radius: Length64
    """The capsule's radius."""
    var height: Length64
    """The walker's height, feet to crown. At least twice the radius."""
    var eye: Length64
    """The eye's height over the capsule's center. It must be less than half
    the height, so that the eye is inside the capsule."""
    var speed: Velocity64
    """The walking pace."""
    var turn: Angle64
    """The most the walker turns in one second."""
    var step: Length64
    """The height of the lowest voxel that stops the walker: a lower one
    is a step it climbs."""
    var clearance: Length64
    """The height over the floor that the walker needs clear."""
    var spacing: Length64
    """The distance between the points tried for the ends of the path."""
    var mass: Mass
    """The walker's mass."""

    def check(self) raises:
        """Refuse options that cannot make a walker.

        Raises:
            Error: If a number is not positive and finite, the height is
                less than twice the radius, the eye is not inside the
                capsule, or the clearance is not above the step.
        """
        require_positive_finite(
            self.radius.to(METER), "Scan walk: the radius must be positive"
        )
        require_positive_finite(
            self.height.to(METER), "Scan walk: the height must be positive"
        )
        require_positive_finite(
            self.speed.to(METER_PER_SECOND),
            "Scan walk: the speed must be positive",
        )
        require_positive_finite(
            self.turn.to(RADIAN), "Scan walk: the turn must be positive"
        )
        require_positive_finite(
            self.step.to(METER), "Scan walk: the step must be positive"
        )
        require_positive_finite(
            self.spacing.to(METER), "Scan walk: the spacing must be positive"
        )
        require_finite(self.eye.to(METER), "Scan walk: the eye must be finite")
        require_positive_finite(
            Float64(self.mass.to(KILOGRAM)),
            "Scan walk: the mass must be positive",
        )
        if self.height.to(METER) < 2 * self.radius.to(METER):
            raise Error("Scan walk: the height is at least twice the radius")
        if abs(self.eye.to(METER)) >= self.height.to(METER) / 2:
            raise Error("Scan walk: the eye must be inside the capsule")
        if self.clearance.to(METER) <= self.step.to(METER):
            raise Error("Scan walk: the clearance must be above the step")


def default_walk_options() -> WalkOptions:
    """Return the options of an adult.

    Returns:
        A radius of 0.3 m, a height of 1.8 m, an eye 0.75 m above the
        capsule's center, a pace of 1.4 m/s, a turn of 2.5 radians a second,
        a step of 0.25 m, a clearance of 1.7 m, a spacing of 0.5 m and a mass
        of 80 kg.
    """
    return WalkOptions(
        Length64(0.3, METER),
        Length64(1.8, METER),
        Length64(0.75, METER),
        Velocity64(1.4, METER_PER_SECOND),
        Angle64(2.5, RADIAN),
        Length64(0.25, METER),
        Length64(1.7, METER),
        Length64(0.5, METER),
        Mass(80, KILOGRAM),
    )


def is_clear(
    grid: OccupancyGrid,
    options: WalkOptions,
    x: Length64,
    y: Length64,
    floor_z: Length64,
) -> Bool:
    """Return whether a walker can stand at a plan point.

    Args:
        grid: The scan's grid.
        options: The walker.
        x: East.
        y: North.
        floor_z: The floor's elevation.

    Returns:
        True if no voxel is solid within the walker's radius, from the step
        height to the clearance over the floor, and the floor is under the
        point.
    """
    var edge = grid.voxel.to(METER)
    var floor_m = floor_z.to(METER)
    var radius = options.radius.to(METER)
    var ci = Int(floor((x.to(METER) - grid.origin.x) / edge))
    var cj = Int(floor((y.to(METER) - grid.origin.y) / edge))
    var low = Int(
        floor((floor_m + options.step.to(METER) - grid.origin.z) / edge)
    )
    var high = Int(
        floor((floor_m + options.clearance.to(METER) - grid.origin.z) / edge)
    )
    var reach = Int(ceil(radius / edge))
    for dj in range(-reach, reach + 1):
        for di in range(-reach, reach + 1):
            if Float64(di * di + dj * dj) * edge * edge > radius * radius:
                continue
            for k in range(low, high + 1):
                if grid.is_solid(ci + di, cj + dj, k):
                    return False
    var below = Int(floor((floor_m - 0.5 * edge - grid.origin.z) / edge))
    return grid.is_solid(ci, cj, below) or grid.is_solid(ci, cj, below - 1)


def is_walkable(
    grid: OccupancyGrid,
    options: WalkOptions,
    from_x: Length64,
    from_y: Length64,
    to_x: Length64,
    to_y: Length64,
    floor_z: Length64,
) -> Bool:
    """Return whether the walker can walk the straight line between two
    plan points.

    Args:
        grid: The scan's grid.
        options: The walker.
        from_x: East of the start.
        from_y: North of the start.
        to_x: East of the end.
        to_y: North of the end.
        floor_z: The floor's elevation.

    Returns:
        Whether every point of the line, a tenth of a meter apart, is clear.
    """
    var ax = from_x.to(METER)
    var ay = from_y.to(METER)
    var dx = to_x.to(METER) - ax
    var dy = to_y.to(METER) - ay
    var steps = Int(sqrt(dx * dx + dy * dy) / 0.1) + 1
    for step in range(steps + 1):
        var t = Float64(step) / Float64(steps)
        if not is_clear(
            grid,
            options,
            Length64(ax + dx * t, METER),
            Length64(ay + dy * t, METER),
            floor_z,
        ):
            return False
    return True


def _farthest(
    grid: OccupancyGrid,
    options: WalkOptions,
    points: List[Vec3d],
    around: Vec3d,
    floor_z: Length64,
) -> Int:
    """Return the clear point farthest from a place that can be walked to
    in a straight line.

    Args:
        grid: The scan's grid.
        options: The walker.
        points: The clear points; z is not used.
        around: The place.
        floor_z: The floor's elevation.

    Returns:
        The index of the point. A place that is one of the points can be
        walked to from itself, so a point is always found.
    """
    var best = 0
    var best_length = Float64(-1)
    for index in range(len(points)):
        var dx = points[index].x - around.x
        var dy = points[index].y - around.y
        var length = dx * dx + dy * dy
        if length > best_length and is_walkable(
            grid,
            options,
            Length64(around.x, METER),
            Length64(around.y, METER),
            Length64(points[index].x, METER),
            Length64(points[index].y, METER),
            floor_z,
        ):
            best = index
            best_length = length
    return best


def walk_ends(
    grid: OccupancyGrid,
    options: WalkOptions,
    low: Vec3d,
    high: Vec3d,
    floor_z: Length64,
) raises -> List[Vec3d]:
    """Return the two ends of a walk across a scan's floor; see the module
    docstring.

    Args:
        grid: The scan's grid.
        options: The walker.
        low: The least x and y of the box to search, in meters.
        high: The most x and y.
        floor_z: The floor's elevation.

    Returns:
        Two plan points, x and y in meters, with z zero.

    Raises:
        Error: If the options are refused, or fewer than two points of the
            floor are clear.
    """
    options.check()
    var edge = options.spacing.to(METER)
    var points = List[Vec3d]()
    var y = low.y
    while y <= high.y:
        var x = low.x
        while x <= high.x:
            if is_clear(
                grid, options, Length64(x, METER), Length64(y, METER), floor_z
            ):
                points.append(Vec3d(x, y, 0))
            x += edge
        y += edge
    if len(points) < 2:
        raise Error("Scan walk: the scan has no clear floor to walk on")
    var mean = Vec3d(0, 0, 0)
    for point in points:
        mean = mean + point
    mean = mean * (1 / Float64(len(points)))
    var first = 0
    var nearest = Float64(1e300)
    for index in range(len(points)):
        var dx = points[index].x - mean.x
        var dy = points[index].y - mean.y
        if dx * dx + dy * dy < nearest:
            nearest = dx * dx + dy * dy
            first = index
    var a = _farthest(grid, options, points, points[first], floor_z)
    var b = _farthest(grid, options, points, points[a], floor_z)
    return [points[a], points[b]]


struct Walker(Movable):
    """A capsule that walks a scan's floor, in a physics world; see the
    module docstring."""

    var world: PhysicsWorld
    """The world: the scan's collider, and the walker."""
    var body: BodyId
    """The walker's body."""
    var options: WalkOptions
    """The walker."""
    var ends: List[Vec3d]
    """The two ends of the walk, x and y in meters."""
    var goal: Int
    """Which end the walker walks to, 0 or 1."""
    var yaw: Float64
    """The way the walker faces, in radians from +x toward +y."""

    def __init__(
        out self,
        grid: OccupancyGrid,
        floor_z: Length64,
        low: Vec3d,
        high: Vec3d,
        options: WalkOptions,
        material: PhysicsMaterial,
    ) raises:
        """Stand a walker on a scan's floor.

        Args:
            grid: The scan's grid, which becomes the static collider.
            floor_z: The floor's elevation.
            low: The least x and y of the box the ends are searched in.
            high: The most x and y.
            options: The walker.
            material: The friction and restitution of the scan.

        Raises:
            Error: Everything `walk_ends` and `add_scan_collider` raise, or
                the walker's shape or body is refused.
        """
        self.ends = walk_ends(grid, options, low, high, floor_z)
        self.world = PhysicsWorld()
        _ = add_scan_collider(self.world, grid, material)
        var half = options.height.to(METER) / 2 - options.radius.to(METER)
        var body = RigidBody(
            DYNAMIC,
            Shape.capsule(
                Length(Float32(options.radius.to(METER)), METER),
                Length(Float32(half), METER),
            ),
            options.mass,
            Vector3(
                Float32(self.ends[0].x),
                Float32(self.ends[0].y),
                Float32(
                    floor_z.to(METER) + half + options.radius.to(METER) + 0.05
                ),
            ),
            Quaternion.identity(),
        )
        body.set_inverse_inertia(locked_inverse_inertia())
        self.body = self.world.add_body(body^)
        self.options = options
        self.goal = 1
        self.yaw = atan2(
            self.ends[1].y - self.ends[0].y, self.ends[1].x - self.ends[0].x
        )

    def position(self) -> Vec3d:
        """Return where the walker's center is.

        Returns:
            Meters east, north and up.
        """
        var at = self.world.bodies[self.body.value].position
        return Vec3d(Float64(at.x), Float64(at.y), Float64(at.z))

    def eye(self) -> Vec3d:
        """Return where the walker's eye is, for a camera.

        Returns:
            Meters east, north and up.
        """
        var at = self.position()
        return Vec3d(at.x, at.y, at.z + self.options.eye.to(METER))

    def forward(self) -> Vec3d:
        """Return the way the walker faces.

        Returns:
            A unit vector in the plan, east, north and zero.
        """
        return Vec3d(cos(self.yaw), sin(self.yaw), 0)

    def step(mut self, dt: Duration) raises:
        """Advance one tick: steer toward the goal, then step the world.

        Args:
            dt: The tick, more than zero and finite.

        Raises:
            Error: If the tick is not valid.
        """
        var seconds = Float64(dt.to(SECOND))
        var here = self.position()
        var dx = self.ends[self.goal].x - here.x
        var dy = self.ends[self.goal].y - here.y
        if dx * dx + dy * dy < 0.09:
            self.goal = 1 - self.goal
            dx = self.ends[self.goal].x - here.x
            dy = self.ends[self.goal].y - here.y
        var turn = atan2(dy, dx) - self.yaw
        while turn > pi:
            turn -= 2 * pi
        while turn < -pi:
            turn += 2 * pi
        var limit = self.options.turn.to(RADIAN) * seconds
        self.yaw += max(-limit, min(limit, turn))
        var pace = self.options.speed.to(METER_PER_SECOND)
        if abs(turn) >= WALK_TURN_LIMIT:
            pace = 0
        ref body = self.world.bodies[self.body.value]
        body.linear_velocity.x = Float32(pace * cos(self.yaw))
        body.linear_velocity.y = Float32(pace * sin(self.yaw))
        self.world.step(dt)
