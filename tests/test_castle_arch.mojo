# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.castle.arch`.

The main reference is Heyman, "The stone skeleton", 1966: a semicircular
arch of constant thickness under its own weight stands if its thickness is
at least 0.1075 of its mean radius, and then its horizontal thrust is about
0.395 of its weight. The loads are checked against closed-form areas: the
annular sector of the ring and the fill above a semicircular extrados.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.castle.arch import ArchResult, analyze_arch, analyze_bridge
from extensions.castle.masonry import clay_brick_masonry
from extensions.castle.plan import wijnendale
from extensions.geotech.quantities import (
    KILONEWTON_PER_CUBIC_METER,
    UnitWeight64,
)
from std.math import nan, pi
from units.si import Length64, METER, Pressure64, KILOPASCAL, Density64


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _bare_semicircle(ratio: Float64, voussoirs: Int) raises -> ArchResult:
    """A semicircular ring of mean radius 1 m and thickness `ratio` m."""
    var inner = 1.0 - ratio / 2.0
    return analyze_arch(
        _m(2.0 * inner),
        _m(inner),
        _m(ratio),
        _m(1.0),
        clay_brick_masonry(),
        UnitWeight64(0.0),
        _m(0.0),
        Pressure64(0.0),
        voussoirs,
    )


def test_heyman_least_thickness_of_a_semicircular_arch() raises:
    var result = _bare_semicircle(0.1075, 40)
    # The least thickness is 0.1075 of the mean radius, to under 0.2 percent.
    assert_almost_equal(result.minimum_thickness.value, 0.1075, atol=2e-4)
    assert_almost_equal(result.geometric_factor, 1.0, atol=2e-3)
    assert_true(result.safe)


def test_heyman_thrust_at_the_least_thickness() raises:
    var result = _bare_semicircle(0.1075, 40)
    var low = result.thrust_min.value / result.vertical.value
    var high = result.thrust_max.value / result.vertical.value
    assert_true(low > 0.385)
    assert_true(high < 0.405)
    assert_true(low <= high)
    # At the critical thickness the line of thrust has one position.
    assert_almost_equal(low, high, atol=2e-3)


def test_a_ring_below_the_least_thickness_has_no_line_of_thrust() raises:
    var thin = _bare_semicircle(0.103, 40)
    assert_false(thin.safe)
    assert_almost_equal(thin.thrust_min.value, 0.0)
    assert_almost_equal(thin.thrust_max.value, 0.0)
    assert_true(thin.geometric_factor < 1.0)
    var thick = _bare_semicircle(0.112, 40)
    assert_true(thick.safe)
    assert_true(thick.geometric_factor > 1.0)


def test_a_thicker_ring_widens_the_range_of_thrust() raises:
    var a = _bare_semicircle(0.15, 30)
    var b = _bare_semicircle(0.25, 30)
    assert_true(
        b.thrust_max.value - b.thrust_min.value
        > a.thrust_max.value - a.thrust_min.value
    )
    assert_true(b.geometric_factor > a.geometric_factor)
    # The least thickness is the same, since the loads change only slowly.
    assert_almost_equal(
        b.minimum_thickness.value, a.minimum_thickness.value, atol=5e-3
    )


def test_a_very_thin_ring_still_gets_a_factor() raises:
    var thin = _bare_semicircle(0.02, 30)
    assert_false(thin.safe)
    assert_true(thin.geometric_factor < 0.25)
    assert_true(thin.minimum_thickness.value > 0.08)


def test_the_reaction_is_the_weight_of_the_half_arch() raises:
    var masonry = clay_brick_masonry()
    var result = analyze_arch(
        _m(4.0),
        _m(2.0),
        _m(0.5),
        _m(1.0),
        masonry,
        UnitWeight64(0.0),
        _m(0.0),
        Pressure64(0.0),
        20,
    )
    # A semicircular ring, inner radius 2 m and outer radius 2.5 m, has the
    # half area (pi / 4) (R^2 - r^2) per meter of width.
    var area = pi / 4.0 * (2.5**2 - 2.0**2)
    assert_almost_equal(
        result.vertical.value, masonry.unit_weight().value * area, atol=1e-6
    )


def test_fill_and_load_add_their_closed_form_weights() raises:
    var masonry = clay_brick_masonry()
    var fill = UnitWeight64(19.0, KILONEWTON_PER_CUBIC_METER)
    var result = analyze_arch(
        _m(4.0),
        _m(2.0),
        _m(0.5),
        _m(1.0),
        masonry,
        fill,
        _m(1.0),
        Pressure64(5.0, KILOPASCAL),
        40,
    )
    # The deck is 3.5 m above the springing line. The fill is the area
    # between the extrados, a semicircle of radius 2.5, and that deck:
    # 3.5 x 2.5 less a quarter disc. The load acts over the half width 2.5.
    var ring = masonry.unit_weight().value * (pi / 4.0 * (2.5**2 - 2.0**2))
    var column = 3.5 * 2.5 - pi * 2.5**2 / 4.0
    var expected = ring + 19000.0 * column + 5000.0 * 2.5
    assert_almost_equal(result.vertical.value / expected, 1.0, atol=1e-9)
    assert_true(result.safe)


def test_a_flatter_arch_pushes_harder() raises:
    var masonry = clay_brick_masonry()
    var fill = UnitWeight64(19.0, KILONEWTON_PER_CUBIC_METER)
    var tall = analyze_arch(
        _m(5.0),
        _m(1.4),
        _m(0.4),
        _m(4.2),
        masonry,
        fill,
        _m(0.5),
        Pressure64(0.0),
        24,
    )
    var flat = analyze_arch(
        _m(5.0),
        _m(0.9),
        _m(0.4),
        _m(4.2),
        masonry,
        fill,
        _m(0.5),
        Pressure64(0.0),
        24,
    )
    assert_true(tall.safe)
    assert_true(flat.safe)
    assert_true(flat.thrust_min.value > tall.thrust_min.value)


