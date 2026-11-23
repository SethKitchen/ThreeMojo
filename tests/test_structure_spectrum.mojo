# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the response spectrum analysis of `extensions.structure`.

The references are the modal analysis of Chopra, "Dynamics of
Structures", 4th edition, chapter 13: one degree of freedom, and the
shear building of two equal storeys, whose squared frequencies are
(3 ∓ √5) k / (2 m) and whose modes are (1, (1 ± √5) / 2).
"""

from std.math import inf, nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.building.material import steel
from extensions.building.model import rectangle
from extensions.structure.ids import NodeId
from extensions.structure.kinds import RX, RY, RZ, UX, UY, UZ
from extensions.structure.model import StructuralModel
from extensions.structure.spectrum import (
    CQC,
    CombinationRule,
    ResponseSpectrum,
    SRSS,
    combine_modes,
    modal_correlation,
    solve_response_spectrum,
)
from generators.utils import Vec3d
from units.si import (
    Acceleration64,
    Duration64,
    KILOGRAM,
    Length64,
    METER,
    METER_PER_SECOND_SQUARED,
    Mass64,
    NEWTON,
    PER_SECOND,
    SECOND,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _g() -> Acceleration64:
    return Acceleration64(9.80665, METER_PER_SECOND_SQUARED)


def _flat(value: Float64) raises -> ResponseSpectrum:
    """A spectrum of one value, in units of g, at every period."""
    return ResponseSpectrum([0.0, 10.0], [value, value], _g())


def test_spectrum() raises:
    """A spectrum is linear between its periods and flat outside them."""
    var spectrum = ResponseSpectrum([0.1, 0.5, 2.0], [1.0, 2.5, 0.5], _g())
    var unit = METER_PER_SECOND_SQUARED
    var g = 9.80665
    assert_almost_equal(spectrum.at(Duration64(0.05)).to(unit), g, atol=1e-12)
    assert_almost_equal(spectrum.at(Duration64(0.1)).to(unit), g, atol=1e-12)
    assert_almost_equal(
        spectrum.at(Duration64(0.3)).to(unit), 1.75 * g, atol=1e-12
    )
    assert_almost_equal(
        spectrum.at(Duration64(0.5)).to(unit), 2.5 * g, atol=1e-12
    )
    assert_almost_equal(
        spectrum.at(Duration64(1.25)).to(unit), 1.5 * g, atol=1e-12
    )
    assert_almost_equal(
        spectrum.at(Duration64(2.0)).to(unit), 0.5 * g, atol=1e-12
    )
    assert_almost_equal(
        spectrum.at(Duration64(9.0)).to(unit), 0.5 * g, atol=1e-12
    )
    var bad = nan[DType.float64]()
    with assert_raises(contains="one period or more"):
        _ = ResponseSpectrum(List[Float64](), List[Float64](), _g())
    with assert_raises(contains="one period or more"):
        _ = ResponseSpectrum([1.0], [1.0, 2.0], _g())
    with assert_raises(contains="scale"):
        _ = ResponseSpectrum([1.0], [1.0], Acceleration64(0))
    with assert_raises(contains="scale"):
        _ = ResponseSpectrum([1.0], [1.0], Acceleration64(inf[DType.float64]()))
    with assert_raises(contains="ascend"):
        _ = ResponseSpectrum([1.0, 1.0], [1.0, 1.0], _g())
    with assert_raises(contains="ascend"):
        _ = ResponseSpectrum([-0.5, 1.0], [1.0, 1.0], _g())
    with assert_raises(contains="ascend"):
        _ = ResponseSpectrum([1.0, inf[DType.float64]()], [1.0, 1.0], _g())
    with assert_raises(contains="spectrum value"):
        _ = ResponseSpectrum([1.0], [-1.0], _g())
    with assert_raises(contains="spectrum value"):
        _ = ResponseSpectrum([1.0], [bad], _g())
    assert_true(SRSS.is_valid())
    assert_true(CQC.is_valid())
    assert_false(CombinationRule(2).is_valid())


def test_combination_rules() raises:
    """The two rules on peaks that the test gives.

    Reference: SRSS of 3 and 4 is 5. CQC is SRSS with no damping, and the
    absolute sum for two equal frequencies. For β = 0.9 and ζ = 5% the
    correlation of Der Kiureghian is 0.473.
    """
    var peaks: List[Float64] = [3.0, -4.0]
    var apart: List[Float64] = [1.0, 5.0]
    assert_almost_equal(
        combine_modes(peaks, apart, SRSS, 0.05), 5.0, atol=1e-12
    )
    assert_almost_equal(combine_modes(peaks, apart, CQC, 0), 5.0, atol=1e-12)
    # Peaks of opposite sign at one frequency cancel.
    var same: List[Float64] = [2.0, 2.0]
    assert_almost_equal(combine_modes(peaks, same, CQC, 0.05), 1.0, atol=1e-12)
    assert_almost_equal(combine_modes(peaks, same, CQC, 0), 1.0, atol=1e-12)
    var rho = modal_correlation(1.0, 0.9, 0.05)
    var expected = (
        8 * 0.0025 * 1.9 * 0.9**1.5 / (0.19 * 0.19 + 4 * 0.0025 * 0.9 * 3.61)
    )
    assert_almost_equal(rho, expected, atol=1e-15)
    assert_true(rho > 0.47 and rho < 0.48, String(rho))
    # The correlation is the same in both orders, and falls with the gap.
    assert_almost_equal(modal_correlation(0.9, 1.0, 0.05), rho, atol=1e-12)
    assert_true(modal_correlation(1.0, 0.5, 0.05) < 0.02)
    var close: List[Float64] = [1.0, 0.9]
    var both: List[Float64] = [3.0, 4.0]
    var one: List[Float64] = [1.0]
    assert_almost_equal(
        combine_modes(both, close, CQC, 0.05),
        sqrt(25 + 24 * rho),
        atol=1e-12,
    )
    assert_almost_equal(
        combine_modes(List[Float64](), List[Float64](), CQC, 0.05),
        0.0,
        atol=0,
    )
    with assert_raises(contains="combination rule"):
        _ = combine_modes(peaks, apart, CombinationRule(5), 0.05)
    with assert_raises(contains="one peak"):
        _ = combine_modes(peaks, one, SRSS, 0.05)
    with assert_raises(contains="damping ratio"):
        _ = combine_modes(peaks, apart, CQC, -0.05)


def _shear_building(storeys: Int) raises -> StructuralModel:
    """A stick of 3 m columns that sways along x only, with 5000 t floors.

    The floors do not turn, so each column has the stiffness
    12 E I / L³ of a 300 mm square steel bar.
    """
    var model = StructuralModel()
    var base = model.add_node(Vec3d(0, 0, 0))
    model.fix(base)
    for s in range(storeys):
        var floor = model.add_node(Vec3d(0, 0, 3 * Float64(s + 1)))
        model.add_support(floor, [UY, UZ, RX, RY, RZ])
        model.add_mass(floor, Mass64(5e6, KILOGRAM))
        _ = model.add_member(
            NodeId(s),
            floor,
            rectangle(_m(0.3), _m(0.3)),
            steel(),
            Vec3d(1, 0, 0),
        )
    return model^


def _column_stiffness() -> Float64:
    return 12 * 200e9 * (0.3**4 / 12) / 27


def test_one_degree_of_freedom() raises:
    """One floor on one column, under a spectrum of 0.4 g.

    Reference: the floor is the whole response. Its peak displacement is
    S_a / ω², with ω² = k / m, and the base shear is m S_a. The mass of
    the column changes them by under 0.05%.
    """
    var model = _shear_building(1)
    var result = solve_response_spectrum(model, _flat(0.4), UX, 1, SRSS, 0.05)
    var sa = 0.4 * 9.80665
    var omega2 = _column_stiffness() / 5e6
    var hertz = result.frequencies[0].to(PER_SECOND)
    assert_true(abs(hertz / (sqrt(omega2) / (2 * pi)) - 1) < 5e-4)
    var sway = result.translation(NodeId(1), UX).to(METER)
    assert_true(abs(sway / (sa / omega2) - 1) < 5e-4, String(sway))
    assert_true(abs(result.base_shear().to(NEWTON) / (5e6 * sa) - 1) < 5e-4)
    assert_true(abs(result.effective_mass(0).to(KILOGRAM) / 5e6 - 1) < 5e-4)
    assert_almost_equal(
        result.translation(NodeId(0), UX).to(METER), 0.0, atol=0
    )


def test_two_storey_shear_building() raises:
    """Two equal storeys under a spectrum of 0.3 g, by SRSS and by CQC.

    Reference: the modes (1, (1 ± √5) / 2) have the effective masses
    m (1 + φ)² / (1 + φ²): 1.8944 m and 0.1056 m. They add to the mass
    2 m. The base shear is S_a times the root of the sum of their
    squares. The roof moves by the root of the sum of the squares of
    Γ φ S_a / ω² of each mode. The frequencies are far apart, so CQC at
    5% damping is within 0.5% of SRSS.
    """
    var model = _shear_building(2)
    var result = solve_response_spectrum(model, _flat(0.3), UX, 2, SRSS, 0.05)
    var sa = 0.3 * 9.80665
    var m = 5e6
    var k = _column_stiffness()
    var masses = List[Float64]()
    var roofs = List[Float64]()
    var signs = [1.0, -1.0]
    for i in range(2):
        var top = (1 + signs[i] * sqrt(5.0)) / 2
        var omega2 = (3 - signs[i] * sqrt(5.0)) / 2 * k / m
        # With φ = (1, top) / sqrt(m (1 + top²)), Γ = m (1 + top) / norm.
        var effective = m * (1 + top) * (1 + top) / (1 + top * top)
        masses.append(effective)
        roofs.append((1 + top) * top / (1 + top * top) * sa / omega2)
        var hertz = result.frequencies[i].to(PER_SECOND)
        assert_true(abs(hertz / (sqrt(omega2) / (2 * pi)) - 1) < 5e-4)
        var got = result.effective_mass(i).to(KILOGRAM)
        assert_true(abs(got / effective - 1) < 2e-3, String(got))
        assert_true(abs(result.modal_shears[i] / (effective * sa) - 1) < 2e-3)
    assert_true(abs(masses[0] / m - 1.8944) < 1e-4)
    var total = result.effective_masses[0] + result.effective_masses[1]
    assert_true(abs(total / (2 * m) - 1) < 5e-4, String(total))
    var shear = sa * sqrt(masses[0] * masses[0] + masses[1] * masses[1])
    assert_true(abs(result.base_shear().to(NEWTON) / shear - 1) < 2e-3)
    var roof = sqrt(roofs[0] * roofs[0] + roofs[1] * roofs[1])
    var sway = result.translation(NodeId(2), UX).to(METER)
    assert_true(abs(sway / roof - 1) < 2e-3, String(sway, " ", roof))
    # The participation factors are the roots of the effective masses.
    assert_almost_equal(
        result.participation[0] * result.participation[0],
        result.effective_masses[0],
        atol=1e-6,
    )
    var complete = solve_response_spectrum(model, _flat(0.3), UX, 2, CQC, 0.05)
    var ratio = complete.base_shear().to(NEWTON) / result.base_shear().to(
        NEWTON
    )
    assert_true(abs(ratio - 1) < 5e-3 and ratio != 1, String(ratio))


def test_spectrum_refusals() raises:
    var model = _shear_building(2)
    var spectrum = _flat(0.3)
    with assert_raises(contains="translation"):
        _ = solve_response_spectrum(model, spectrum, RY, 1, SRSS, 0.05)
    with assert_raises(contains="combination rule"):
        _ = solve_response_spectrum(
            model, spectrum, UX, 1, CombinationRule(-1), 0.05
        )
    with assert_raises(contains="damping ratio"):
        _ = solve_response_spectrum(
            model, spectrum, UX, 1, CQC, nan[DType.float64]()
        )
    with assert_raises(contains="mode count"):
        _ = solve_response_spectrum(model, spectrum, UX, 3, SRSS, 0.05)
    var result = solve_response_spectrum(model, spectrum, UX, 1, SRSS, 0.05)
    with assert_raises(contains="UX, UY or UZ"):
        _ = result.translation(NodeId(1), RX)
    with assert_raises(contains="node id"):
        _ = result.translation(NodeId(3), UX)
    with assert_raises(contains="node id"):
        _ = result.translation(NodeId(-1), UX)
    with assert_raises(contains="mode is out of range"):
        _ = result.effective_mass(1)
    with assert_raises(contains="mode is out of range"):
        _ = result.effective_mass(-1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
