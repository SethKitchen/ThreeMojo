# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the open channels of `extensions.hydraulics`.

The references are the closed forms of a rectangle and of a triangle,
the worked trapezoidal channel of Chow, "Open-Channel Hydraulics", 1959,
examples 4-2 and 6-2, and the profile equation
dy/dx = (S₀ - S_f) / (1 - Fr²), which the test integrates with the
classical Runge-Kutta method.
"""

from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.hydraulics.channel import (
    GRAVITY,
    Channel,
    ProfilePoint,
    critical_depth,
    friction_slope,
    froude_number,
    manning_flow,
    normal_depth,
    sequent_depth,
    specific_energy,
    water_surface_profile,
)
from units.si import (
    CUBIC_METER_PER_SECOND,
    FOOT,
    Length64,
    METER,
    SQUARE_METER,
    VolumeFlowRate64,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _q(v: Float64) -> VolumeFlowRate64:
    return VolumeFlowRate64(v, CUBIC_METER_PER_SECOND)


def test_section() raises:
    """The area, the perimeter and the top width of a trapezoid."""
    var channel = Channel(_m(3), 2, 0.001, 0.02)
    assert_almost_equal(channel.area(_m(1.5)).to(SQUARE_METER), 9.0, atol=1e-12)
    assert_almost_equal(
        channel.wetted_perimeter(_m(1.5)).to(METER),
        3 + 3 * sqrt(5.0),
        atol=1e-12,
    )
    assert_almost_equal(channel.top_width(_m(1.5)).to(METER), 9.0, atol=1e-12)
    assert_almost_equal(
        channel.hydraulic_radius(_m(1.5)).to(METER),
        9 / (3 + 3 * sqrt(5.0)),
        atol=1e-12,
    )
    var bad = nan[DType.float64]()
    with assert_raises(contains="bottom width"):
        _ = Channel(_m(-1), 1, 0.001, 0.02)
    with assert_raises(contains="bottom width"):
        _ = Channel(_m(inf[DType.float64]()), 1, 0.001, 0.02)
    with assert_raises(contains="side slope"):
        _ = Channel(_m(1), -1, 0.001, 0.02)
    with assert_raises(contains="side slope"):
        _ = Channel(_m(1), inf[DType.float64](), 0.001, 0.02)
    with assert_raises(contains="needs a bottom width"):
        _ = Channel(_m(0), 0, 0.001, 0.02)
    with assert_raises(contains="bed slope"):
        _ = Channel(_m(1), 0, bad, 0.02)
    with assert_raises(contains="Manning"):
        _ = Channel(_m(1), 0, 0.001, 0)


def test_rectangle_closed_forms() raises:
    """A rectangle 4 m wide with a flow of 10 m³/s.

    Reference: the critical depth is (q² / g)^(1/3), with q the flow per
    width. The depth after a jump is y (sqrt(1 + 8 Fr²) - 1) / 2. The
    specific energy at the critical depth is 1.5 times it.
    """
    var channel = Channel(_m(4), 0, 0.0008, 0.015)
    var flow = _q(10)
    var critical = (2.5 * 2.5 / GRAVITY) ** (1.0 / 3.0)
    var got = critical_depth(channel, flow).to(METER)
    assert_almost_equal(got, critical, atol=1e-12)
    assert_almost_equal(
        froude_number(channel, flow, _m(critical)), 1.0, atol=1e-12
    )
    assert_almost_equal(
        specific_energy(channel, flow, _m(critical)).to(METER),
        1.5 * critical,
        atol=1e-12,
    )
    var shallow = 0.3
    var froude = froude_number(channel, flow, _m(shallow))
    assert_almost_equal(
        froude, 2.5 / (shallow * sqrt(GRAVITY * shallow)), atol=1e-12
    )
    var after = shallow * (sqrt(1 + 8 * froude * froude) - 1) / 2
    assert_almost_equal(
        sequent_depth(channel, flow, _m(shallow)).to(METER), after, atol=1e-11
    )
    # The jump is the same from the other side, and a critical flow has
    # no jump.
    assert_almost_equal(
        sequent_depth(channel, flow, _m(after)).to(METER), shallow, atol=1e-11
    )
    assert_almost_equal(
        sequent_depth(channel, flow, _m(got)).to(METER), got, atol=1e-7
    )
    # Uniform flow: the normal depth of Manning's flow at 1.2 m is 1.2 m.
    var uniform = manning_flow(channel, _m(1.2))
    var radius = 4.8 / 6.4
    assert_almost_equal(
        uniform.to(CUBIC_METER_PER_SECOND),
        4.8 * radius ** (2.0 / 3.0) * sqrt(0.0008) / 0.015,
        atol=1e-12,
    )
    assert_almost_equal(
        normal_depth(channel, uniform).to(METER), 1.2, atol=1e-12
    )
    assert_almost_equal(
        friction_slope(channel, uniform, _m(1.2)), 0.0008, atol=1e-15
    )


def test_triangle_and_large_flows() raises:
    """A triangle with sides of 1.5 to 1, and a river of 900 m³/s.

    Reference: the critical depth of a triangle is
    (2 Q² / (g z²))^(1/5).
    """
    var ditch = Channel(_m(0), 1.5, 0.002, 0.03)
    var expected = (2 * 4.0 / (GRAVITY * 2.25)) ** 0.2
    assert_almost_equal(
        critical_depth(ditch, _q(2)).to(METER), expected, atol=1e-12
    )
    # Depths above the first bracket of 1 m.
    var river = Channel(_m(40), 2, 0.0002, 0.03)
    var normal = normal_depth(river, _q(900)).to(METER)
    var critical = critical_depth(river, _q(900)).to(METER)
    assert_true(critical > 1 and normal > critical)
    assert_almost_equal(
        manning_flow(river, _m(normal)).to(CUBIC_METER_PER_SECOND),
        900.0,
        atol=1e-9,
    )
    assert_almost_equal(
        froude_number(river, _q(900), _m(critical)), 1.0, atol=1e-12
    )
    # A strong jump: the depth after it is above twice the critical depth.
    var after = sequent_depth(river, _q(900), _m(0.2 * critical)).to(METER)
    assert_true(after > 2 * critical)
    assert_almost_equal(
        sequent_depth(river, _q(900), _m(after)).to(METER),
        0.2 * critical,
        atol=1e-9,
    )


def test_chow_trapezoid() raises:
    """The channel of Chow: 20 ft wide, sides of 2 to 1, 400 ft³/s.

    Reference: with a slope of 0.0016 and n = 0.025, example 6-2 gives a
    normal depth of 3.36 ft. Example 4-2 gives a critical depth of
    2.15 ft. The table values have three digits.
    """
    var channel = Channel(Length64(20, FOOT), 2, 0.0016, 0.025)
    var flow = _q(400 * 0.3048**3)
    assert_true(abs(normal_depth(channel, flow).to(FOOT) - 3.36) < 0.006)
    assert_true(abs(critical_depth(channel, flow).to(FOOT) - 2.15) < 0.006)


def _slope(channel: Channel, q: Float64, y: Float64) raises -> Float64:
    """Return dy/dx = (S₀ - S_f) / (1 - Fr²) of the profile equation."""
    var froude = froude_number(channel, _q(q), _m(y))
    var friction = friction_slope(channel, _q(q), _m(y))
    return (channel.slope - friction) / (1 - froude * froude)


def _runge_kutta(
    channel: Channel, q: Float64, start: Float64, distance: Float64
) raises -> Float64:
    """Integrate the profile equation over a signed distance, in 4000 steps."""
    var y = start
    var h = distance / 4000
    for _ in range(4000):
        var k1 = _slope(channel, q, y)
        var k2 = _slope(channel, q, y + 0.5 * h * k1)
        var k3 = _slope(channel, q, y + 0.5 * h * k2)
        var k4 = _slope(channel, q, y + h * k3)
        y += h * (k1 + 2 * k2 + 2 * k3 + k4) / 6
    return y


def test_backwater_profile_meets_the_profile_equation() raises:
    """The M1 profile behind a dam, 1500 m upstream from a depth of 2 m.

    Reference: the profile equation, by Runge-Kutta. The standard step
    result is within 0.2 mm with 25 steps, and the error falls by four
    when the step is halved. The depth falls toward the normal depth and
    stays above it.
    """
    var channel = Channel(_m(6), 2, 0.001, 0.025)
    var q = 12.0
    var normal = normal_depth(channel, _q(q)).to(METER)
    assert_true(
        normal < 2 and normal > critical_depth(channel, _q(q)).to(METER)
    )
    var exact = _runge_kutta(channel, q, 2, -1500)
    var coarse = water_surface_profile(channel, _q(q), _m(2), _m(1500), 25)
    var fine = water_surface_profile(channel, _q(q), _m(2), _m(1500), 50)
    assert_equal(len(coarse), 26)
    assert_almost_equal(coarse[25].station.to(METER), -1500.0, atol=1e-9)
    assert_almost_equal(coarse[0].depth.to(METER), 2.0, atol=0)
    var coarse_error = abs(coarse[25].depth.to(METER) - exact)
    var fine_error = abs(fine[50].depth.to(METER) - exact)
    assert_true(coarse_error < 2e-4, String(coarse_error))
    var ratio = coarse_error / fine_error
    assert_true(ratio > 3.5 and ratio < 4.5, String(ratio))
    for i in range(1, 26):
        var depth = coarse[i].depth.to(METER)
        assert_true(depth < coarse[i - 1].depth.to(METER) and depth > normal)
    # A profile that starts at the normal depth stays there.
    var uniform = water_surface_profile(channel, _q(q), _m(normal), _m(800), 4)
    for i in range(5):
        assert_almost_equal(uniform[i].depth.to(METER), normal, atol=1e-9)


def test_supercritical_profile_runs_downstream() raises:
    """A steep chute: an S3 profile from 0.25 m, 60 m downstream.

    Reference: the profile equation, by Runge-Kutta, within 0.5 mm with
    40 steps. The depth rises toward the normal depth, which is below the
    critical depth.
    """
    var chute = Channel(_m(3), 0, 0.05, 0.014)
    var q = 9.0
    var normal = normal_depth(chute, _q(q)).to(METER)
    var critical = critical_depth(chute, _q(q)).to(METER)
    assert_true(normal < critical and normal > 0.25)
    var exact = _runge_kutta(chute, q, 0.25, 60)
    var profile = water_surface_profile(chute, _q(q), _m(0.25), _m(60), 40)
    assert_almost_equal(profile[40].station.to(METER), 60.0, atol=1e-9)
    var got = profile[40].depth.to(METER)
    assert_true(abs(got - exact) < 5e-4, String(got, " ", exact))
    assert_true(got > 0.25 and got < normal)


def test_drawdown_in_one_long_step() raises:
    """An M2 profile from near the critical depth, in one step of 100 m.

    Reference: upstream of a free fall the depth rises toward the normal
    depth. One step is coarse here, so the test checks only that the
    depth is above twice the start depth and below the normal depth.
    """
    var channel = Channel(_m(10), 0, 0.00005, 0.03)
    var q = 10.0
    var normal = normal_depth(channel, _q(q)).to(METER)
    var start = 1.05 * critical_depth(channel, _q(q)).to(METER)
    var profile = water_surface_profile(channel, _q(q), _m(start), _m(100), 1)
    var got = profile[1].depth.to(METER)
    assert_true(got > 2 * start and got < normal, String(got))


def test_profile_refusals() raises:
    var mild = Channel(_m(6), 2, 0.001, 0.025)
    var flow = _q(12)
    var critical = critical_depth(mild, flow)
    with assert_raises(contains="channel flow"):
        _ = water_surface_profile(mild, _q(0), _m(1), _m(10), 2)
    with assert_raises(contains="depth must be positive"):
        _ = water_surface_profile(mild, flow, _m(0), _m(10), 2)
    with assert_raises(contains="reach"):
        _ = water_surface_profile(mild, flow, _m(1), _m(0), 2)
    with assert_raises(contains="step count must be positive"):
        _ = water_surface_profile(mild, flow, _m(1), _m(10), 0)
    with assert_raises(contains="larger"):
        _ = water_surface_profile(mild, flow, _m(1), _m(10), 1048577)
    with assert_raises(contains="start at the critical depth"):
        _ = water_surface_profile(mild, flow, critical, _m(10), 2)
    # A supercritical flow on a mild slope rises to the critical depth.
    with assert_raises(contains="reaches the critical depth"):
        _ = water_surface_profile(mild, flow, _m(0.2), _m(2000), 4)
    # A subcritical flow on a steep slope falls to it going upstream.
    var steep = Channel(_m(3), 0, 0.05, 0.014)
    var above = 1.2 * critical_depth(steep, _q(9)).to(METER)
    with assert_raises(contains="reaches the critical depth"):
        _ = water_surface_profile(steep, _q(9), _m(above), _m(500), 2)
    with assert_raises(contains="channel flow"):
        _ = critical_depth(mild, _q(-1))
    with assert_raises(contains="channel flow"):
        _ = normal_depth(mild, _q(nan[DType.float64]()))
    var flat = Channel(_m(6), 2, 0, 0.025)
    with assert_raises(contains="positive bed slope"):
        _ = normal_depth(flat, flow)
    assert_almost_equal(
        manning_flow(flat, _m(1)).to(CUBIC_METER_PER_SECOND), 0.0, atol=0
    )
    var adverse = Channel(_m(6), 2, -0.001, 0.025)
    with assert_raises(contains="zero or more"):
        _ = manning_flow(adverse, _m(1))
    with assert_raises(contains="depth must be positive"):
        _ = manning_flow(mild, _m(-1))
    # A profile on an adverse bed: the depth rises going upstream.
    var up = water_surface_profile(adverse, flow, _m(2), _m(200), 4)
    assert_true(up[4].depth.to(METER) > 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