def test_a_thick_flat_ring_carries_any_thrust_up_to_the_limit() raises:
    var result = analyze_arch(
        _m(4.0),
        _m(0.1),
        _m(2.0),
        _m(1.0),
        clay_brick_masonry(),
        UnitWeight64(0.0),
        _m(0.0),
        Pressure64(0.0),
        20,
    )
    assert_true(result.safe)
    assert_almost_equal(
        result.thrust_max.value / result.vertical.value, 100.0, atol=1e-6
    )


def test_the_wijnendale_bridge_arch_is_safe() raises:
    var plan = wijnendale()
    var fill = UnitWeight64(19.0, KILONEWTON_PER_CUBIC_METER)
    var result = analyze_bridge(
        plan.bridge, clay_brick_masonry(), fill, Pressure64(5.0, KILOPASCAL), 24
    )
    assert_true(result.safe)
    assert_true(result.geometric_factor > 3.0)
    assert_true(result.thrust_min.value > 0.0)
    assert_true(result.thrust_min.value < result.thrust_max.value)
    # The same arch, given directly.
    var direct = analyze_arch(
        plan.bridge.span,
        plan.bridge.rise,
        plan.bridge.ring,
        plan.bridge.width,
        clay_brick_masonry(),
        fill,
        plan.bridge.fill,
        Pressure64(5.0, KILOPASCAL),
        24,
    )
    assert_almost_equal(direct.thrust_min.value, result.thrust_min.value)
    assert_almost_equal(direct.geometric_factor, result.geometric_factor)


def test_the_bridge_is_refused_when_it_is_not_sound() raises:
    var plan = wijnendale()
    plan.bridge.spans = 0
    with assert_raises(contains="at least one span"):
        _ = analyze_bridge(
            plan.bridge,
            clay_brick_masonry(),
            UnitWeight64(19.0, KILONEWTON_PER_CUBIC_METER),
            Pressure64(0.0),
            12,
        )


def test_analysis_refuses_bad_input() raises:
    var masonry = clay_brick_masonry()
    var fill = UnitWeight64(19.0, KILONEWTON_PER_CUBIC_METER)
    var none = Pressure64(0.0)
    var bad_masonry = masonry.copy()
    bad_masonry.density = Density64(0.0)
    with assert_raises(contains="A masonry density must be positive"):
        _ = analyze_arch(
            _m(4), _m(1), _m(0.4), _m(1), bad_masonry, fill, _m(0.5), none, 12
        )
    with assert_raises(contains="An arch span must be positive"):
        _ = analyze_arch(
            _m(0), _m(1), _m(0.4), _m(1), masonry, fill, _m(0.5), none, 12
        )
    with assert_raises(contains="An arch rise must be positive"):
        _ = analyze_arch(
            _m(4), _m(0), _m(0.4), _m(1), masonry, fill, _m(0.5), none, 12
        )
    with assert_raises(contains="An arch ring must be positive"):
        _ = analyze_arch(
            _m(4), _m(1), _m(0), _m(1), masonry, fill, _m(0.5), none, 12
        )
    with assert_raises(contains="An arch width must be positive"):
        _ = analyze_arch(
            _m(4), _m(1), _m(0.4), _m(0), masonry, fill, _m(0.5), none, 12
        )
    with assert_raises(contains="A fill weight must be zero or more"):
        _ = analyze_arch(
            _m(4),
            _m(1),
            _m(0.4),
            _m(1),
            masonry,
            UnitWeight64(-1.0),
            _m(0.5),
            none,
            12,
        )
    with assert_raises(contains="A fill weight must be zero or more"):
        _ = analyze_arch(
            _m(4),
            _m(1),
            _m(0.4),
            _m(1),
            masonry,
            UnitWeight64(1.0e13),
            _m(0.5),
            none,
            12,
        )
    with assert_raises(contains="A fill depth must be zero or more"):
        _ = analyze_arch(
            _m(4), _m(1), _m(0.4), _m(1), masonry, fill, _m(-0.5), none, 12
        )
    with assert_raises(contains="A fill depth must be zero or more"):
        _ = analyze_arch(
            _m(4), _m(1), _m(0.4), _m(1), masonry, fill, _m(2.0e9), none, 12
        )
    with assert_raises(contains="A surcharge must be zero or more"):
        _ = analyze_arch(
            _m(4),
            _m(1),
            _m(0.4),
            _m(1),
            masonry,
            fill,
            _m(0.5),
            Pressure64(-1.0),
            12,
        )
    with assert_raises(contains="A surcharge must be zero or more"):
        _ = analyze_arch(
            _m(4),
            _m(1),
            _m(0.4),
            _m(1),
            masonry,
            fill,
            _m(0.5),
            Pressure64(2.0e12),
            12,
        )
    with assert_raises(contains="at least two voussoirs"):
        _ = analyze_arch(
            _m(4), _m(1), _m(0.4), _m(1), masonry, fill, _m(0.5), none, 1
        )
    with assert_raises(contains="cannot rise more than half its span"):
        _ = analyze_arch(
            _m(4), _m(2.5), _m(0.4), _m(1), masonry, fill, _m(0.5), none, 12
        )
    with assert_raises(contains="An arch span must be positive"):
        _ = analyze_arch(
            _m(nan[DType.float64]()),
            _m(1),
            _m(0.4),
            _m(1),
            masonry,
            fill,
            _m(0.5),
            none,
            12,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
