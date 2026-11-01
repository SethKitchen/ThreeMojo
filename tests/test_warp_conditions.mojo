# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the energy conditions of `extensions.warp.conditions`.

A perfect fluid with energy density ρ and pressure p, at rest for the
Eulerian observer, has closed-form values for each sampled direction.
With k = (1, n̂)/√2 and V = (1, s n̂)/√(1 + s²):

- Null: T_ab k^a k^b = (ρ + p) / 2.
- Weak: T_ab V^a V^b = (ρ + p s²) / (1 + s²).
- Strong: ((ρ + 3p) + s² (ρ - p)) / (2 (1 + s²)).
- Dominant: F = (ρ, -p n̂)/√2, so F·F = (p² - ρ²) / 2, and the value is
  √((ρ² - p²)/2) when ρ > abs(p), or -√((p² - ρ²)/2) when abs(p) > ρ.

See Hawking and Ellis, "The Large Scale Structure of Space-Time" (1973),
section 4.3.
"""

from std.math import acos, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from extensions.warp.conditions import (
    ConditionMap,
    energy_condition,
    energy_condition_samples,
    even_sphere_points,
    null_directions,
    timelike_directions,
)
from extensions.warp.frame import eulerian_transform
from extensions.warp.grid import SpacetimeGrid
from extensions.warp.kinds import (
    CONTRAVARIANT,
    COORDINATE_FRAME,
    DOMINANT_ENERGY,
    EULERIAN_FRAME,
    EnergyCondition,
    FOURTH_ORDER,
    NULL_ENERGY,
    STRONG_ENERGY,
    WEAK_ENERGY,
)
from extensions.warp.metrics import minkowski
from extensions.warp.solver import StressEnergy
from extensions.warp.tensor import (
    MINKOWSKI,
    Matrix4,
    Metric,
    TensorField,
    Vector4,
    inverse4,
)
from extensions.warp.three_plus_one import ThreePlusOne
from units.si import Duration64, Length64


def _grid() raises -> SpacetimeGrid:
    return SpacetimeGrid.uniform(1, 2, 2, 2, Duration64(1.0), Length64(1.0))


def _fluid(rho: Float64, p: Float64) raises -> StressEnergy:
    """A fluid in the Eulerian frame, with ρ and p at point 0 and the
    point index at every other point."""
    var grid = _grid()
    var t = TensorField(grid, CONTRAVARIANT, EULERIAN_FRAME)
    for point in range(grid.points()):
        var r = rho
        var q = p
        if point > 0:
            r = Float64(point)
            q = 0.0
        t.set_matrix(
            point, Matrix4(r, 0, 0, 0, 0, q, 0, 0, 0, 0, q, 0, 0, 0, 0, q)
        )
    return StressEnergy(t^, "fluid", FOURTH_ORDER)


def _tilted(grid: SpacetimeGrid) raises -> Metric:
    var parts = ThreePlusOne(grid)
    for point in range(grid.points()):
        parts.lapse[point] = 1.25
        parts.set_shift(0, point, 0.5)
        parts.set_shift(1, point, -0.25)
        parts.set_spatial(0, 0, point, 1.5)
        parts.set_spatial(0, 2, point, 0.25)
    return parts.metric("tilted")


def _norm(v: Vector4) -> Float64:
    return sqrt((v * v).reduce_add())


def test_sphere_points() raises:
    var points = even_sphere_points(2.0, 4)
    assert_equal(len(points), 4)
    var phi = acos(0.75)
    assert_almost_equal(points[0][1], 2.0 * sqrt(1.0 - 0.5625), atol=1e-15)
    assert_almost_equal(points[0][2], 0.0, atol=1e-15)
    assert_almost_equal(points[0][3], 2.0 * 0.75, atol=1e-15)
    assert_equal(points[0][0], 0.0)
    for i in range(4):
        assert_almost_equal(_norm(points[i]), 2.0, atol=1e-14)
    assert_true(phi > 0.0)
    with assert_raises(contains="at least one point"):
        _ = even_sphere_points(1.0, 0)
    with assert_raises(contains="radius must be finite"):
        _ = even_sphere_points(nan[DType.float64](), 3)


def test_directions() raises:
    var null = null_directions(10)
    assert_equal(len(null), 10)
    for i in range(10):
        var k = null[i]
        assert_almost_equal(_norm(k), 1.0, atol=1e-15)
        assert_almost_equal(k[0], sqrt(0.5), atol=1e-15)
        # Null for the Minkowski metric.
        assert_almost_equal(
            (MINKOWSKI[0] * k[0] * k[0])
            + k[1] * k[1]
            + k[2] * k[2]
            + k[3] * k[3],
            0.0,
            atol=1e-15,
        )
    var timelike = timelike_directions(5, 3)
    assert_equal(len(timelike), 15)
    # Shell 0 is null, shell 1 has half the speed, shell 2 is at rest.
    assert_almost_equal(timelike[0][0], sqrt(0.5), atol=1e-15)
    assert_almost_equal(timelike[5][0], 1.0 / sqrt(1.25), atol=1e-15)
    assert_equal(timelike[14][0], 1.0)
    assert_equal(timelike[14][3], 0.0)
    var one = timelike_directions(4, 1)
    assert_equal(len(one), 4)
    assert_equal(one[2][0], 1.0)
    with assert_raises(contains="at least one shell"):
        _ = timelike_directions(4, 0)
    with assert_raises(contains="at least one point"):
        _ = timelike_directions(0, 2)


def test_conditions_of_a_fluid() raises:
    var grid = _grid()
    var metric = minkowski(grid)
    var rho = 3.0
    var p = 0.5
    var energy = _fluid(rho, p)
    var null = energy_condition(energy, metric, NULL_ENERGY, 20)
    assert_almost_equal(null.at(0).value, (rho + p) / 2.0, atol=1e-14)
    var weak = energy_condition(energy, metric, WEAK_ENERGY, 20, 5)
    assert_almost_equal(weak.at(0).value, (rho + p) / 2.0, atol=1e-14)
    var strong = energy_condition(energy, metric, STRONG_ENERGY, 20, 5)
    assert_almost_equal(strong.at(0).value, (rho + p) / 2.0, atol=1e-14)
    var dominant = energy_condition(energy, metric, DOMINANT_ENERGY, 20)
    assert_almost_equal(
        dominant.at(0).value, sqrt((rho * rho - p * p) / 2.0), atol=1e-14
    )
    # Dust at point 1: ρ = 1, p = 0.
    assert_almost_equal(dominant.at(1).value, sqrt(0.5), atol=1e-14)
    assert_almost_equal(weak.at(1).value, 0.5, atol=1e-14)
    assert_equal(null.violations(), 0)
    assert_equal(dominant.condition, DOMINANT_ENERGY)


def test_conditions_of_exotic_matter() raises:
    var grid = _grid()
    var metric = minkowski(grid)
    # Negative energy density with a large tension.
    var rho = -1.0
    var p = -2.0
    var energy = _fluid(rho, p)
    var null = energy_condition(energy, metric, NULL_ENERGY, 8)
    assert_almost_equal(null.at(0).value, -1.5, atol=1e-14)
    var weak = energy_condition(energy, metric, WEAK_ENERGY, 8, 4)
    assert_almost_equal(weak.at(0).value, -1.5, atol=1e-14)
    # The strong value is least at rest: (ρ + 3p) / 2 = -3.5.
    var strong = energy_condition(energy, metric, STRONG_ENERGY, 8, 4)
    assert_almost_equal(strong.at(0).value, -3.5, atol=1e-14)
    var dominant = energy_condition(energy, metric, DOMINANT_ENERGY, 8)
    assert_almost_equal(dominant.at(0).value, -sqrt(1.5), atol=1e-14)
    assert_equal(null.violations(), 1)
    assert_almost_equal(null.worst().value, -1.5, atol=1e-14)
    var kept = null.violations_only()
    assert_almost_equal(kept.at(0).value, -1.5, atol=1e-14)
    assert_equal(kept.at(3).value, 0.0)
    assert_true(null.at(3).value > 0.0)
    # One point has no others to compare; no point has no worst value.
    var single = ConditionMap(NULL_ENERGY, [2.5])
    assert_equal(single.worst().value, 2.5)
    var none = ConditionMap(NULL_ENERGY, List[Float64]())
    assert_equal(none.violations(), 0)
    assert_equal(len(none.violations_only().values), 0)
    with assert_raises(contains="no worst value"):
        _ = none.worst()
    # A tension below the energy density leaves the weak condition intact
    # but breaks the null one only where ρ + p < 0.
    var mild = energy_condition(_fluid(2.0, -1.0), metric, WEAK_ENERGY, 8, 4)
    assert_almost_equal(mild.at(0).value, 0.5, atol=1e-14)


def test_coordinate_frame_uses_the_eulerian_observer() raises:
    var grid = _grid()
    var metric = _tilted(grid)
    var rho = 2.0
    var p = 0.75
    var fluid = TensorField(grid, CONTRAVARIANT, COORDINATE_FRAME)
    for point in range(grid.points()):
        var g = metric.at(point)
        var gu = inverse4(g)
        var n = eulerian_transform(g)
        var t = Matrix4(0)
        for a in range(4):
            for b in range(4):
                t[4 * a + b] = (rho + p) * n[4 * a] * n[4 * b] + p * gu[
                    4 * a + b
                ]
        fluid.set_matrix(point, t)
    var energy = StressEnergy(fluid^, "fluid", FOURTH_ORDER)
    var null = energy_condition(energy, metric, NULL_ENERGY, 12)
    assert_almost_equal(null.at(4).value, (rho + p) / 2.0, atol=1e-13)
    var dominant = energy_condition(energy, metric, DOMINANT_ENERGY, 12)
    assert_almost_equal(
        dominant.at(4).value, sqrt((rho * rho - p * p) / 2.0), atol=1e-13
    )


def test_samples() raises:
    var grid = _grid()
    var metric = minkowski(grid)
    var samples = energy_condition_samples(
        _fluid(-1.0, -2.0), metric, WEAK_ENERGY, 6, 3
    )
    assert_equal(samples.condition, WEAK_ENERGY)
    assert_equal(len(samples.directions), 18)
    assert_equal(len(samples.values), 18 * grid.points())
    # Shell 1 has s = 1/2: (ρ + p s²) / (1 + s²) = (-1 - 0.5) / 1.25.
    assert_almost_equal(samples.at(0, 7).value, -1.2, atol=1e-14)
    # Shell 2 is at rest: ρ.
    assert_almost_equal(samples.at(0, 17).value, -1.0, atol=1e-14)
    assert_almost_equal(samples.map[0], -1.5, atol=1e-14)
    var dominant = energy_condition_samples(
        _fluid(3.0, 0.0), metric, DOMINANT_ENERGY, 4
    )
    assert_equal(len(dominant.directions), 4)
    assert_almost_equal(dominant.at(0, 2).value, 3.0 * sqrt(0.5), atol=1e-14)
    var big = SpacetimeGrid.uniform(
        1, 16, 16, 16, Duration64(1.0), Length64(1.0)
    )
    var big_metric = minkowski(big)
    var empty = StressEnergy(
        TensorField(big, CONTRAVARIANT, EULERIAN_FRAME), "empty", FOURTH_ORDER
    )
    with assert_raises(contains="more than this port stores"):
        _ = energy_condition_samples(empty, big_metric, NULL_ENERGY, 4097)


def test_condition_refusals() raises:
    var grid = _grid()
    var metric = minkowski(grid)
    var energy = _fluid(1.0, 0.0)
    with assert_raises(contains="not valid"):
        _ = energy_condition(energy, metric, EnergyCondition(4))
    with assert_raises(contains="at least one point"):
        _ = energy_condition(energy, metric, NULL_ENERGY, 0)
    with assert_raises(contains="at least one shell"):
        _ = energy_condition(energy, metric, STRONG_ENERGY, 3, 0)
    var coordinate = StressEnergy(
        TensorField(grid, CONTRAVARIANT, COORDINATE_FRAME), "x", FOURTH_ORDER
    )
    var two_times = TensorField(grid, metric.tensor.index, COORDINATE_FRAME)
    for point in range(grid.points()):
        two_times.set_matrix(
            point, Matrix4(-1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
        )
    with assert_raises(contains="no Eulerian frame"):
        _ = energy_condition(coordinate, Metric(two_times^, "bad"), NULL_ENERGY)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
