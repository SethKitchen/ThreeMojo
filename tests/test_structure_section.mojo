# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the fiber sections of `extensions.structure`.

The steel references are the closed forms of a rectangle of an
elastic-perfectly plastic material, from Chen and Han, "Plasticity for
Structural Engineers", 1988, chapter 4: M = M_y (3 - (κ_y / κ)²) / 2 past
yield, and a plastic moment of M_p (1 - (N / N_y)²) under an axial force.
The concrete reference is the nominal moment of a singly reinforced beam
by the rectangular stress block of ACI 318-19, section 22.2.
"""

from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.structure.nonlinear import BarState, SteelLaw
from extensions.structure.section import (
    ConcreteLaw,
    FiberSection,
    concrete_response,
    moment_curvature,
    section_response,
)
from units.si import (
    Area64,
    Force64,
    InverseLength64,
    Length64,
    METER,
    NEWTON,
    NEWTON_METER,
    PASCAL,
    PER_METER,
    Pressure64,
    SQUARE_METER,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _kappa(v: Float64) -> InverseLength64:
    return InverseLength64(v, PER_METER)


def _concrete() raises -> ConcreteLaw:
    """A concrete of 30 MPa that peaks at 0.002 and crushes to 6 MPa."""
    return ConcreteLaw(
        Pressure64(30e6, PASCAL), 0.002, Pressure64(6e6, PASCAL), 0.006
    )


def _steel(yield_stress: Float64) raises -> SteelLaw:
    return SteelLaw(
        Pressure64(200e9, PASCAL), Pressure64(yield_stress, PASCAL), 0
    )


def test_concrete_law() raises:
    """The envelope of Kent and Park at six strains.

    Reference: 0.75 of the strength at half the peak strain, the strength
    at the peak, a line to the crushing strength, and no tension. The
    first tangent is twice the strength over the peak strain.
    """
    var law = _concrete()
    assert_almost_equal(concrete_response(law, 0.001).stress, 0.0, atol=0)
    assert_almost_equal(concrete_response(law, 0.001).tangent, 0.0, atol=0)
    assert_almost_equal(concrete_response(law, 0).tangent, 0.0, atol=0)
    var half = concrete_response(law, -0.001)
    assert_almost_equal(half.stress, -22.5e6, atol=1e-6)
    assert_almost_equal(half.tangent, 15e9, atol=1e-3)
    assert_almost_equal(concrete_response(law, -1e-12).tangent, 30e9, atol=1e3)
    var peak = concrete_response(law, -0.002)
    assert_almost_equal(peak.stress, -30e6, atol=1e-6)
    assert_almost_equal(peak.tangent, 0.0, atol=1e-3)
    var falling = concrete_response(law, -0.004)
    assert_almost_equal(falling.stress, -18e6, atol=1e-6)
    assert_almost_equal(falling.tangent, -6e9, atol=1e-3)
    var crushed = concrete_response(law, -0.01)
    assert_almost_equal(crushed.stress, -6e6, atol=0)
    assert_almost_equal(crushed.tangent, 0.0, atol=0)
    var p = Pressure64(30e6, PASCAL)
    var bad = nan[DType.float64]()
    with assert_raises(contains="concrete strength"):
        _ = ConcreteLaw(Pressure64(0, PASCAL), 0.002, p, 0.006)
    with assert_raises(contains="peak strain"):
        _ = ConcreteLaw(p, 0, p, 0.006)
    with assert_raises(contains="crushing strength"):
        _ = ConcreteLaw(p, 0.002, Pressure64(-1, PASCAL), 0.006)
    with assert_raises(contains="crushing strength"):
        _ = ConcreteLaw(p, 0.002, Pressure64(31e6, PASCAL), 0.006)
    with assert_raises(contains="crushing strain"):
        _ = ConcreteLaw(p, 0.002, p, 0.002)
    with assert_raises(contains="crushing strain"):
        _ = ConcreteLaw(p, 0.002, p, inf[DType.float64]())
    with assert_raises(contains="crushing strain"):
        _ = ConcreteLaw(p, 0.002, p, bad)


def _plate(layers: Int) raises -> FiberSection:
    """A steel rectangle 100 mm wide and 200 mm deep, about its middle."""
    var section = FiberSection()
    section.add_steel_patch(_m(-0.1), _m(0.1), _m(0.1), layers, _steel(250e6))
    return section^


def test_steel_rectangle_yields_to_its_plastic_moment() raises:
    """A rectangle of perfectly plastic steel under a growing curvature.

    Reference: with M_y = σ b h² / 6 and κ_y = 2 σ / (E h), the moment is
    E I κ up to yield and M_y (3 - (κ_y / κ)²) / 2 past it. It tends to
    the plastic moment 1.5 M_y. With 200 layers the sum over the fibers is
    within 0.01% of the closed form.
    """
    var section = _plate(200)
    var yield_moment = 250e6 * 0.1 * 0.04 / 6
    var yield_curvature = 2 * 250e6 / (200e9 * 0.2)
    var curve = moment_curvature(
        section, Force64(0, NEWTON), _kappa(10 * yield_curvature), 20, 1e-10
    )
    assert_equal(len(curve), 21)
    assert_almost_equal(curve[0].moment.to(NEWTON_METER), 0.0, atol=1e-6)
    for i in range(1, 21):
        var kappa = curve[i].curvature.to(PER_METER)
        assert_almost_equal(
            kappa, 10 * yield_curvature * Float64(i) / 20, atol=1e-15
        )
        var ratio = kappa / yield_curvature
        var expected = yield_moment * ratio
        if ratio > 1:
            expected = yield_moment * (3 - 1 / (ratio * ratio)) / 2
        var got = curve[i].moment.to(NEWTON_METER)
        assert_true(abs(got / expected - 1) < 1e-4, String(i, " ", got))
        # A symmetric section in pure bending has no axial strain.
        assert_almost_equal(curve[i].strain, 0.0, atol=1e-12)
    var last = curve[20].moment.to(NEWTON_METER)
    assert_true(last > 1.49 * yield_moment and last < 1.5 * yield_moment)


def test_axial_force_lowers_the_plastic_moment() raises:
    """The same rectangle with a compression of 0.4 of its squash load.

    Reference: the plastic moment under an axial force N is
    M_p (1 - (N / N_y)²), so here 0.84 M_p. At 40 times the yield
    curvature the moment is within 0.1% of it.
    """
    var section = _plate(400)
    var squash = 250e6 * 0.02
    var plastic = 250e6 * 0.1 * 0.04 / 4
    var yield_curvature = 2 * 250e6 / (200e9 * 0.2)
    var curve = moment_curvature(
        section,
        Force64(-0.4 * squash, NEWTON),
        _kappa(40 * yield_curvature),
        80,
        1e-10,
    )
    # With no curvature the strain is the force over E A.
    assert_almost_equal(
        curve[0].strain, -0.4 * squash / (200e9 * 0.02), atol=1e-12
    )
    assert_almost_equal(curve[0].moment.to(NEWTON_METER), 0.0, atol=1e-6)
    var got = curve[80].moment.to(NEWTON_METER)
    assert_true(abs(got / (0.84 * plastic) - 1) < 1e-3, String(got))


def _beam() raises -> FiberSection:
    """A concrete beam 300 mm wide and 500 mm deep with 1500 mm² of steel.

    The reference axis is at mid depth. The steel is 60 mm above the
    bottom, so the effective depth is 440 mm.
    """
    var section = FiberSection()
    section.add_concrete_patch(_m(-0.25), _m(0.25), _m(0.3), 100, _concrete())
    section.add_steel(_m(-0.19), Area64(1500e-6, SQUARE_METER), _steel(420e6))
    return section^


def test_reinforced_beam_meets_the_stress_block() raises:
    """The peak moment of a singly reinforced concrete beam.

    Reference: ACI 318, M_n = A_s f_y (d - a / 2) with
    a = A_s f_y / (0.85 f_c b). The steel yields before the concrete
    crushes, so the peak moment of the fiber section is within 3% of it.
    The steel has yielded at the peak, and the top strain is near 0.003.
    """
    var section = _beam()
    var curve = moment_curvature(
        section, Force64(0, NEWTON), _kappa(0.06), 120, 1e-9
    )
    var tension = 1500e-6 * 420e6
    var block = tension / (0.85 * 30e6 * 0.3)
    var nominal = tension * (0.44 - block / 2)
    var peak = Float64(0)
    var at = 0
    for i in range(121):
        if curve[i].moment.to(NEWTON_METER) > peak:
            peak = curve[i].moment.to(NEWTON_METER)
            at = i
    assert_true(abs(peak / nominal - 1) < 0.03, String(peak, " ", nominal))
    var kappa = curve[at].curvature.to(PER_METER)
    var top = curve[at].strain - kappa * 0.25
    var steel = curve[at].strain + kappa * 0.19
    assert_true(steel > 420e6 / 200e9, String(steel))
    assert_true(top < -0.002 and top > -0.006, String(top))
    # The first slope is the stiffness of the cracked section, which is
    # below that of the whole concrete section.
    var first = curve[1].moment.to(NEWTON_METER) / curve[1].curvature.to(
        PER_METER
    )
    assert_true(first < 30e9 * 0.3 * 0.125 / 12)


def test_section_response_sums_the_fibers() raises:
    """One steel fiber and one concrete fiber at a strain and a curvature."""
    var section = FiberSection()
    section.add_steel(_m(-0.2), Area64(1e-3, SQUARE_METER), _steel(400e6))
    section.add_concrete_patch(_m(0.1), _m(0.3), _m(0.5), 1, _concrete())
    var response = section_response(section, [BarState(0, 0)], -0.0002, 0.004)
    # The steel is at a strain of 0.0006 and the concrete at -0.001.
    var steel = 200e9 * 0.0006 * 1e-3
    var concrete = -22.5e6 * 0.1
    assert_almost_equal(response.axial, steel + concrete, atol=1e-6)
    assert_almost_equal(
        response.moment, steel * 0.2 - concrete * 0.2, atol=1e-6
    )
    assert_almost_equal(
        response.axial_stiffness, 200e9 * 1e-3 + 15e9 * 0.1, atol=1e-3
    )
    assert_almost_equal(response.size, steel - concrete, atol=1e-6)
    assert_equal(len(response.steel), 1)
    with assert_raises(contains="one state"):
        _ = section_response(section, List[BarState](), 0, 0)


def test_section_refusals() raises:
    var section = FiberSection()
    var none = Force64(0, NEWTON)
    with assert_raises(contains="one fiber or more"):
        _ = moment_curvature(section, none, _kappa(1), 2, 1e-9)
    var bad = nan[DType.float64]()
    var law = _steel(250e6)
    var area = Area64(1e-4, SQUARE_METER)
    with assert_raises(contains="fiber height"):
        section.add_steel(_m(bad), area, law)
    with assert_raises(contains="fiber area"):
        section.add_steel(_m(0), Area64(0, SQUARE_METER), law)
    with assert_raises(contains="patch edge"):
        section.add_steel_patch(_m(bad), _m(1), _m(1), 2, law)
    with assert_raises(contains="patch edge"):
        section.add_steel_patch(_m(0), _m(bad), _m(1), 2, law)
    with assert_raises(contains="above its bottom"):
        section.add_steel_patch(_m(1), _m(1), _m(1), 2, law)
    with assert_raises(contains="patch width"):
        section.add_concrete_patch(_m(0), _m(1), _m(0), 2, _concrete())
    with assert_raises(contains="one layer"):
        section.add_concrete_patch(_m(0), _m(1), _m(1), 0, _concrete())
    with assert_raises(contains="more layers"):
        section.add_concrete_patch(_m(0), _m(1), _m(1), 1048577, _concrete())
    section.add_steel(_m(0), area, law)
    with assert_raises(contains="axial force must be finite"):
        _ = moment_curvature(section, Force64(bad, NEWTON), _kappa(1), 2, 1e-9)
    with assert_raises(contains="last curvature"):
        _ = moment_curvature(section, none, _kappa(0), 2, 1e-9)
    with assert_raises(contains="step count must be positive"):
        _ = moment_curvature(section, none, _kappa(1), 0, 1e-9)
    with assert_raises(contains="larger"):
        _ = moment_curvature(section, none, _kappa(1), 1048577, 1e-9)
    with assert_raises(contains="tolerance"):
        _ = moment_curvature(section, none, _kappa(1), 2, 0)
    # A tension above the yield force of the one fiber has no strain.
    with assert_raises(contains="finds no axial strain"):
        _ = moment_curvature(
            section, Force64(30e3, NEWTON), _kappa(1e-3), 2, 1e-9
        )
    # A concrete section cannot carry a tension at all.
    var plain = FiberSection()
    plain.add_concrete_patch(_m(0), _m(1), _m(1), 4, _concrete())
    with assert_raises(contains="finds no axial strain"):
        _ = moment_curvature(plain, Force64(1, NEWTON), _kappa(1e-3), 2, 1e-9)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
