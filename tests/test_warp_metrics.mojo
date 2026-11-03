# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the closed-form metrics of `extensions.warp.metrics`.

Each metric is checked at grid points against its formula, worked out in
the test. The Lentz regions are checked against WarpFactory's own chain
of seven region tests, copied here line for line from
`metricGet_Lentz.m` at commit 03b10cb.
"""

from std.math import inf, nan, sqrt, tanh
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from extensions.warp.grid import SpacetimeCenter, SpacetimeGrid
from extensions.warp.metrics import (
    SCHWARZSCHILD_OFFSET,
    alcubierre,
    alcubierre_comoving,
    alcubierre_shape,
    lentz,
    lentz_comoving,
    lentz_warp_factors,
    minkowski,
    modified_time,
    modified_time_comoving,
    schwarzschild,
    van_den_broeck,
    van_den_broeck_comoving,
)
from extensions.warp.quantities import SPEED_OF_LIGHT, fraction_of_light
from units.si import Duration64, InverseLength64, Length64, Velocity64


def _sign(y: Float64) -> Float64:
    if y > 0.0:
        return 1.0
    if y < 0.0:
        return -1.0
    return 0.0


def _upstream_lentz(
    x: Float64, y_in: Float64, s: Float64
) -> SIMD[DType.float64, 2]:
    """WarpFactory's `getWarpFactorByRegion`, line for line."""
    var y = abs(y_in)
    var wfx = 0.0
    var wfy = 0.0
    if (x >= s and x <= 2 * s) and (x - s >= y):
        wfx = -2
        wfy = 0
    elif (x > s and x <= 2 * s) and (x - s <= y) and (-y + 3 * s >= x):
        wfx = -1
        wfy = 1
    elif (x > 0 and x <= s) and (x + s > y) and (-y + s < x):
        wfx = 0
        wfy = 1
    elif (x > 0 and x <= s) and (x + s <= y) and (-y + 3 * s >= x):
        wfx = -0.5
        wfy = 0.5
    elif (x > -s and x <= 0) and (-x + s < y) and (-y + 3 * s >= -x):
        wfx = 0.5
        wfy = 0.5
    elif (x > -s and x <= 0) and (x + s <= y) and (-y + s >= x):
        wfx = 1
        wfy = 0
    elif (x >= -s and x <= s) and (x + s > y):
        wfx = 1
        wfy = 0
    return SIMD[DType.float64, 2](wfx, _sign(y_in) * wfy)


def _grid(nt: Int, n: Int, step: Float64) raises -> SpacetimeGrid:
    return SpacetimeGrid.uniform(
        nt, n, n, n, Duration64(0.5 / SPEED_OF_LIGHT.value), Length64(step)
    )


def _place(grid: SpacetimeGrid, point: Int) -> SIMD[DType.float64, 4]:
    """Return c t, x, y and z of a point about the grid's center."""
    var at = grid.position(point)
    var c = grid.center()
    return SIMD[DType.float64, 4](
        (Float64(at[0] + 1) * grid.time_step().value - c.time.value)
        * SPEED_OF_LIGHT.value,
        Float64(at[1] + 1) * 0.5 - c.x.value,
        Float64(at[2] + 1) * 0.5 - c.y.value,
        Float64(at[3] + 1) * 0.5 - c.z.value,
    )


def test_shape() raises:
    assert_almost_equal(alcubierre_shape(0.0, 2.0, 1.5), 1.0, atol=1e-15)
    var r = 2.0
    var expected = (tanh(1.5 * 4.0) + tanh(0.0)) / (2.0 * tanh(3.0))
    assert_almost_equal(alcubierre_shape(r, 2.0, 1.5), expected, atol=1e-15)
    assert_true(alcubierre_shape(10.0, 2.0, 1.5) < 1e-10)


