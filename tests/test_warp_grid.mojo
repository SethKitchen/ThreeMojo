# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the kinds, grids, tensors, 3+1 split and finite differences of
`extensions.warp`.

The finite-difference tests use polynomials. A fourth-order central first
difference is exact for a polynomial of degree 4, and a fourth-order
second difference for degree 5. A second-order first difference is exact
for degree 2.
"""

from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from extensions.warp.derivatives import Stencil, derivative, second_derivative
from extensions.warp.grid import (
    MAX_GRID_POINTS,
    SpacetimeCenter,
    SpacetimeGrid,
    grid_place,
    grid_time,
    require_single_slice,
)
from extensions.warp.kinds import (
    Axis,
    CONTRAVARIANT,
    COORDINATE_FRAME,
    COVARIANT,
    DOMINANT_ENERGY,
    DifferenceOrder,
    EULERIAN_FRAME,
    EXACT_DERIVATIVES,
    EnergyCondition,
    FOURTH_ORDER,
    Frame,
    MIXED_DOWN_UP,
    MIXED_UP_DOWN,
    NULL_ENERGY,
    SECOND_ORDER,
    STRONG_ENERGY,
    T_AXIS,
    TensorIndex,
    WEAK_ENERGY,
    X_AXIS,
    Y_AXIS,
    Z_AXIS,
)
from extensions.warp.quantities import (
    GRAVITATIONAL_CONSTANT,
    JOULE_PER_CUBIC_METER,
    SPEED_OF_LIGHT,
    EnergyDensity64,
    einstein_coupling,
    fraction_of_light,
    light_fraction,
    schwarzschild_radius,
)
from extensions.warp.tensor import (
    MINKOWSKI,
    Matrix4,
    Metric,
    TensorField,
    Vector4,
    apply4,
    change_index,
    cofactors4,
    determinant4,
    inverse4,
    multiply4,
    trace,
    transpose4,
)
from extensions.warp.three_plus_one import ThreePlusOne, decompose, inverse3
from units.si import Duration64, Length64, Mass64


def _grid(nt: Int, n: Int) raises -> SpacetimeGrid:
    return SpacetimeGrid.uniform(nt, n, n, n, Duration64(1.0), Length64(0.5))


def _near(a: Matrix4, b: Matrix4, tolerance: Float64) raises:
    for k in range(16):
        assert_almost_equal(a[k], b[k], atol=tolerance)


def test_kinds() raises:
    assert_equal(T_AXIS.name(), "t")
    assert_equal(Z_AXIS.name(), "z")
    assert_equal(Axis(4).name(), "?")
    assert_false(Axis(-1).is_valid())
    assert_true(X_AXIS != Y_AXIS)
    assert_equal(COVARIANT.name(), "covariant")
    assert_equal(MIXED_DOWN_UP.name(), "mixeddownup")
    assert_equal(TensorIndex(4).name(), "?")
    assert_false(TensorIndex(-1).is_valid())
    assert_equal(NULL_ENERGY.name(), "Null")
    assert_equal(STRONG_ENERGY.name(), "Strong")
    assert_equal(EnergyCondition(9).name(), "?")
    assert_false(EnergyCondition(-1).is_valid())
    assert_true(NULL_ENERGY.uses_null_directions())
    assert_true(DOMINANT_ENERGY.uses_null_directions())
    assert_false(WEAK_ENERGY.uses_null_directions())
    assert_false(STRONG_ENERGY.uses_null_directions())
    assert_true(SECOND_ORDER.is_valid() and FOURTH_ORDER.is_valid())
    assert_false(DifferenceOrder(3).is_valid())
    assert_false(DifferenceOrder(-1).is_valid())
    assert_true(EXACT_DERIVATIVES.is_valid())
    assert_false(EXACT_DERIVATIVES.is_stencil())
    assert_true(SECOND_ORDER.is_stencil() and FOURTH_ORDER.is_stencil())
    assert_equal(SECOND_ORDER.reach(), 1)
    assert_equal(FOURTH_ORDER.reach(), 2)
    assert_true(COORDINATE_FRAME.is_valid() and EULERIAN_FRAME.is_valid())
    assert_false(Frame(2).is_valid())


def test_quantities() raises:
    assert_equal(SPEED_OF_LIGHT.value, 299792458.0)
    assert_equal(GRAVITATIONAL_CONSTANT.value, 6.67430e-11)
    assert_almost_equal(fraction_of_light(0.5).value, 149896229.0)
    assert_almost_equal(light_fraction(fraction_of_light(0.25)), 0.25)
    # The sun: about 2953 m.
    assert_almost_equal(
        schwarzschild_radius(Mass64(1.98847e30)).value, 2953.25, atol=0.1
    )
    assert_almost_equal(
        einstein_coupling(),
        SPEED_OF_LIGHT.value**4
        / (8.0 * 3.141592653589793 * GRAVITATIONAL_CONSTANT.value),
        atol=1e30,
    )
    assert_equal(EnergyDensity64(2.0, JOULE_PER_CUBIC_METER).value, 2.0)


def test_grid() raises:
    var grid = SpacetimeGrid(
        2,
        3,
        4,
        5,
        Duration64(2.0),
        Length64(0.5),
        Length64(0.25),
        Length64(0.125),
    )
    assert_equal(grid.points(), 120)
    assert_equal(grid.count(Y_AXIS), 4)
    assert_equal(grid.stride(T_AXIS), 60)
    assert_equal(grid.stride(X_AXIS), 20)
    assert_equal(grid.stride(Z_AXIS), 1)
    assert_equal(grid.time_step().value, 2.0)
    assert_equal(grid.spacing(Y_AXIS).value, 0.25)
    assert_equal(grid.coordinate_step(T_AXIS), 2.0 * SPEED_OF_LIGHT.value)
    assert_equal(grid.coordinate_step(Z_AXIS), 0.125)
    var point = grid.index(1, 2, 3, 4)
    assert_equal(point, 119)
    var at = grid.position(point)
    assert_equal(Int(at[0]), 1)
    assert_equal(Int(at[3]), 4)
    assert_equal(String(grid), "[2, 3, 4, 5]")
    assert_true(grid == grid)
    var other = SpacetimeGrid.uniform(
        2, 3, 4, 5, Duration64(2.0), Length64(1.0)
    )
    assert_false(grid == other)
    var center = grid.center()
    assert_equal(center.time.value, 3.0)
    assert_equal(center.x.value, 1.0)
    assert_equal(center.z.value, 0.375)
    assert_equal(grid_time(grid, center, 0), -1.0)
    assert_equal(grid_place(grid, center, X_AXIS, 1), 0.0)
    assert_equal(grid_place(grid, center, Y_AXIS, 0), -0.375)
    assert_equal(grid_place(grid, center, Z_AXIS, 4), 0.25)
    require_single_slice(_grid(1, 2), "test")
    with assert_raises(contains="needs one time slice"):
        require_single_slice(grid, "test")


def test_grid_refusals() raises:
    with assert_raises(contains="at least one point"):
        _ = SpacetimeGrid.uniform(0, 1, 1, 1, Duration64(1.0), Length64(1.0))
    with assert_raises(contains="at least one point"):
        _ = SpacetimeGrid.uniform(1, 1, 1, 0, Duration64(1.0), Length64(1.0))
    with assert_raises(contains="at least one point"):
        _ = SpacetimeGrid.uniform(1, 0, 1, 1, Duration64(1.0), Length64(1.0))
    with assert_raises(contains="at least one point"):
        _ = SpacetimeGrid.uniform(1, 1, 0, 1, Duration64(1.0), Length64(1.0))
    _ = SpacetimeGrid.uniform(
        1, MAX_GRID_POINTS, 1, 1, Duration64(1.0), Length64(1.0)
    )
    with assert_raises(contains="larger than"):
        _ = SpacetimeGrid.uniform(
            MAX_GRID_POINTS + 1, 1, 1, 1, Duration64(1.0), Length64(1.0)
        )
    with assert_raises(contains="larger than"):
        _ = SpacetimeGrid.uniform(
            2, MAX_GRID_POINTS // 2 + 1, 1, 1, Duration64(1.0), Length64(1.0)
        )
    with assert_raises(contains="larger than"):
        _ = SpacetimeGrid.uniform(
            1, 1024, 1025, 1, Duration64(1.0), Length64(1.0)
        )
    with assert_raises(contains="larger than"):
        _ = SpacetimeGrid.uniform(
            1, 1024, 1024, 2, Duration64(1.0), Length64(1.0)
        )
    with assert_raises(contains="time step"):
        _ = SpacetimeGrid.uniform(1, 1, 1, 1, Duration64(0.0), Length64(1.0))
    with assert_raises(contains="time step"):
        _ = SpacetimeGrid.uniform(
            1, 1, 1, 1, Duration64(nan[DType.float64]()), Length64(1.0)
        )
    with assert_raises(contains="x step"):
        _ = SpacetimeGrid(
            1,
            1,
            1,
            1,
            Duration64(1.0),
            Length64(-1.0),
            Length64(1.0),
            Length64(1.0),
        )
    with assert_raises(contains="y step"):
        _ = SpacetimeGrid(
            1,
            1,
            1,
            1,
            Duration64(1.0),
            Length64(1.0),
            Length64(inf[DType.float64]()),
            Length64(1.0),
        )
    with assert_raises(contains="z step"):
        _ = SpacetimeGrid(
            1,
            1,
            1,
            1,
            Duration64(1.0),
            Length64(1.0),
            Length64(1.0),
            Length64(0.0),
        )
    var center = SpacetimeCenter(
        Duration64(0.0), Length64(0.0), Length64(0.0), Length64(0.0)
    )
    center.require_finite()
    for part in range(4):
        var bad = center
        if part == 0:
            bad.time = Duration64(nan[DType.float64]())
        elif part == 1:
            bad.x = Length64(inf[DType.float64]())
        elif part == 2:
            bad.y = Length64(nan[DType.float64]())
        else:
            bad.z = Length64(-inf[DType.float64]())
        with assert_raises(contains="center must be finite"):
            bad.require_finite()


def test_matrices() raises:
    var a = Matrix4(2, 1, 0, 3, 1, 3, 0, 0, 0, 0, 1, 0, 3, 0, 0, 4)
    var b = Matrix4(1, 0, 0, 0, 2, 1, 0, 0, 0, 0, 1, 0, 0, 0, 5, 1)
    var ab = multiply4(a, b)
    assert_equal(ab[0], 4.0)
    assert_equal(ab[2], 15.0)
    assert_equal(transpose4(b)[1], 2.0)
    var v = apply4(a, Vector4(1, 0, 0, 1))
    assert_equal(v[0], 5.0)
    assert_equal(v[3], 7.0)
    # Expanding along the first row: 2 * 12 - 1 * 4 - 3 * 9 = -7.
    assert_almost_equal(determinant4(a), -7.0, atol=1e-14)
    assert_equal(cofactors4(a)[0], 12.0)
    _near(multiply4(a, inverse4(a)), MINKOWSKI * MINKOWSKI, 1e-14)
    with assert_raises(contains="singular"):
        _ = inverse4(Matrix4(0))
    with assert_raises(contains="singular"):
        _ = inverse4(Matrix4(nan[DType.float64]()))
    var g3 = SIMD[DType.float64, 16](
        2, 1, 0, 1, 2, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0
    )
    var g3i = inverse3(g3)
    assert_almost_equal(g3i[0], 2.0 / 3.0)
    assert_almost_equal(g3i[1], -1.0 / 3.0)
    assert_almost_equal(g3i[8], 0.25)
    with assert_raises(contains="spatial metric is singular"):
        _ = inverse3(SIMD[DType.float64, 16](0))
    with assert_raises(contains="spatial metric is singular"):
        _ = inverse3(SIMD[DType.float64, 16](inf[DType.float64]()))


def _boosted(grid: SpacetimeGrid) raises -> Metric:
    var parts = ThreePlusOne(grid)
    for point in range(grid.points()):
        parts.lapse[point] = 1.5
        parts.set_shift(0, point, 0.25)
        parts.set_shift(2, point, -0.125)
        parts.set_spatial(0, 0, point, 2.0)
        parts.set_spatial(0, 1, point, 0.5)
        parts.set_spatial(2, 2, point, 1.5)
    return parts.metric("boosted")


def test_tensor_field() raises:
    var grid = _grid(1, 2)
    with assert_raises(contains="index position is not valid"):
        _ = TensorField(grid, TensorIndex(7), COORDINATE_FRAME)
    with assert_raises(contains="frame is not valid"):
        _ = TensorField(grid, COVARIANT, Frame(3))
    var t = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    t.set(1, 2, 3, 4.0)
    assert_equal(t.get(1, 2, 3), 4.0)
    assert_equal(t.get(2, 1, 3), 0.0)
    t.set_symmetric(0, 3, 5, -1.0)
    assert_equal(t.get(3, 0, 5), -1.0)
    var m = t.matrix(3)
    assert_equal(m[6], 4.0)
    m[15] = 9.0
    t.set_matrix(7, m)
    assert_equal(t.get(3, 3, 7), 9.0)
    var column = t.component(1, 2)
    assert_equal(len(column), 8)
    assert_equal(column[3], 4.0)
    assert_equal(column[7], 4.0)
    t.require_finite()
    t.set(0, 0, 0, nan[DType.float64]())
    with assert_raises(contains="not finite"):
        t.require_finite()


def test_metric() raises:
    var grid = _grid(1, 2)
    with assert_raises(contains="must be covariant"):
        _ = Metric(TensorField(grid, CONTRAVARIANT, COORDINATE_FRAME), "x")
    with assert_raises(contains="coordinate frame"):
        _ = Metric(TensorField(grid, COVARIANT, EULERIAN_FRAME), "x")
    var bad = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    bad.set(1, 0, 4, inf[DType.float64]())
    with assert_raises(contains="not finite"):
        _ = Metric(bad^, "x")
    var skew = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    skew.set(0, 2, 6, 0.5)
    with assert_raises(contains="symmetric"):
        _ = Metric(skew^, "x")
    var metric = _boosted(grid)
    assert_equal(metric.name, "boosted")
    assert_true(metric.grid() == grid)
    var g = metric.at(3)
    var up = metric.inverse()
    assert_equal(up.index, CONTRAVARIANT)
    _near(multiply4(g, up.matrix(3)), MINKOWSKI * MINKOWSKI, 1e-14)
    with assert_raises(contains="singular"):
        _ = Metric(
            TensorField(grid, COVARIANT, COORDINATE_FRAME), "zero"
        ).inverse()


def test_change_index() raises:
    var grid = _grid(1, 2)
    var metric = _boosted(grid)
    var g = metric.at(2)
    var gu = inverse4(g)
    var t = TensorField(grid, CONTRAVARIANT, COORDINATE_FRAME)
    var value = Matrix4(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
    t.set_matrix(2, value)
    var down = change_index(t, COVARIANT, metric)
    assert_equal(down.index, COVARIANT)
    _near(down.matrix(2), multiply4(multiply4(g, value), g), 1e-12)
    var up_down = change_index(t, MIXED_UP_DOWN, metric)
    _near(up_down.matrix(2), multiply4(value, g), 1e-12)
    var down_up = change_index(t, MIXED_DOWN_UP, metric)
    _near(down_up.matrix(2), multiply4(g, value), 1e-12)
    # Between the two mixed positions, both indices move.
    var swapped = change_index(up_down, MIXED_DOWN_UP, metric)
    _near(swapped.matrix(2), down_up.matrix(2), 1e-11)
    _near(
        change_index(down_up, MIXED_UP_DOWN, metric).matrix(2),
        up_down.matrix(2),
        1e-11,
    )
    # Back to contravariant from every position.
    _near(change_index(down, CONTRAVARIANT, metric).matrix(2), value, 1e-10)
    _near(change_index(up_down, CONTRAVARIANT, metric).matrix(2), value, 1e-10)
    _near(change_index(down_up, CONTRAVARIANT, metric).matrix(2), value, 1e-10)
    _near(
        change_index(down, MIXED_UP_DOWN, metric).matrix(2),
        up_down.matrix(2),
        1e-10,
    )
    _near(
        change_index(up_down, COVARIANT, metric).matrix(2),
        down.matrix(2),
        1e-10,
    )
    _near(change_index(t, CONTRAVARIANT, metric).matrix(2), value, 0.0)
    _near(
        multiply4(multiply4(gu, down.matrix(2)), gu),
        change_index(down, CONTRAVARIANT, metric).matrix(2),
        1e-10,
    )
    # An Eulerian tensor moves with the Minkowski metric.
    var e = TensorField(grid, CONTRAVARIANT, EULERIAN_FRAME)
    e.set_matrix(2, value)
    var e_down = change_index(e, COVARIANT, metric)
    assert_equal(e_down.frame, EULERIAN_FRAME)
    _near(
        e_down.matrix(2), multiply4(multiply4(MINKOWSKI, value), MINKOWSKI), 0.0
    )
    _near(change_index(e_down, CONTRAVARIANT, metric).matrix(2), value, 0.0)
    with assert_raises(contains="not valid"):
        _ = change_index(t, TensorIndex(5), metric)
    with assert_raises(contains="share one grid"):
        _ = change_index(
            TensorField(_grid(1, 3), COVARIANT, COORDINATE_FRAME),
            COVARIANT,
            metric,
        )


def test_trace() raises:
    var grid = _grid(1, 2)
    var metric = _boosted(grid)
    # The trace of the metric itself is 4 at every index position.
    var traces = trace(metric.tensor, metric)
    assert_equal(len(traces), grid.points())
    assert_almost_equal(traces[5], 4.0, atol=1e-14)
    var up = metric.inverse()
    assert_almost_equal(trace(up, metric)[5], 4.0, atol=1e-14)
    var e = TensorField(grid, CONTRAVARIANT, EULERIAN_FRAME)
    e.set_matrix(0, Matrix4(3, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1))
    # η_ab T^ab = -3 + 1 + 1 + 1.
    assert_equal(trace(e, metric)[0], 0.0)


def test_three_plus_one() raises:
    var grid = _grid(1, 2)
    var parts = ThreePlusOne(grid)
    assert_equal(parts.lapse[3], 1.0)
    assert_equal(parts.spatial_at(1, 1, 3), 1.0)
    assert_equal(parts.spatial_at(0, 1, 3), 0.0)
    parts.set_shift(1, 3, 0.5)
    assert_equal(parts.shift_at(1, 3), 0.5)
    parts.set_spatial(0, 2, 3, 0.25)
    assert_equal(parts.spatial_at(2, 0, 3), 0.25)
    assert_equal(parts.spatial_matrix(3)[2], 0.25)
    var metric = _boosted(grid)
    var g = metric.at(1)
    # β_i = (0.25, 0, -0.125) and γ = [[2, .5, 0], [.5, 1, 0], [0, 0, 1.5]].
    assert_equal(g[1], 0.25)
    assert_equal(g[3], -0.125)
    assert_equal(g[6], 0.5)
    var beta_up_x = 0.25 * (1.0 / 1.75)
    var beta_up_y = 0.25 * (-0.5 / 1.75)
    var beta_up_z = -0.125 / 1.5
    var g00 = -2.25 + beta_up_x * 0.25 + beta_up_z * -0.125
    assert_almost_equal(g[0], g00, atol=1e-15)
    var split = decompose(metric)
    assert_almost_equal(split.parts.lapse[1], 1.5, atol=1e-14)
    assert_almost_equal(split.parts.shift_at(0, 1), 0.25)
    assert_almost_equal(split.parts.spatial_at(1, 0, 1), 0.5)
    var n = grid.points()
    assert_almost_equal(split.shift_up[1], beta_up_x, atol=1e-15)
    assert_almost_equal(split.shift_up[n + 1], beta_up_y, atol=1e-15)
    assert_almost_equal(split.shift_up[2 * n + 1], beta_up_z, atol=1e-15)
    assert_almost_equal(split.spatial_up[8 * n + 1], 1.0 / 1.5, atol=1e-15)
    var flat = ThreePlusOne(grid)
    flat.set_spatial(1, 1, 0, 0.0)
    with assert_raises(contains="spatial metric is singular"):
        _ = flat.metric("bad")
    var horizon = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    for point in range(n):
        horizon.set_matrix(point, MINKOWSKI * MINKOWSKI)
    with assert_raises(contains="no real lapse"):
        _ = decompose(Metric(horizon^, "static"))
    # A shift so large that β_i βⁱ - g_00 overflows: no finite lapse.
    var huge = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    for point in range(n):
        huge.set_matrix(point, MINKOWSKI * MINKOWSKI)
        huge.set(0, 0, point, -1.7e308)
        huge.set_symmetric(0, 1, point, 1e154)
    with assert_raises(contains="no real lapse"):
        _ = decompose(Metric(huge^, "huge"))
    var inside = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    for point in range(n):
        inside.set_matrix(point, MINKOWSKI * MINKOWSKI)
        inside.set(1, 1, point, 0.0)
    with assert_raises(contains="spatial metric is singular"):
        _ = decompose(Metric(inside^, "flat"))


def _polynomial(grid: SpacetimeGrid, fourth: Bool) -> List[Float64]:
    """Return f = t² + x³ y + x y² z + z⁴ on the grid's indexes times their
    steps, or a quadratic for the second order."""
    var out = List[Float64](capacity=grid.points())
    for point in range(grid.points()):
        var at = grid.position(point)
        var t = Float64(at[0]) * grid.coordinate_step(T_AXIS)
        var x = Float64(at[1]) * grid.coordinate_step(X_AXIS)
        var y = Float64(at[2]) * grid.coordinate_step(Y_AXIS)
        var z = Float64(at[3]) * grid.coordinate_step(Z_AXIS)
        if fourth:
            out.append(t * t + x * x * x * y + x * y * y * z + z * z * z * z)
        else:
            out.append(t * t + x * y + 3.0 * z * z)
    return out^


def test_fourth_order_differences() raises:
    var grid = SpacetimeGrid(
        6,
        7,
        6,
        8,
        Duration64(1e-9),
        Length64(0.5),
        Length64(0.25),
        Length64(1.0),
    )
    var f = _polynomial(grid, True)
    var p = grid.index(3, 3, 2, 4)
    var ct = 3.0 * grid.coordinate_step(T_AXIS)
    var x = 1.5
    var y = 0.5
    var z = 4.0
    assert_almost_equal(derivative(f, grid, T_AXIS)[p], 2.0 * ct, atol=1e-6)
    assert_almost_equal(
        derivative(f, grid, X_AXIS)[p], 3.0 * x * x * y + y * y * z, atol=1e-11
    )
    assert_almost_equal(
        derivative(f, grid, Z_AXIS)[p], x * y * y + 4.0 * z * z * z, atol=1e-10
    )
    assert_almost_equal(
        second_derivative(f, grid, X_AXIS, X_AXIS)[p], 6.0 * x * y, atol=1e-10
    )
    assert_almost_equal(
        second_derivative(f, grid, X_AXIS, Y_AXIS)[p],
        3.0 * x * x + 2.0 * y * z,
        atol=1e-10,
    )
    assert_almost_equal(
        second_derivative(f, grid, Z_AXIS, Y_AXIS)[p], 2.0 * x * y, atol=1e-10
    )
    assert_almost_equal(
        second_derivative(f, grid, T_AXIS, T_AXIS)[p], 2.0, atol=1e-8
    )
    # Near an edge, a first or a pure second difference copies the
    # nearest one; a mixed difference is zero.
    var edge = grid.index(3, 0, 2, 4)
    var inner = grid.index(3, 2, 2, 4)
    assert_equal(
        derivative(f, grid, X_AXIS)[edge], derivative(f, grid, X_AXIS)[inner]
    )
    assert_equal(
        second_derivative(f, grid, X_AXIS, X_AXIS)[edge],
        second_derivative(f, grid, X_AXIS, X_AXIS)[inner],
    )
    assert_equal(second_derivative(f, grid, X_AXIS, Y_AXIS)[edge], 0.0)
    var far = grid.index(3, 3, 5, 4)
    assert_equal(second_derivative(f, grid, X_AXIS, Y_AXIS)[far], 0.0)
    var top = grid.index(3, 6, 2, 4)
    assert_equal(second_derivative(f, grid, X_AXIS, Y_AXIS)[top], 0.0)
    var low = grid.index(3, 3, 1, 4)
    assert_equal(second_derivative(f, grid, X_AXIS, Y_AXIS)[low], 0.0)


def test_second_order_differences() raises:
    var grid = SpacetimeGrid(
        3,
        4,
        3,
        5,
        Duration64(1e-9),
        Length64(0.5),
        Length64(0.25),
        Length64(1.0),
    )
    var f = _polynomial(grid, False)
    var p = grid.index(1, 1, 1, 2)
    assert_almost_equal(
        derivative(f, grid, T_AXIS, SECOND_ORDER)[p],
        2.0 * grid.coordinate_step(T_AXIS),
        atol=1e-7,
    )
    assert_almost_equal(derivative(f, grid, X_AXIS, SECOND_ORDER)[p], 0.25)
    assert_almost_equal(
        second_derivative(f, grid, Z_AXIS, Z_AXIS, SECOND_ORDER)[p], 6.0
    )
    assert_almost_equal(
        second_derivative(f, grid, X_AXIS, Y_AXIS, SECOND_ORDER)[p], 1.0
    )
    var edge = grid.index(1, 3, 1, 2)
    assert_equal(
        second_derivative(f, grid, X_AXIS, Y_AXIS, SECOND_ORDER)[edge], 0.0
    )
    assert_almost_equal(
        second_derivative(f, grid, T_AXIS, T_AXIS, SECOND_ORDER)[edge],
        2.0,
        atol=1e-6,
    )
    # Three points are too few for the fourth order: zero.
    var short = derivative(f, grid, T_AXIS, FOURTH_ORDER)
    assert_equal(short[p], 0.0)
    assert_equal(
        second_derivative(f, grid, X_AXIS, T_AXIS, FOURTH_ORDER)[p], 0.0
    )
    assert_equal(
        second_derivative(f, grid, Z_AXIS, T_AXIS, FOURTH_ORDER)[p], 0.0
    )
    var flat = SpacetimeGrid.uniform(1, 2, 2, 2, Duration64(1.0), Length64(1.0))
    var g = List[Float64](length=8, fill=1.0)
    assert_equal(derivative(g, flat, X_AXIS, SECOND_ORDER)[0], 0.0)


def test_difference_refusals() raises:
    var grid = _grid(1, 3)
    var f = List[Float64](length=grid.points(), fill=0.0)
    with assert_raises(contains="one value for each grid point"):
        _ = derivative(List[Float64](), grid, X_AXIS)
    with assert_raises(contains="one value for each grid point"):
        _ = second_derivative(List[Float64](), grid, X_AXIS, X_AXIS)
    with assert_raises(contains="axis is not valid"):
        _ = derivative(f, grid, Axis(4))
    with assert_raises(contains="axis is not valid"):
        _ = second_derivative(f, grid, Axis(-1), X_AXIS)
    with assert_raises(contains="axis is not valid"):
        _ = second_derivative(f, grid, X_AXIS, Axis(4))
    with assert_raises(contains="order is not valid"):
        _ = derivative(f, grid, X_AXIS, DifferenceOrder(3))
    with assert_raises(contains="order is not valid"):
        _ = Stencil(grid, DifferenceOrder(-1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
