# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the limit analysis of a masonry arch.

The reference is the classical result for a semicircular arch of uniform
thickness under its own weight: it stands down to a thickness of 0.1075 of the
mean radius (Couplet, 1730; Heyman, "The stone skeleton", 1966).
"""

from extensions.castle.arch import (
    Arch,
    arch_check,
    bridge_arch,
    minimum_thickness_ratio,
    thrust_range,
)
from extensions.castle.masonry import historic_brick
from extensions.castle.wijnendale import wijnendale_plan
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER


def test_the_least_thickness_is_the_classical_ratio() raises:
    # 0.1075 of the mean radius, to the accuracy of the published figure.
    assert_almost_equal(minimum_thickness_ratio(), 0.1075, atol=1.0e-4)
    assert_almost_equal(minimum_thickness_ratio(720), 0.107478, atol=1.0e-6)


def test_a_finer_mesh_of_joints_converges() raises:
    var coarse = minimum_thickness_ratio(90)
    var fine = minimum_thickness_ratio(2000)
    # The coarse search can only miss the hinge, so it is not above the fine.
    assert_true(coarse <= fine + 1.0e-12)
    assert_almost_equal(coarse, fine, atol=5.0e-5)
    assert_almost_equal(minimum_thickness_ratio(360), fine, atol=1.0e-6)
    with assert_raises(contains="at least 8"):
        _ = minimum_thickness_ratio(7)


def test_the_thrust_range_closes_at_the_least_thickness() raises:
    var thick = thrust_range(0.4)
    var thin = thrust_range(0.2)
    assert_true(thick[0] > 0.0)
    assert_true(thick[0] < thick[1])
    # A thicker ring leaves more room: a wider range of thrusts.
    assert_true(thick[1] - thick[0] > thin[1] - thin[0])
    assert_almost_equal(thin[0], 0.0967874, atol=1.0e-6)
    assert_almost_equal(thin[1], 0.1599410, atol=1.0e-6)
    # Just over the least thickness the range is a point, at 0.0668 of the
    # unit weight times the radius squared.
    var narrow = thrust_range(0.1076)
    assert_true(narrow[1] - narrow[0] < 1.0e-4)
    assert_almost_equal(narrow[0], 0.06681, atol=2.0e-4)


def test_a_ring_that_is_too_thin_falls() raises:
    with assert_raises(contains="falls"):
        _ = thrust_range(0.10)
    with assert_raises(contains="positive"):
        _ = thrust_range(0.0)
    with assert_raises(contains="positive"):
        _ = thrust_range(Float64(0.0) / Float64(0.0))
    with assert_raises(contains="at least 8"):
        _ = thrust_range(0.2, 4)


def test_the_bridge_arch_comes_from_the_plan() raises:
    var arch = bridge_arch(wijnendale_plan())
    # A clear span of 5.19 m: an intrados radius of 2.595 m, a ring of 0.6 m,
    # and so a mean radius of 2.895 m.
    assert_almost_equal(arch.mean_radius.value, 2.895, atol=1.0e-9)
    assert_almost_equal(arch.thickness.value, 0.6, atol=1.0e-12)
    assert_almost_equal(arch.thickness_ratio(), 0.2072539, atol=1.0e-6)


def test_the_bridge_arch_is_twice_as_thick_as_it_needs_to_be() raises:
    var check = arch_check(bridge_arch(wijnendale_plan()))
    assert_almost_equal(check.minimum_ratio, 0.107478, atol=1.0e-6)
    assert_almost_equal(check.ratio, 0.2072539, atol=1.0e-6)
    # Heyman's geometrical factor of safety is about 1.9: the ring could be
    # nearly half as thick and still stand.
    assert_almost_equal(check.geometric_factor, 1.92834, atol=1.0e-4)
    assert_true(check.geometric_factor > 1.5)
    # The thrusts, for one meter of width: the weight of the masonry is 17.65
    # kN/m^3 and the radius is 2.895 m.
    assert_true(check.least_thrust.value < check.greatest_thrust.value)
    assert_almost_equal(check.least_thrust.value, 14557.0, atol=100.0)
    assert_almost_equal(check.greatest_thrust.value, 24861.0, atol=100.0)
    assert_almost_equal(check.springing_force.value, 50315.0, atol=200.0)
    # The compression is small beside the strength of the masonry, which is
    # why Heyman's assumption that crushing does not govern holds here.
    assert_true(check.crushing_utilization < 0.05)


def test_a_ring_under_the_least_thickness_is_refused() raises:
    var thin = Arch(
        Length64(3.0, METER), Length64(0.3, METER), historic_brick()
    )
    with assert_raises(contains="falls"):
        _ = arch_check(thin)


def test_an_arch_is_checked() raises:
    var good = Arch(
        Length64(3.0, METER), Length64(0.6, METER), historic_brick()
    )
    good.check()
    var flat = Arch(Length64(0.0), Length64(0.6, METER), historic_brick())
    with assert_raises(contains="positive finite"):
        flat.check()
    var none = Arch(Length64(3.0, METER), Length64(0.0), historic_brick())
    with assert_raises(contains="positive finite"):
        none.check()
    var wide = Arch(
        Length64(3.0, METER), Length64(7.0, METER), historic_brick()
    )
    with assert_raises(contains="thicker"):
        wide.check()
    var bad = good.copy()
    bad.masonry.partial_factor = 0.0
    with assert_raises():
        bad.check()


def test_a_size_that_is_not_a_number_is_refused() raises:
    var good = Arch(
        Length64(3.0, METER), Length64(0.6, METER), historic_brick()
    )
    var radius = good.copy()
    radius.mean_radius = Length64(nan[DType.float64](), METER)
    with assert_raises(contains="positive finite"):
        radius.check()
    var thickness = good.copy()
    thickness.thickness = Length64(nan[DType.float64](), METER)
    with assert_raises(contains="positive finite"):
        thickness.check()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