def test_lentz_factors_match_warpfactory() raises:
    var count = 0
    for scale in range(1, 3):
        var s = Float64(scale)
        # Steps of s/8 put points on every edge of every region.
        for i in range(-28, 29):
            for j in range(-30, 31):
                var x = Float64(i) * s / 8.0
                var y = Float64(j) * s / 8.0
                var ours = lentz_warp_factors(x, y, s)
                var theirs = _upstream_lentz(x, y, s)
                assert_equal(ours[0], theirs[0])
                assert_equal(ours[1], theirs[1])
                count += 1
    assert_equal(count, 2 * 57 * 61)
    # One point in each region, at scale 1.
    assert_equal(lentz_warp_factors(1.5, 0.2, 1.0)[0], -2.0)
    assert_equal(lentz_warp_factors(1.5, -1.0, 1.0)[1], -1.0)
    assert_equal(lentz_warp_factors(0.5, 0.7, 1.0)[1], 1.0)
    assert_equal(lentz_warp_factors(0.5, 1.8, 1.0)[0], -0.5)
    assert_equal(lentz_warp_factors(-0.5, 1.8, 1.0)[0], 0.5)
    assert_equal(lentz_warp_factors(-0.5, 0.6, 1.0)[0], 1.0)
    assert_equal(lentz_warp_factors(0.5, 0.2, 1.0)[0], 1.0)
    assert_equal(lentz_warp_factors(5.0, 0.0, 1.0)[0], 0.0)


def test_minkowski() raises:
    var grid = _grid(1, 3, 0.5)
    var metric = minkowski(grid)
    assert_equal(metric.name, "Minkowski")
    var g = metric.at(13)
    assert_equal(g[0], -1.0)
    assert_equal(g[5], 1.0)
    assert_equal(g[1], 0.0)


def test_alcubierre() raises:
    var grid = _grid(5, 5, 0.5)
    var speed = fraction_of_light(0.8)
    var metric = alcubierre(
        grid, grid.center(), speed, Length64(1.0), InverseLength64(2.0)
    )
    assert_equal(metric.name, "Alcubierre")
    for point in [0, 77, 312, 400, 624]:
        var p = _place(grid, point)
        var r = sqrt((p[1] - 0.8 * p[0]) ** 2 + p[2] ** 2 + p[3] ** 2)
        var f = alcubierre_shape(r, 1.0, 2.0)
        var g = metric.at(point)
        assert_almost_equal(g[1], -0.8 * f, atol=1e-15)
        assert_almost_equal(g[0], -1.0 + 0.64 * f * f, atol=1e-15)
        assert_equal(g[5], 1.0)
    var comoving = alcubierre_comoving(
        _grid(1, 5, 0.5),
        _grid(1, 5, 0.5).center(),
        speed,
        Length64(1.0),
        InverseLength64(2.0),
    )
    assert_equal(comoving.name, "Alcubierre Comoving")
    var center = comoving.at(62)
    assert_almost_equal(center[1], 0.0, atol=1e-15)
    assert_almost_equal(center[0], -1.0, atol=1e-15)
    var corner = comoving.at(0)
    var f = alcubierre_shape(sqrt(3.0), 1.0, 2.0)
    assert_almost_equal(corner[1], 0.8 * (1.0 - f), atol=1e-15)


def test_lentz() raises:
    var grid = _grid(5, 5, 0.5)
    var speed = fraction_of_light(0.1)
    var metric = lentz(grid, grid.center(), speed, Length64(0.75))
    assert_equal(metric.name, "Lentz")
    for point in [0, 100, 213, 444, 600]:
        var p = _place(grid, point)
        var w = lentz_warp_factors(p[1] - 0.1 * p[0], p[2], 0.75)
        var g = metric.at(point)
        assert_almost_equal(g[1], -0.1 * w[0], atol=1e-15)
        assert_almost_equal(g[2], 0.1 * w[1], atol=1e-15)
    var still = _grid(1, 5, 0.5)
    var comoving = lentz_comoving(still, still.center(), speed, Length64(0.75))
    assert_equal(comoving.name, "Lentz Comoving")
    for point in [0, 33, 62, 99]:
        var p = _place(still, point)
        var w = lentz_warp_factors(p[1], p[2], 0.75)
        var g = comoving.at(point)
        assert_almost_equal(g[1], 0.1 * (1.0 - w[0]), atol=1e-15)
        assert_almost_equal(g[2], 0.1 * w[1], atol=1e-15)


