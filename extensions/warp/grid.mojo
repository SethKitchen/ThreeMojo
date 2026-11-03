# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The uniform grid that a spacetime is sampled on.

A `SpacetimeGrid` has a number of points along t, x, y and z, a time step
and three space steps. WarpFactory calls these `gridSize` and
`gridScaling`. The points are stored with z changing fastest and t
slowest.

The time coordinate used in the derivatives is x⁰ = c t, so its step is
c times the time step. This is what WarpFactory does when it divides each
time derivative by c.

A `SpacetimeCenter` is WarpFactory's `worldCenter`: the place of the
coordinate origin. WarpFactory counts grid points from 1, and point i
sits at i times the step. This port counts from 0 and keeps the same
places, so point i sits at (i + 1) times the step, minus the center.
"""

from std.math import isfinite

from extensions.warp.kinds import (
    Axis,
    CARTESIAN,
    CYLINDRICAL,
    CoordinateSystem,
    SPHERICAL,
    T_AXIS,
    X_AXIS,
    Y_AXIS,
)
from extensions.warp.quantities import SPEED_OF_LIGHT
from units.si import Angle64, Duration64, Length64

comptime MAX_GRID_POINTS = 1048576
"""The most points a grid can hold. Each tensor stores 16 values a point, so
a tensor at this size takes 128 MiB."""


comptime _PI = 3.141592653589793


def _require_start(first: Float64, second: Float64) raises:
    """Raise unless two starts of a curvilinear grid are finite."""
    if not (isfinite(first) and isfinite(second)):
        raise Error("A grid's starts must be finite")


def _require_turn(count: Int, step: Float64) raises:
    """Raise if the azimuths cover more than one turn."""
    if Float64(count) * step > 2.0 * _PI * (1.0 + 1e-12):
        raise Error("A grid's azimuths must cover at most one turn")


def _require_step(value: Float64, name: String) raises:
    """Raise unless a grid step is positive and finite."""
    if not (isfinite(value) and value > 0.0):
        raise Error(String("The ", name, " step must be positive and finite"))


struct SpacetimeGrid(Equatable, ImplicitlyCopyable, Writable):
    """The number of points and the step along each coordinate."""

    var counts: SIMD[DType.int64, 4]
    """The number of points along t, x, y and z."""
    var steps: SIMD[DType.float64, 4]
    """The time step in seconds, then the steps of the three space axes,
    in meters or, for an angle, in radians."""
    var system: CoordinateSystem
    """What the space axes measure."""
    var starts: SIMD[DType.float64, 4]
    """The first coordinate along each space axis of a curvilinear grid.
    Zero for a Cartesian grid, which places its points by a center."""

    def __init__(
        out self,
        t_count: Int,
        x_count: Int,
        y_count: Int,
        z_count: Int,
        time_step: Duration64,
        x_step: Length64,
        y_step: Length64,
        z_step: Length64,
    ) raises:
        """Create a grid.

        Args:
            t_count: The number of time slices. 1 or more.
            x_count: The number of points along x. 1 or more.
            y_count: The number of points along y. 1 or more.
            z_count: The number of points along z. 1 or more.
            time_step: The time between two slices.
            x_step: The distance between two points along x.
            y_step: The distance between two points along y.
            z_step: The distance between two points along z.

        Raises:
            Error: If a count is less than 1, if the grid has more than
                `MAX_GRID_POINTS` points, or if a step is not positive
                and finite.
        """
        if t_count < 1 or x_count < 1 or y_count < 1 or z_count < 1:
            raise Error("A grid needs at least one point along each axis")
        # Each count is at most the limit, so no product below wraps.
        var limit = MAX_GRID_POINTS
        if (
            t_count > limit
            or x_count > limit // t_count
            or y_count > limit // (t_count * x_count)
            or z_count > limit // (t_count * x_count * y_count)
        ):
            raise Error("A grid is larger than this port stores")
        _require_step(time_step.value, "time")
        _require_step(x_step.value, "x")
        _require_step(y_step.value, "y")
        _require_step(z_step.value, "z")
        self.counts = SIMD[DType.int64, 4](
            Int64(t_count), Int64(x_count), Int64(y_count), Int64(z_count)
        )
        self.steps = SIMD[DType.float64, 4](
            time_step.value, x_step.value, y_step.value, z_step.value
        )
        self.system = CARTESIAN
        self.starts = SIMD[DType.float64, 4](0.0)

    @staticmethod
    def uniform(
        t_count: Int,
        x_count: Int,
        y_count: Int,
        z_count: Int,
        time_step: Duration64,
        step: Length64,
    ) raises -> SpacetimeGrid:
        """Return a grid with the same step along x, y and z.

        Args:
            t_count: The number of time slices.
            x_count: The number of points along x.
            y_count: The number of points along y.
            z_count: The number of points along z.
            time_step: The time between two slices.
            step: The distance between two points along each space axis.

        Returns:
            The grid.

        Raises:
            Error: For the same input as the constructor.
        """
        return SpacetimeGrid(
            t_count, x_count, y_count, z_count, time_step, step, step, step
        )

    @staticmethod
    def spherical(
        t_count: Int,
        r_count: Int,
        theta_count: Int,
        phi_count: Int,
        time_step: Duration64,
        r_start: Length64,
        r_step: Length64,
        theta_start: Angle64,
        theta_step: Angle64,
        phi_start: Angle64,
        phi_step: Angle64,
    ) raises -> SpacetimeGrid:
        """Return a grid in spherical coordinates t, r, θ and φ.

        Point i along an axis sits at the start plus i steps. The axes
        that `Axis` calls x, y and z are r, θ and φ. If the φ points cover
        the whole circle, the φ derivatives wrap around it.

        Args:
            t_count: The number of time slices.
            r_count: The number of radii.
            theta_count: The number of polar angles.
            phi_count: The number of azimuths.
            time_step: The time between two slices.
            r_start: The first radius. It must be positive: r = 0 is a
                coordinate singularity.
            r_step: The step in r.
            theta_start: The first polar angle, above 0.
            theta_step: The step in θ. The last angle must be below π.
            phi_start: The first azimuth.
            phi_step: The step in φ. The points can cover at most one
                turn.

        Returns:
            The grid.

        Raises:
            Error: For the input that the constructor refuses, or if a
                start is not finite, r or θ reaches a pole, or φ covers
                more than one turn.
        """
        var grid = SpacetimeGrid(
            t_count,
            r_count,
            theta_count,
            phi_count,
            time_step,
            r_step,
            Length64(theta_step.value),
            Length64(phi_step.value),
        )
        _require_start(r_start.value, phi_start.value)
        if not (r_start.value > 0.0):
            raise Error("A spherical grid must start at r > 0")
        var last = (
            theta_start.value + Float64(theta_count - 1) * theta_step.value
        )
        if not (theta_start.value > 0.0 and last < _PI):
            raise Error("A spherical grid's angles must be inside (0, pi)")
        _require_turn(phi_count, phi_step.value)
        grid.system = SPHERICAL
        grid.starts = SIMD[DType.float64, 4](
            0.0, r_start.value, theta_start.value, phi_start.value
        )
        return grid

    @staticmethod
    def cylindrical(
        t_count: Int,
        rho_count: Int,
        phi_count: Int,
        z_count: Int,
        time_step: Duration64,
        rho_start: Length64,
        rho_step: Length64,
        phi_start: Angle64,
        phi_step: Angle64,
        z_start: Length64,
        z_step: Length64,
    ) raises -> SpacetimeGrid:
        """Return a grid in cylindrical coordinates t, ρ, φ and z.

        Point i along an axis sits at the start plus i steps. The axes
        that `Axis` calls x, y and z are ρ, φ and z. If the φ points cover
        the whole circle, the φ derivatives wrap around it.

        Args:
            t_count: The number of time slices.
            rho_count: The number of distances from the axis.
            phi_count: The number of azimuths.
            z_count: The number of points along z.
            time_step: The time between two slices.
            rho_start: The first distance. It must be positive: ρ = 0 is
                a coordinate singularity.
            rho_step: The step in ρ.
            phi_start: The first azimuth.
            phi_step: The step in φ. The points can cover at most one
                turn.
            z_start: The first z.
            z_step: The step in z.

        Returns:
            The grid.

        Raises:
            Error: For the input that the constructor refuses, or if a
                start is not finite, ρ starts at the axis, or φ covers more
                than one turn.
        """
        var grid = SpacetimeGrid(
            t_count,
            rho_count,
            phi_count,
            z_count,
            time_step,
            rho_step,
            Length64(phi_step.value),
            z_step,
        )
        _require_start(rho_start.value, phi_start.value)
        _require_start(z_start.value, 0.0)
        if not (rho_start.value > 0.0):
            raise Error("A cylindrical grid must start at rho > 0")
        _require_turn(phi_count, phi_step.value)
        grid.system = CYLINDRICAL
        grid.starts = SIMD[DType.float64, 4](
            0.0, rho_start.value, phi_start.value, z_start.value
        )
        return grid

    def phi_axis(self) -> Int:
        """Return the axis that holds the azimuth φ.

        Returns:
            3 for spherical, 2 for cylindrical, or -1 for Cartesian.
        """
        if self.system == SPHERICAL:
            return 3
        if self.system == CYLINDRICAL:
            return 2
        return -1

    def periodic(self, axis: Int) -> Bool:
        """Return True if the derivatives along an axis wrap around.

        Args:
            axis: The axis, 0 to 3.

        Returns:
            Whether the axis is φ and its points cover one whole turn.
        """
        if axis != self.phi_axis():
            return False
        var span = Float64(self.counts[axis]) * self.steps[axis]
        return abs(span - 2.0 * _PI) <= 1e-12 * 2.0 * _PI

    def coordinate(self, axis: Axis, index: Int) -> Float64:
        """Return the coordinate of a point of a curvilinear grid.

        Args:
            axis: A space axis.
            index: The index along that axis, from 0.

        Returns:
            The start plus `index` steps, in meters or radians.
        """
        return self.starts[axis.value] + Float64(index) * self.steps[axis.value]

    def __eq__(self, other: Self) -> Bool:
        """Return True if both grids have the same counts and steps.

        Args:
            other: The other grid.

        Returns:
            Whether the grids are the same.
        """
        return (
            self.counts == other.counts
            and self.steps == other.steps
            and self.system == other.system
            and self.starts == other.starts
        )

    def write_to(self, mut writer: Some[Writer]):
        """Write the counts, as WarpFactory's `gridSize` reads.

        Args:
            writer: The destination.
        """
        writer.write(
            "[",
            self.counts[0],
            ", ",
            self.counts[1],
            ", ",
            self.counts[2],
            ", ",
            self.counts[3],
            "]",
        )

    def points(self) -> Int:
        """Return the number of points of the whole grid.

        Returns:
            The product of the four counts.
        """
        return Int(self.counts.reduce_mul())

    def count(self, axis: Axis) -> Int:
        """Return the number of points along one axis.

        Args:
            axis: A valid axis.

        Returns:
            The count.
        """
        return Int(self.counts[axis.value])

    def time_step(self) -> Duration64:
        """Return the time between two slices.

        Returns:
            The time step.
        """
        return Duration64(self.steps[0])

    def spacing(self, axis: Axis) -> Length64:
        """Return the distance between two points along a space axis.

        Args:
            axis: X_AXIS, Y_AXIS or Z_AXIS.

        Returns:
            The step.
        """
        return Length64(self.steps[axis.value])

    def stride(self, axis: Axis) -> Int:
        """Return how far apart two neighbors along one axis are stored.

        Args:
            axis: A valid axis.

        Returns:
            The distance between the flat indexes of the two points.
        """
        var total = 1
        for later in range(axis.value + 1, 4):
            total *= Int(self.counts[later])
        return total

    def coordinate_step(self, axis: Axis) -> Float64:
        """Return the step of one coordinate, in meters.

        The step of x⁰ = c t is c times the time step.

        Args:
            axis: A valid axis.

        Returns:
            The step.
        """
        if axis == T_AXIS:
            return SPEED_OF_LIGHT.value * self.steps[0]
        return self.steps[axis.value]

    def index(self, t: Int, x: Int, y: Int, z: Int) -> Int:
        """Return the flat index of one point. The indexes must be in range.

        Args:
            t: The time slice.
            x: The index along x.
            y: The index along y.
            z: The index along z.

        Returns:
            The flat index.
        """
        return ((t * Int(self.counts[1]) + x) * Int(self.counts[2]) + y) * Int(
            self.counts[3]
        ) + z

    def position(self, point: Int) -> SIMD[DType.int64, 4]:
        """Return the four indexes of a flat index. It must be in range.

        Args:
            point: The flat index.

        Returns:
            The indexes along t, x, y and z.
        """
        var out = SIMD[DType.int64, 4](0)
        var rest = point
        for axis in range(3, -1, -1):  # pragma: no branch
            var count = Int(self.counts[axis])
            out[axis] = Int64(rest % count)
            rest //= count
        return out

    def center(self) -> SpacetimeCenter:
        """Return the center that puts the origin in the middle of the grid.

        This is the `worldCenter = (gridSize + 1) / 2 .* gridScaling` of the
        WarpFactory examples.

        Returns:
            The center.
        """
        var half = (self.counts + 1).cast[DType.float64]() / 2.0 * self.steps
        return SpacetimeCenter(
            Duration64(half[0]),
            Length64(half[1]),
            Length64(half[2]),
            Length64(half[3]),
        )


@fieldwise_init
struct SpacetimeCenter(ImplicitlyCopyable, Movable):
    """Where the coordinate origin sits on the grid."""

    var time: Duration64
    """The time of the origin."""
    var x: Length64
    """The x of the origin."""
    var y: Length64
    """The y of the origin."""
    var z: Length64
    """The z of the origin."""

    def require_finite(self) raises:
        """Raise unless every part of the center is finite.

        Raises:
            Error: If a part is NaN or infinite.
        """
        if not (
            isfinite(self.time.value)
            and isfinite(self.x.value)
            and isfinite(self.y.value)
            and isfinite(self.z.value)
        ):
            raise Error("The grid center must be finite")


def grid_time(grid: SpacetimeGrid, center: SpacetimeCenter, t: Int) -> Float64:
    """Return the time of one slice from the origin, in seconds.

    Args:
        grid: The grid.
        center: The origin.
        t: The time slice, from 0.

    Returns:
        (t + 1) times the time step, minus the time of the center.
    """
    return Float64(t + 1) * grid.steps[0] - center.time.value


def grid_place(
    grid: SpacetimeGrid, center: SpacetimeCenter, axis: Axis, index: Int
) -> Float64:
    """Return the place of one point from the origin, in meters.

    Args:
        grid: The grid.
        center: The origin.
        axis: A space axis.
        index: The index along that axis, from 0.

    Returns:
        (index + 1) times the step, minus the center along the axis.
    """
    var origin = center.z.value
    if axis == X_AXIS:
        origin = center.x.value
    elif axis == Y_AXIS:
        origin = center.y.value
    return Float64(index + 1) * grid.steps[axis.value] - origin


def require_single_slice(grid: SpacetimeGrid, name: String) raises:
    """Raise unless a grid has one time slice.

    A comoving metric is static, so WarpFactory builds it on one slice.

    Args:
        grid: The grid.
        name: The name of the metric, for the message.

    Raises:
        Error: If the grid has more than one time slice.
    """
    if grid.counts[0] != 1:
        raise Error(String("The ", name, " metric needs one time slice"))


def require_cartesian(grid: SpacetimeGrid, name: String) raises:
    """Raise unless a grid uses Cartesian coordinates.

    Args:
        grid: The grid.
        name: What needs the coordinates, for the message.

    Raises:
        Error: If the grid is spherical or cylindrical.
    """
    if grid.system != CARTESIAN:
        raise Error(String(name, " needs a Cartesian grid"))
