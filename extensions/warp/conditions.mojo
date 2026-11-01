# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The pointwise energy conditions of a stress-energy tensor.

`energy_condition` is WarpFactory's `getEnergyConditions`. It moves the
tensor into the Eulerian frame, samples a set of observer directions at
each point, and keeps the most violating value. A negative value violates
the condition. Every value is an energy density.

| Condition | Directions | Value at a point |
|---|---|---|
| Null | null k | min T_ab k^a k^b |
| Weak | timelike V | min T_ab V^a V^b |
| Strong | timelike V | min (T_ab - T η_ab / 2) V^a V^b |
| Dominant | null k | -max s(F) √abs(F·F), F^a = -T^a_b k^b |

In the last row s is the sign, and F·F = η_ab F^a F^b. A spacelike F
gives a negative value.

The directions are WarpFactory's: `null_directions` puts (1, n̂) on n
even points of the unit sphere, and `timelike_directions` puts
(1, (1 - b) n̂) on shells with b from 0 to 1. Each direction is scaled to
a Euclidean length of 1. The points on the sphere follow the golden
angle.

## Differences from WarpFactory

WarpFactory lowers the Eulerian tensor with the metric of the coordinate
frame for the null and weak conditions, and with the Minkowski metric for
the strong and dominant ones. The Eulerian frame is orthonormal, and the
sampled directions are null or timelike for the Minkowski metric. So this
port uses the Minkowski metric for all four. Where g is not η, as in the
wall of a warp bubble, the null and weak values differ from WarpFactory's.
"""

from std.math import acos, cos, isfinite, sin, sqrt

from extensions.numerics.vector import MAX_VECTOR_ENTRIES
from extensions.warp.frame import to_eulerian
from extensions.warp.kinds import (
    DOMINANT_ENERGY,
    EnergyCondition,
    NULL_ENERGY,
    STRONG_ENERGY,
    WEAK_ENERGY,
)
from extensions.warp.quantities import EnergyDensity64
from extensions.warp.solver import StressEnergy, task_count
from render.tasks import TaskGroup
from extensions.warp.tensor import MINKOWSKI, Matrix4, Metric, Vector4

comptime _GOLDEN_RATIO = 1.618033988749895
comptime _TAU = 6.283185307179586


def even_sphere_points(radius: Float64, count: Int) raises -> List[Vector4]:
    """Return points spread evenly on a sphere, by the golden angle.

    This is WarpFactory's `getEvenPointsOnSphere`. Point i has the
    azimuth 2 π i / φ and the polar angle acos(1 - 2 (i + 1/2) / n).

    Args:
        radius: The radius of the sphere.
        count: The number of points. 1 or more.

    Returns:
        The points, in lanes 1 to 3. Lane 0 is zero.

    Raises:
        Error: If the count is less than 1 or the radius is not finite.
    """
    if count < 1:
        raise Error("A sphere needs at least one point")
    if not isfinite(radius):
        raise Error("A sphere radius must be finite")
    var out = List[Vector4](capacity=count)
    for i in range(count):  # pragma: no branch
        var theta = _TAU * Float64(i) / _GOLDEN_RATIO
        var phi = acos(1.0 - 2.0 * (Float64(i) + 0.5) / Float64(count))
        out.append(
            Vector4(
                0.0,
                radius * cos(theta) * sin(phi),
                radius * sin(theta) * sin(phi),
                radius * cos(phi),
            )
        )
    return out^


def _unit(v: Vector4) -> Vector4:
    """Return a vector scaled to a Euclidean length of 1."""
    return v / sqrt((v * v).reduce_add())


def null_directions(count: Int) raises -> List[Vector4]:
    """Return null directions (1, n̂) for even points n̂ of the sphere.

    This is WarpFactory's `generateUniformField` with "nulllike". Each
    direction is scaled to a Euclidean length of 1.

    Args:
        count: The number of directions. 1 or more.

    Returns:
        The directions, with the t component in lane 0.

    Raises:
        Error: If the count is less than 1.
    """
    var points = even_sphere_points(1.0, count)
    var out = List[Vector4](capacity=count)
    for i in range(count):  # pragma: no branch
        var v = points[i]
        v[0] = 1.0
        out.append(_unit(v))
    return out^


def timelike_directions(count: Int, shells: Int) raises -> List[Vector4]:
    """Return timelike directions on shells of decreasing speed.

    This is WarpFactory's `generateUniformField` with "timelike". Shell j
    of m has b = j / (m - 1), or b = 1 if m is 1, and its directions are
    (1, (1 - b) n̂). The first shell is null and the last is (1, 0, 0, 0).

    Args:
        count: The number of directions on each shell. 1 or more.
        shells: The number of shells. 1 or more.

    Returns:
        All shells, one after the other, with the t component in lane 0.

    Raises:
        Error: If a count is less than 1.
    """
    if shells < 1:
        raise Error("A field needs at least one shell")
    var out = List[Vector4](capacity=count * shells)
    for shell in range(shells):  # pragma: no branch
        var b = 1.0
        if shells > 1:
            b = Float64(shell) / Float64(shells - 1)
        var points = even_sphere_points(1.0 - b, count)
        for i in range(count):  # pragma: no branch
            var v = points[i]
            v[0] = 1.0
            out.append(_unit(v))
    return out^


def _directions(
    condition: EnergyCondition, count: Int, shells: Int
) raises -> List[Vector4]:
    """Return the directions that a condition samples."""
    if condition.uses_null_directions():
        return null_directions(count)
    return timelike_directions(count, shells)


def _quadratic(t: Matrix4, v: Vector4) -> Float64:
    """Return t_ab v^a v^b."""
    var total = 0.0
    for a in range(4):
        for b in range(4):
            total += t[4 * a + b] * v[a] * v[b]
    return total


def _flux_value(mixed: Matrix4, k: Vector4) -> Float64:
    """Return s(F) √abs(F·F) for F^a = -T^a_b k^b, with η."""
    var norm = 0.0
    for a in range(4):
        var f = 0.0
        for b in range(4):
            f -= mixed[4 * a + b] * k[b]
        norm += MINKOWSKI[5 * a] * f * f
    if norm < 0.0:
        return -sqrt(-norm)
    return sqrt(norm)


struct ConditionSamples(Copyable, Movable):
    """The value of a condition for each direction at each point."""

    var condition: EnergyCondition
    """The condition."""
    var directions: List[Vector4]
    """The sampled directions, in the Eulerian frame."""
    var values: List[Float64]
    """Direction d at point p is at p times the direction count, plus d,
    in joules per cubic meter."""
    var map: List[Float64]
    """The most violating value at each point, in joules per cubic
    meter."""

    def __init__(
        out self,
        condition: EnergyCondition,
        var directions: List[Vector4],
        var values: List[Float64],
        var map: List[Float64],
    ):
        """Hold the samples of a condition.

        Args:
            condition: The condition.
            directions: The sampled directions.
            values: The value for each direction at each point.
            map: The most violating value at each point.
        """
        self.condition = condition
        self.directions = directions^
        self.values = values^
        self.map = map^

    def at(self, point: Int, direction: Int) -> EnergyDensity64:
        """Return the value for one direction at one point.

        Args:
            point: The flat index of the point.
            direction: The index of the direction.

        Returns:
            The value. A negative value violates the condition.
        """
        return EnergyDensity64(
            self.values[point * len(self.directions) + direction]
        )


struct ConditionMap(Copyable, Movable):
    """The most violating value of a condition at each point."""

    var condition: EnergyCondition
    """The condition."""
    var values: List[Float64]
    """One value for each point, in joules per cubic meter."""

    def __init__(
        out self, condition: EnergyCondition, var values: List[Float64]
    ):
        """Hold the map of a condition.

        Args:
            condition: The condition.
            values: One value for each point.
        """
        self.condition = condition
        self.values = values^

    def at(self, point: Int) -> EnergyDensity64:
        """Return the value at one point.

        Args:
            point: The flat index of the point.

        Returns:
            The value. A negative value violates the condition.
        """
        return EnergyDensity64(self.values[point])

    def worst(self) raises -> EnergyDensity64:
        """Return the most negative value of the map.

        Returns:
            The least value over every point.

        Raises:
            Error: If the map has no values.
        """
        if len(self.values) == 0:
            raise Error("An empty map has no worst value")
        var out = self.values[0]
        for point in range(1, len(self.values)):
            out = min(out, self.values[point])
        return EnergyDensity64(out)

    def violations(self) -> Int:
        """Return the number of points where the condition is violated.

        Returns:
            The number of negative values.
        """
        var out = 0
        for point in range(len(self.values)):
            if self.values[point] < 0.0:
                out += 1
        return out

    def violations_only(self) -> ConditionMap:
        """Return the map with every positive value set to zero.

        This is what WarpFactory's `evalMetric` returns when its
        `keepPositive` flag is 0.

        Returns:
            The map, with only its violations kept.
        """
        var values = self.values.copy()
        for point in range(len(values)):
            values[point] = min(values[point], 0.0)
        return ConditionMap(self.condition, values^)


__async def _evaluate_chunk(
    eulerian: Pointer[StressEnergy, MutAnyOrigin],
    directions: Pointer[List[Vector4], MutAnyOrigin],
    map: MutPointer[Float64, MutAnyOrigin],
    values: MutPointer[Float64, MutAnyOrigin],
    condition: EnergyCondition,
    keep_samples: Bool,
    first: Int,
    past: Int,
):
    """Evaluate a condition at the points from `first` to `past`."""
    var per_point = len(directions[])
    var dominant = condition == DOMINANT_ENERGY
    var strong = condition == STRONG_ENERGY
    for point in range(first, past):
        var upper = eulerian[].tensor.matrix(point)
        # T_ab = η_ac T^cd η_db: η is diagonal, so each entry changes sign
        # once for each index that is 0.
        var lower = upper * Matrix4(
            1, -1, -1, -1, -1, 1, 1, 1, -1, 1, 1, 1, -1, 1, 1, 1
        )
        if strong:
            var trace = (MINKOWSKI * lower).reduce_add()
            lower = lower - 0.5 * trace * MINKOWSKI
        # T^a_b = T^ac η_cb: column b of T^ab times η_bb.
        var mixed = upper * Matrix4(
            -1, 1, 1, 1, -1, 1, 1, 1, -1, 1, 1, 1, -1, 1, 1, 1
        )
        var best = 0.0
        for d in range(per_point):  # pragma: no branch
            var value: Float64
            if dominant:
                value = -_flux_value(mixed, directions[][d])
            else:
                value = _quadratic(lower, directions[][d])
            if keep_samples:
                values[unsafe_offset=point * per_point + d] = value
            if d == 0 or value < best:
                best = value
        map[unsafe_offset=point] = best


def _evaluate(
    energy: StressEnergy,
    metric: Metric,
    condition: EnergyCondition,
    count: Int,
    shells: Int,
    keep_samples: Bool,
    threads: Int,
) raises -> ConditionSamples:
    """Evaluate a condition, and keep every sample if asked."""
    if not condition.is_valid():
        raise Error("An energy condition is not valid")
    var directions = _directions(condition, count, shells)
    var grid = metric.grid()
    var n = grid.points()
    var per_point = len(directions)
    if keep_samples and per_point > MAX_VECTOR_ENTRIES // n:
        raise Error("The samples are more than this port stores")
    var tasks = task_count(threads, n)
    var eulerian = to_eulerian(energy, metric)
    var map = List[Float64](length=n, fill=0.0)
    var values = List[Float64]()
    if keep_samples:
        values = List[Float64](length=n * per_point, fill=0.0)
    var group = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        group.create_task(
            _evaluate_chunk(
                Pointer(to=eulerian).unsafe_origin_cast[MutAnyOrigin](),
                Pointer(to=directions).unsafe_origin_cast[MutAnyOrigin](),
                map.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                values.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                condition,
                keep_samples,
                task * n // tasks,
                (task + 1) * n // tasks,
            )
        )
    group.wait()
    _ = len(map)
    _ = len(values)
    _ = len(eulerian.tensor.data)
    return ConditionSamples(condition, directions^, values^, map^)


def energy_condition(
    energy: StressEnergy,
    metric: Metric,
    condition: EnergyCondition,
    count: Int = 100,
    shells: Int = 10,
    threads: Int = 0,
) raises -> ConditionMap:
    """Return the most violating value of an energy condition at each point.

    This is WarpFactory's `getEnergyConditions` with `returnVec` 0.

    Args:
        energy: The stress-energy tensor, in any frame and index position.
        metric: The metric. It must have the same grid.
        condition: The condition.
        count: The number of directions on the sphere.
        shells: The number of timelike shells, for the weak and strong
            conditions.
        threads: The tasks to use. 0 means one for each logical core.

    Returns:
        The map. A negative value violates the condition.

    Raises:
        Error: If the condition is not valid, a count is less than 1,
            `threads` is negative, the grids differ, or the metric has no
            Eulerian frame at a point.
    """
    var samples = _evaluate(
        energy, metric, condition, count, shells, False, threads
    )
    return ConditionMap(condition, samples.map.copy())


def energy_condition_samples(
    energy: StressEnergy,
    metric: Metric,
    condition: EnergyCondition,
    count: Int = 100,
    shells: Int = 10,
    threads: Int = 0,
) raises -> ConditionSamples:
    """Return an energy condition for every sampled direction at each point.

    This is WarpFactory's `getEnergyConditions` with `returnVec` 1.

    Args:
        energy: The stress-energy tensor, in any frame and index position.
        metric: The metric. It must have the same grid.
        condition: The condition.
        count: The number of directions on the sphere.
        shells: The number of timelike shells, for the weak and strong
            conditions.
        threads: The tasks to use. 0 means one for each logical core.

    Returns:
        The samples, the directions and the map.

    Raises:
        Error: For the same input as `energy_condition`, or if the
            samples are more than 16777216 values.
    """
    return _evaluate(energy, metric, condition, count, shells, True, threads)
