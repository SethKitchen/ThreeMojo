# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the geodesics of `extensions.warp.geodesics`.

The references are:

- In flat space a ray is a straight line, and the sky is not moved.
- Light that passes a mass m = rₛ/2 at the impact parameter b bends by
  4 m / b + 15 π m² / (4 b²), to second order. See Weinberg,
  "Gravitation and Cosmology" (1972), section 8.5, and Epstein and
  Shapiro, Physical Review D 22 (1980) 2947.
- A clock at rest at radius r outside a mass runs at √(1 - rₛ/r).
- A passenger at the center of a comoving Alcubierre bubble is in free
  fall and stays there, and its clock keeps coordinate time.
"""

from std.math import atan2, cos, nan, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from extensions.warp.analytic import AnalyticMetric, flat_components
from extensions.warp.jet import Jet
from extensions.warp.geodesics import (
    draw_view,
    geodesic_acceleration,
    metric_at,
    null_velocity,
    passenger_view,
    proper_time,
    sky_color,
    sky_direction,
    trace_geodesic,
    view_direction,
)
from extensions.warp.metrics import (
    AlcubierreMetric,
    MinkowskiMetric,
    SchwarzschildMetric,
)
from extensions.warp.quantities import SPEED_OF_LIGHT, fraction_of_light
from extensions.warp.tensor import Vector4
from render.framebuffer import Color
from units.si import Angle64, InverseLength64, Length64

comptime PI = 3.141592653589793


def test_straight_line() raises:
    var flat = MinkowskiMetric()
    var start = Vector4(0.0, 1.0, 2.0, 3.0)
    var u = null_velocity(flat, start, Vector4(0.0, 0.6, 0.8, 0.0))
    assert_almost_equal(u[0], 1.0, atol=1e-15)
    var ray = trace_geodesic(flat, start, u, Length64(0.5), 100, Length64(10.0))
    assert_true(ray.escaped)
    var last = ray.places[len(ray.places) - 1]
    var steps = Float64(len(ray.places) - 1)
    assert_almost_equal(last[1], 1.0 + 0.3 * steps, atol=1e-12)
    assert_almost_equal(last[2], 2.0 + 0.4 * steps, atol=1e-12)
    assert_equal(last[3], 3.0)
    var short = trace_geodesic(
        flat, start, u, Length64(0.5), 3, Length64(100.0)
    )
    assert_false(short.escaped)
    assert_equal(len(short.places), 4)
    var still = geodesic_acceleration(flat, start, u)
    assert_equal(still[1], 0.0)


def test_light_bending() raises:
    var rs = 0.01
    var m = rs / 2.0
    var b = 2.0
    var hole = SchwarzschildMetric(Length64(rs))
    var start = Vector4(0.0, -200.0, b, 0.0)
    var u = null_velocity(hole, start, Vector4(0.0, 1.0, 0.0, 0.0))
    var ray = trace_geodesic(
        hole, start, u, Length64(0.2), 3000, Length64(200.5)
    )
    assert_true(ray.escaped)
    var deflection = -atan2(ray.velocity[2], ray.velocity[1])
    var expected = 4.0 * m / b + 15.0 * PI * m * m / (4.0 * b * b)
    assert_almost_equal(deflection, expected, atol=1e-3 * expected)


def test_static_clock() raises:
    var rs = 0.5
    var hole = SchwarzschildMetric(Length64(rs))
    var places = List[Vector4]()
    for k in range(11):
        places.append(Vector4(Float64(k), 3.0, 0.0, 0.0))
    var tau = proper_time(hole, places)
    var r = 3.0 + 1e-10
    assert_almost_equal(
        tau.value, 10.0 * sqrt(1.0 - rs / r) / SPEED_OF_LIGHT.value, atol=1e-20
    )
    var one: List[Vector4] = [Vector4(0.0)]
    assert_equal(proper_time(hole, one).value, 0.0)
    var sideways: List[Vector4] = [
        Vector4(0.0, 3.0, 0.0, 0.0),
        Vector4(0.0, 3.0, 1.0, 0.0),
    ]
    with assert_raises(contains="not timelike"):
        _ = proper_time(hole, sideways)


def test_passenger_stays_at_the_center() raises:
    var bubble = AlcubierreMetric(
        fraction_of_light(2.0), Length64(2.0), InverseLength64(1.5), True
    )
    var start = Vector4(0.0)
    var u = Vector4(1.0, 0.0, 0.0, 0.0)
    var path = trace_geodesic(
        bubble, start, u, Length64(0.1), 50, Length64(10.0)
    )
    var last = path.places[len(path.places) - 1]
    assert_almost_equal(last[0], 5.0, atol=1e-12)
    assert_equal(last[1], 0.0)
    var tau = proper_time(bubble, path.places)
    assert_almost_equal(tau.value, 5.0 / SPEED_OF_LIGHT.value, atol=1e-20)


def test_view_direction() raises:
    var ahead = view_direction(1, 1, 3, 3, Angle64(PI / 2.0))
    assert_almost_equal(ahead[1], 1.0, atol=1e-15)
    var left = view_direction(0, 1, 3, 3, Angle64(PI / 2.0))
    assert_true(left[2] > 0.0)
    var top = view_direction(1, 0, 3, 3, Angle64(PI / 2.0))
    assert_true(top[3] > 0.0)
    assert_almost_equal((left * left).reduce_add(), 1.0, atol=1e-15)


def test_flat_sky_is_not_moved() raises:
    var flat = MinkowskiMetric()
    var look = view_direction(0, 0, 4, 3, Angle64(1.2))
    var sky = sky_direction(
        flat, Vector4(0.0), look, Length64(0.5), 100, Length64(5.0)
    )
    for k in range(1, 4):
        assert_almost_equal(sky[k], look[k], atol=1e-14)
    var lost = sky_direction(
        flat, Vector4(0.0), look, Length64(0.5), 2, Length64(5.0)
    )
    assert_true(lost[1] != lost[1])
    var view = passenger_view(
        flat,
        Vector4(0.0),
        4,
        3,
        Angle64(1.2),
        Length64(0.5),
        100,
        Length64(5.0),
        2,
    )
    assert_equal(len(view), 12)
    for k in range(1, 4):
        assert_almost_equal(view[0][k], look[k], atol=1e-14)
    var frame = draw_view(view, 4, 3)
    assert_equal(frame.width, 4)
    assert_equal(frame.height, 3)


def test_bubble_moves_the_sky() raises:
    # Inside a bubble moving at twice c, the sky ahead is bunched up.
    var bubble = AlcubierreMetric(
        fraction_of_light(2.0), Length64(2.0), InverseLength64(1.5), True
    )
    var look = view_direction(0, 0, 2, 2, Angle64(PI / 3.0))
    var sky = sky_direction(
        bubble, Vector4(0.0), look, Length64(0.05), 2000, Length64(6.0)
    )
    var angle_in = atan2(sqrt(look[2] * look[2] + look[3] * look[3]), look[1])
    var angle_out = atan2(sqrt(sky[2] * sky[2] + sky[3] * sky[3]), sky[1])
    assert_true(abs(angle_out - angle_in) > 0.01)


def test_sky_colors() raises:
    assert_true(sky_color(Vector4(nan[DType.float64]())) == Color(0, 0, 0))
    assert_true(sky_color(Vector4(0.0, 1.0, 0.0, 0.0)) == Color(230, 40, 40))
    assert_true(sky_color(Vector4(0.0, -1.0, 0.0, 0.0)) == Color(40, 90, 230))
    # On the equator at longitude 0: a grid line.
    assert_true(sky_color(Vector4(0.0, 0.0, 1.0, 0.0)) == Color(235, 235, 235))
    # Latitude and longitude 7 degrees: between the lines.
    var a = 7.0 * PI / 180.0
    var between = Vector4(0.0, sin(a), cos(a) * cos(a), cos(a) * sin(a))
    var color = sky_color(between)
    assert_false(color == Color(235, 235, 235))
    assert_false(color == Color(0, 0, 0))


@fieldwise_init
struct _TwoTimes(AnalyticMetric):
    """A metric with two time directions, t and x."""

    def components(self, place: List[Jet]) -> List[Jet]:
        var g = flat_components()
        g[5] = Jet.constant(-1.0)
        return g^

    def name(self) -> String:
        return "two times"


def test_geodesic_refusals() raises:
    var flat = MinkowskiMetric()
    var u = Vector4(1.0, 1.0, 0.0, 0.0)
    var z = Vector4(0.0)
    with assert_raises(contains="step must be positive"):
        _ = trace_geodesic(flat, z, u, Length64(0.0), 10, Length64(1.0))
    with assert_raises(contains="step must be positive"):
        _ = trace_geodesic(
            flat, z, u, Length64(nan[DType.float64]()), 10, Length64(1.0)
        )
    with assert_raises(contains="escape radius"):
        _ = trace_geodesic(flat, z, u, Length64(0.1), 10, Length64(-1.0))
    with assert_raises(contains="escape radius"):
        _ = trace_geodesic(
            flat, z, u, Length64(0.1), 10, Length64(nan[DType.float64]())
        )
    with assert_raises(contains="at least one step"):
        _ = trace_geodesic(flat, z, u, Length64(0.1), 0, Length64(1.0))
    # Inside the horizon the time direction is spacelike.
    var hole = SchwarzschildMetric(Length64(2.0))
    with assert_raises(contains="not timelike"):
        _ = null_velocity(
            hole, Vector4(0.0, 1.0, 0.0, 0.0), Vector4(0.0, 1.0, 0.0, 0.0)
        )
    # Outside a comoving bubble at three times c, the stars stream past
    # faster than light: the time direction is spacelike there.
    var fast = AlcubierreMetric(
        fraction_of_light(3.0), Length64(2.0), InverseLength64(1.5), True
    )
    with assert_raises(contains="not timelike"):
        _ = null_velocity(
            fast, Vector4(0.0, 6.0, 0.0, 0.0), Vector4(0.0, 0.0, 1.0, 0.0)
        )
    var g = metric_at(fast, Vector4(0.0, 6.0, 0.0, 0.0))
    assert_true(g[0] > 0.0)
    with assert_raises(contains="no null direction"):
        _ = null_velocity(_TwoTimes(), z, Vector4(0.0, 1.0, 0.0, 0.0))
    with assert_raises(contains="at least one pixel"):
        _ = passenger_view(
            flat, z, 0, 3, Angle64(1.0), Length64(0.1), 10, Length64(1.0)
        )
    with assert_raises(contains="at least one pixel"):
        _ = passenger_view(
            flat, z, 3, 0, Angle64(1.0), Length64(0.1), 10, Length64(1.0)
        )
    with assert_raises(contains="field of view"):
        _ = passenger_view(
            flat, z, 3, 3, Angle64(0.0), Length64(0.1), 10, Length64(1.0)
        )
    with assert_raises(contains="field of view"):
        _ = passenger_view(
            flat, z, 3, 3, Angle64(PI), Length64(0.1), 10, Length64(1.0)
        )
    with assert_raises(contains="could not be traced"):
        _ = passenger_view(
            flat, z, 2, 2, Angle64(1.0), Length64(0.0), 10, Length64(1.0)
        )
    with assert_raises(contains="one direction for each pixel"):
        _ = draw_view(List[Vector4](), 2, 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
