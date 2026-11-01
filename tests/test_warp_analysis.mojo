# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the scalars, flow lines, evaluation and plots of
`extensions.warp`.

For the Alcubierre metric with shift βˣ = β (1 - f), the space
derivatives of the shift are Dᵢ = -β f'(r) xᵢ / r. Then the expansion is
θ = -Dₓ, the shear scalar is Dₓ²/3 + (D_y² + D_z²)/4, and the vorticity
is zero. See Alcubierre, Classical and Quantum Gravity 11 (1994) L73,
equation 12, for the expansion.
"""

from std.math import cosh, inf, nan, sqrt, tanh
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from extensions.warp.evaluation import evaluate_metric
from extensions.warp.flow import GridPoint, momentum_flow_lines, trilinear
from extensions.warp.grid import SpacetimeCenter, SpacetimeGrid
from extensions.warp.kinds import (
    Axis,
    CONTRAVARIANT,
    COORDINATE_FRAME,
    COVARIANT,
    FOURTH_ORDER,
    T_AXIS,
    X_AXIS,
    Y_AXIS,
    Z_AXIS,
)
from extensions.warp.metrics import alcubierre_comoving, minkowski
from extensions.warp.plot import (
    PlaneSlice,
    draw_plane,
    red_blue,
    slice_plane,
)
from extensions.warp.quantities import Compliance64, fraction_of_light
from extensions.warp.scalars import metric_scalars
from extensions.warp.solver import StressEnergy
from extensions.warp.tensor import MINKOWSKI, Metric, TensorField
from render.framebuffer import Color
from units.si import Duration64, InverseLength64, Length64

comptime RADIUS = 2.0
comptime SIGMA = 1.5
comptime BETA = 0.5


def _bubble(h: Float64, x: Float64, y: Float64, z: Float64) raises -> Metric:
    """An Alcubierre bubble on a 5 by 5 by 5 grid whose middle point is at
    (x, y, z)."""
    var grid = SpacetimeGrid.uniform(1, 5, 5, 5, Duration64(1.0), Length64(h))
    var center = SpacetimeCenter(
        Duration64(0.0),
        Length64(3.0 * h - x),
        Length64(3.0 * h - y),
        Length64(3.0 * h - z),
    )
    return alcubierre_comoving(
        grid,
        center,
        fraction_of_light(BETA),
        Length64(RADIUS),
        InverseLength64(SIGMA),
    )


def _shape_slope(r: Float64) -> Float64:
    return (
        SIGMA
        * (
            1.0 / cosh(SIGMA * (RADIUS + r)) ** 2
            - 1.0 / cosh(SIGMA * (RADIUS - r)) ** 2
        )
        / (2.0 * tanh(SIGMA * RADIUS))
    )


def test_alcubierre_scalars() raises:
    var x = 0.9
    var y = -0.6
    var z = 0.4
    var r = sqrt(x * x + y * y + z * z)
    var slope = _shape_slope(r)
    var dx = -BETA * slope * x / r
    var dy = -BETA * slope * y / r
    var dz = -BETA * slope * z / r
    var metric = _bubble(0.05, x, y, z)
    var scalars = metric_scalars(metric)
    var point = metric.grid().index(0, 2, 2, 2)
    var theta = scalars.expansion_at(point).value
    assert_almost_equal(theta, -dx, atol=1e-5 * abs(dx))
    var shear = dx * dx / 3.0 + (dy * dy + dz * dz) / 4.0
    assert_almost_equal(scalars.shear_at(point).value, shear, atol=1e-5 * shear)
    assert_true(abs(scalars.vorticity_at(point).value) < 1e-12 * shear)
    # The bubble contracts in front and expands behind.
    assert_true(theta < 0.0)
    var behind = metric_scalars(_bubble(0.05, -x, y, z))
    assert_true(behind.expansion_at(point).value > 0.0)


def test_flat_scalars() raises:
    var grid = SpacetimeGrid.uniform(1, 5, 5, 5, Duration64(1.0), Length64(1.0))
    var scalars = metric_scalars(minkowski(grid))
    for point in range(grid.points()):
        assert_equal(scalars.expansion[point], 0.0)
        assert_equal(scalars.shear[point], 0.0)
        assert_equal(scalars.vorticity[point], 0.0)
    var identity = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    for point in range(grid.points()):
        identity.set_matrix(point, MINKOWSKI * MINKOWSKI)
    with assert_raises(contains="no real lapse"):
        _ = metric_scalars(Metric(identity^, "no lapse"))


def _flow_tensor(grid: SpacetimeGrid) raises -> StressEnergy:
    """T^0x = 1, T^0y = x + 2 y + 3 z in grid indexes, T^0z = 0."""
    var t = TensorField(grid, CONTRAVARIANT, COORDINATE_FRAME)
    for point in range(grid.points()):
        var at = grid.position(point)
        t.set_symmetric(0, 1, point, 1.0)
        t.set_symmetric(
            0,
            2,
            point,
            Float64(at[1]) + 2.0 * Float64(at[2]) + 3.0 * Float64(at[3]),
        )
    return StressEnergy(t^, "flow", FOURTH_ORDER)


def test_trilinear() raises:
    var grid = SpacetimeGrid.uniform(1, 6, 6, 6, Duration64(1.0), Length64(1.0))
    var energy = _flow_tensor(grid)
    var place = GridPoint(1.25, 2.5, 3.75)
    assert_almost_equal(
        trilinear(energy.tensor, 0, 2, place), 1.25 + 5.0 + 11.25, atol=1e-13
    )
    assert_almost_equal(trilinear(energy.tensor, 0, 1, place), 1.0, atol=1e-15)
    assert_equal(trilinear(energy.tensor, 0, 2, GridPoint(2.0, 3.0, 1.0)), 11.0)


def test_flow_lines() raises:
    var grid = SpacetimeGrid.uniform(1, 6, 6, 6, Duration64(1.0), Length64(1.0))
    var energy = _flow_tensor(grid)
    var flat = TensorField(grid, CONTRAVARIANT, COORDINATE_FRAME)
    for point in range(grid.points()):
        flat.set_symmetric(0, 1, point, 1.0)
    var along = StressEnergy(flat^, "along", FOURTH_ORDER)
    var starts: List[GridPoint] = [
        GridPoint(1.5, 2.0, 2.0),
        GridPoint(0.5, 2.0, 2.0),
        GridPoint(2.0, 0.5, 2.0),
        GridPoint(2.0, 2.0, 4.5),
        GridPoint(nan[DType.float64](), 2.0, 2.0),
    ]
    var lines = momentum_flow_lines(along, starts, Compliance64(0.5), 100)
    assert_equal(len(lines), 5)
    # 1.5, 2.0, ..., 4.0: the next place, 4.5, is within one point of the
    # edge.
    assert_equal(len(lines[0]), 6)
    assert_equal(lines[0][0], GridPoint(1.5, 2.0, 2.0))
    assert_equal(lines[0][5], GridPoint(4.0, 2.0, 2.0))
    for i in range(1, 5):
        assert_equal(len(lines[i]), 0)
    assert_equal(
        len(
            momentum_flow_lines(along, List[GridPoint](), Compliance64(0.5), 3)
        ),
        0,
    )
    var short = momentum_flow_lines(along, starts, Compliance64(0.5), 3)
    assert_equal(len(short[0]), 3)
    var curved = momentum_flow_lines(
        energy, [GridPoint(1.5, 1.5, 1.5)], Compliance64(0.01), 4
    )
    assert_equal(len(curved[0]), 4)
    assert_almost_equal(
        curved[0][1].y, 1.5 + 0.01 * (1.5 + 3.0 + 4.5), atol=1e-14
    )
    assert_almost_equal(curved[0][1].x, 1.51, atol=1e-14)


def test_flow_refusals() raises:
    var grid = SpacetimeGrid.uniform(1, 6, 6, 6, Duration64(1.0), Length64(1.0))
    var start: List[GridPoint] = [GridPoint(2.0, 2.0, 2.0)]
    var lowered = StressEnergy(
        TensorField(grid, COVARIANT, COORDINATE_FRAME), "x", FOURTH_ORDER
    )
    with assert_raises(contains="contravariant"):
        _ = momentum_flow_lines(lowered, start, Compliance64(1.0), 5)
    var moving = SpacetimeGrid.uniform(
        2, 6, 6, 6, Duration64(1.0), Length64(1.0)
    )
    var two = StressEnergy(
        TensorField(moving, CONTRAVARIANT, COORDINATE_FRAME), "x", FOURTH_ORDER
    )
    with assert_raises(contains="one time slice"):
        _ = momentum_flow_lines(two, start, Compliance64(1.0), 5)
    var energy = _flow_tensor(grid)
    with assert_raises(contains="step must be finite"):
        _ = momentum_flow_lines(
            energy, start, Compliance64(inf[DType.float64]()), 5
        )
    with assert_raises(contains="at least one step"):
        _ = momentum_flow_lines(energy, start, Compliance64(1.0), 0)


def test_evaluate_metric() raises:
    var metric = _bubble(0.25, 0.9, -0.6, 0.4)
    var full = evaluate_metric(metric, True, 6, 2)
    var point = metric.grid().index(0, 2, 2, 2)
    assert_equal(full.metric.name, "Alcubierre Comoving")
    assert_equal(full.energy.tensor.index, CONTRAVARIANT)
    assert_true(full.null.at(point).value < 0.0)
    assert_true(full.weak.at(point).value < 0.0)
    assert_true(full.dominant.at(point).value != 0.0)
    assert_true(full.strong.at(point).value != 0.0)
    assert_true(full.eulerian.tensor.get(0, 0, point) < 0.0)
    assert_true(full.scalars.expansion[point] < 0.0)
    var kept = evaluate_metric(metric, False, 6, 2)
    for p in range(metric.grid().points()):
        assert_true(kept.null.values[p] <= 0.0)
        assert_true(kept.weak.values[p] <= 0.0)
        assert_true(kept.strong.values[p] <= 0.0)
        assert_true(kept.dominant.values[p] <= 0.0)
    assert_equal(kept.null.at(point).value, full.null.at(point).value)


def test_slice_plane() raises:
    var grid = SpacetimeGrid(
        2, 3, 4, 5, Duration64(1.0), Length64(1.0), Length64(1.0), Length64(1.0)
    )
    var field = List[Float64]()
    for point in range(grid.points()):
        field.append(Float64(point))
    var xy = slice_plane(field, grid, T_AXIS, 1, Z_AXIS, 3)
    assert_equal(xy.columns, 3)
    assert_equal(xy.rows, 4)
    assert_equal(xy.at(2, 1), Float64(grid.index(1, 2, 1, 3)))
    var tz = slice_plane(field, grid, Y_AXIS, 2, X_AXIS, 0)
    assert_equal(tz.columns, 2)
    assert_equal(tz.rows, 5)
    assert_equal(tz.at(1, 4), Float64(grid.index(1, 0, 2, 4)))
    var bounds = xy.bounds()
    assert_equal(bounds[0], Float64(grid.index(1, 0, 0, 3)))
    assert_equal(bounds[1], Float64(grid.index(1, 2, 3, 3)))
    with assert_raises(contains="one value for each grid point"):
        _ = slice_plane(List[Float64](), grid, T_AXIS, 0, Z_AXIS, 0)
    with assert_raises(contains="axis is not valid"):
        _ = slice_plane(field, grid, Axis(4), 0, Z_AXIS, 0)
    with assert_raises(contains="axis is not valid"):
        _ = slice_plane(field, grid, T_AXIS, 0, Axis(-2), 0)
    with assert_raises(contains="two different axes"):
        _ = slice_plane(field, grid, X_AXIS, 0, X_AXIS, 0)
    with assert_raises(contains="outside the grid"):
        _ = slice_plane(field, grid, T_AXIS, -1, Z_AXIS, 0)
    with assert_raises(contains="outside the grid"):
        _ = slice_plane(field, grid, T_AXIS, 2, Z_AXIS, 0)
    with assert_raises(contains="outside the grid"):
        _ = slice_plane(field, grid, T_AXIS, 0, Z_AXIS, -1)
    with assert_raises(contains="outside the grid"):
        _ = slice_plane(field, grid, T_AXIS, 0, Z_AXIS, 5)


def test_plane_range() raises:
    var values: List[Float64] = [
        nan[DType.float64](),
        3.0,
        -2.0,
        inf[DType.float64](),
    ]
    var plane = PlaneSlice(2, 2, values^)
    var bounds = plane.bounds()
    assert_equal(bounds[0], -2.0)
    assert_equal(bounds[1], 3.0)
    var blank: List[Float64] = [nan[DType.float64](), nan[DType.float64]()]
    var empty = PlaneSlice(2, 1, blank^)
    assert_equal(empty.bounds()[0], 0.0)
    assert_equal(empty.bounds()[1], 0.0)
    var nothing = PlaneSlice(0, 0, List[Float64]())
    assert_equal(nothing.bounds()[1], 0.0)


def test_red_blue() raises:
    assert_true(red_blue(nan[DType.float64](), -1.0, 1.0) == Color(0, 0, 0))
    # Across zero: red, white, blue.
    assert_true(red_blue(-2.0, -2.0, 4.0) == Color(255, 0, 0))
    assert_true(red_blue(0.0, -2.0, 4.0) == Color(255, 255, 255))
    assert_true(red_blue(4.0, -2.0, 4.0) == Color(0, 0, 255))
    assert_true(red_blue(2.0, -2.0, 4.0) == Color(128, 128, 255))
    assert_true(red_blue(-1.0, -2.0, 4.0) == Color(255, 128, 128))
    # All positive: white to blue.
    assert_true(red_blue(1.0, 1.0, 3.0) == Color(255, 255, 255))
    assert_true(red_blue(3.0, 1.0, 3.0) == Color(0, 0, 255))
    assert_true(red_blue(2.0, 2.0, 2.0) == Color(255, 255, 255))
    # All negative: red to white.
    assert_true(red_blue(-3.0, -3.0, -1.0) == Color(255, 0, 0))
    assert_true(red_blue(-1.0, -3.0, -1.0) == Color(255, 255, 255))
    assert_true(red_blue(-2.0, -2.0, -2.0) == Color(255, 255, 255))
    assert_true(red_blue(0.0, 0.0, 0.0) == Color(255, 255, 255))


def test_draw_plane() raises:
    var values: List[Float64] = [-1.0, 0.0, 1.0, 1.0, 1.0, 1.0]
    var plane = PlaneSlice(3, 2, values^)
    var frame = draw_plane(plane, 2)
    assert_equal(frame.width, 6)
    assert_equal(frame.height, 4)
    # The first row is drawn at the bottom.
    var bottom_left = (3 * 6 + 0) * 4
    assert_equal(frame.pixels[bottom_left], 255)
    assert_equal(frame.pixels[bottom_left + 1], 0)
    var top_left = (0 * 6 + 1) * 4
    assert_equal(frame.pixels[top_left], 0)
    assert_equal(frame.pixels[top_left + 2], 255)
    with assert_raises(contains="scale must be 1 or more"):
        _ = draw_plane(plane, 0)
    assert_false(frame.pixels[(2 * 6 + 2) * 4 + 1] == 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