def test_modified_time() raises:
    var grid = _grid(5, 5, 0.5)
    var speed = fraction_of_light(0.4)
    var metric = modified_time(
        grid, grid.center(), speed, Length64(1.0), InverseLength64(2.0), 4.0
    )
    assert_equal(metric.name, "Modified Time")
    for point in [0, 312, 555]:
        var p = _place(grid, point)
        var r = sqrt((p[1] - 0.4 * p[0]) ** 2 + p[2] ** 2 + p[3] ** 2)
        var f = alcubierre_shape(r, 1.0, 2.0)
        var lapse = (1.0 - f) + f / 4.0
        var g = metric.at(point)
        assert_almost_equal(g[1], -0.4 * f, atol=1e-15)
        assert_almost_equal(g[4], g[1], atol=0.0)
        assert_almost_equal(g[0], -lapse * lapse + (0.4 * f) ** 2, atol=1e-15)
    var still = _grid(1, 5, 0.5)
    var comoving = modified_time_comoving(
        still, still.center(), speed, Length64(1.0), InverseLength64(2.0), 4.0
    )
    assert_equal(comoving.name, "Modified Time Comoving")
    var g = comoving.at(62)
    assert_almost_equal(g[0], -0.0625 + 0.16, atol=1e-12)
    assert_almost_equal(g[1], 0.0, atol=1e-12)
    assert_almost_equal(g[4], g[1], atol=0.0)


def test_schwarzschild() raises:
    var grid = _grid(1, 5, 0.5)
    var rs = 0.25
    var metric = schwarzschild(grid, grid.center(), Length64(rs))
    assert_equal(metric.name, "Schwarzschild")
    var point = grid.index(0, 4, 1, 3)
    var p = _place(grid, point)
    var x = p[1]
    var y = p[2]
    var z = p[3]
    var r = sqrt(x * x + y * y + z * z) + SCHWARZSCHILD_OFFSET
    var g = metric.at(point)
    assert_almost_equal(g[0], -(1.0 - rs / r), atol=1e-15)
    # In Cartesian form, g_ij = δ_ij + rs/(r - rs) x_i x_j / r².
    assert_almost_equal(g[5], 1.0 + rs / (r - rs) * x * x / (r * r), atol=1e-14)
    assert_almost_equal(g[6], rs / (r - rs) * x * y / (r * r), atol=1e-14)
    assert_almost_equal(g[11], rs / (r - rs) * y * z / (r * r), atol=1e-14)
    assert_almost_equal(g[14], g[11], atol=0.0)
    # A point on the horizon divides by zero.
    var shell = SpacetimeCenter(
        Duration64(0.0), Length64(0.5), Length64(0.5 + 0.75), Length64(0.5)
    )
    with assert_raises(contains="not finite"):
        _ = schwarzschild(grid, shell, Length64(0.75 + SCHWARZSCHILD_OFFSET))


def test_van_den_broeck() raises:
    var grid = _grid(5, 5, 0.5)
    var speed = fraction_of_light(0.1)
    var metric = van_den_broeck(
        grid,
        grid.center(),
        speed,
        Length64(0.5),
        InverseLength64(2.0),
        Length64(1.5),
        InverseLength64(1.0),
        0.5,
    )
    assert_equal(metric.name, "Van Den Broeck")
    for point in [0, 250, 312, 600]:
        var p = _place(grid, point)
        var xs = p[0] * 0.1 * 2.25
        var r = sqrt((p[1] - xs) ** 2 + p[2] ** 2 + p[3] ** 2)
        var b = 1.0 + alcubierre_shape(r, 0.5, 2.0) * 0.5
        var f = alcubierre_shape(r, 1.5, 1.0) * 0.1
        var g = metric.at(point)
        assert_almost_equal(g[5], b * b, atol=1e-15)
        assert_almost_equal(g[15], b * b, atol=1e-15)
        assert_almost_equal(g[1], -b * b * f, atol=1e-15)
        assert_almost_equal(g[0], -(1.0 - b * b * f * f), atol=1e-15)
    var still = _grid(1, 5, 0.5)
    var comoving = van_den_broeck_comoving(
        still,
        still.center(),
        speed,
        Length64(0.5),
        InverseLength64(2.0),
        Length64(1.5),
        InverseLength64(1.0),
        0.5,
    )
    assert_equal(comoving.name, "Van Den Broeck Comoving")
    var g = comoving.at(62)
    var f = 0.1
    assert_almost_equal(g[5], 2.25, atol=1e-12)
    assert_almost_equal(g[1], 2.25 * (0.1 - f), atol=1e-12)
    assert_almost_equal(g[0], -(1.0 - 2.25 * f * f), atol=1e-12)


def test_refusals() raises:
    var moving = _grid(5, 5, 0.5)
    var still = _grid(1, 5, 0.5)
    var c = still.center()
    var v = fraction_of_light(0.5)
    var r = Length64(1.0)
    var s = InverseLength64(1.0)
    var bad_center = SpacetimeCenter(
        Duration64(0.0),
        Length64(nan[DType.float64]()),
        Length64(0.0),
        Length64(0.0),
    )
    var bad_speed = Velocity64(inf[DType.float64]())
    with assert_raises(contains="center must be finite"):
        _ = alcubierre(moving, bad_center, v, r, s)
    with assert_raises(contains="speed must be finite"):
        _ = alcubierre(moving, c, bad_speed, r, s)
    with assert_raises(contains="bubble radius"):
        _ = alcubierre(moving, c, v, Length64(0.0), s)
    with assert_raises(contains="bubble steepness"):
        _ = alcubierre(moving, c, v, r, InverseLength64(nan[DType.float64]()))
    with assert_raises(contains="one time slice"):
        _ = alcubierre_comoving(moving, c, v, r, s)
    with assert_raises(contains="bubble radius"):
        _ = alcubierre_comoving(still, c, v, Length64(-1.0), s)
    with assert_raises(contains="Lentz scale"):
        _ = lentz(moving, c, v, Length64(0.0))
    with assert_raises(contains="one time slice"):
        _ = lentz_comoving(moving, c, v, r)
    with assert_raises(contains="Lentz scale"):
        _ = lentz_comoving(still, c, v, Length64(inf[DType.float64]()))
    with assert_raises(contains="lapse factor"):
        _ = modified_time(moving, c, v, r, s, 0.0)
    with assert_raises(contains="lapse factor"):
        _ = modified_time(moving, c, v, r, s, nan[DType.float64]())
    with assert_raises(contains="one time slice"):
        _ = modified_time_comoving(moving, c, v, r, s, 2.0)
    with assert_raises(contains="lapse factor"):
        _ = modified_time_comoving(still, c, v, r, s, inf[DType.float64]())
    with assert_raises(contains="one time slice"):
        _ = schwarzschild(moving, c, r)
    with assert_raises(contains="Schwarzschild radius"):
        _ = schwarzschild(still, c, Length64(0.0))
    with assert_raises(contains="expansion factor"):
        _ = van_den_broeck(moving, c, v, r, s, r, s, nan[DType.float64]())
    with assert_raises(contains="bubble radius"):
        _ = van_den_broeck(moving, c, v, r, s, Length64(0.0), s, 0.5)
    with assert_raises(contains="one time slice"):
        _ = van_den_broeck_comoving(moving, c, v, r, s, r, s, 0.5)
    with assert_raises(contains="bubble steepness"):
        _ = van_den_broeck_comoving(
            still, c, v, r, InverseLength64(0.0), r, s, 0.5
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
