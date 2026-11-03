# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the binary solutions of `extensions.chemistry`.

Each result is checked against a closed form that the hull method does
not use:

- A symmetric regular solution with parameter W has a miscibility gap
  below Tc = W / (2 R). Its edges solve ln(x / (1 - x)) = W (2x - 1) /
  (R T).
- Two ideal phases form a lens. With k_i = exp((Gs_i - Gl_i) / R T), the
  solidus is (1 - k1) / (k2 - k1) and the liquidus k2 times that.
- An activity coefficient is the partial molar excess energy, which a
  finite difference of the excess energy gives.
"""

from std.math import exp, inf, log, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.chemistry.quantities import MolarEnergy64, MolarEntropy64
from extensions.chemistry.solution import (
    Linear,
    PhaseModel,
    TieLine,
    phase_boundaries,
)
from units.temperature import Temperature64

comptime R = 8.31446261815324


def _t(kelvin: Float64) -> Temperature64:
    return Temperature64(kelvin)


def _linear(a: Float64, b: Float64) -> Linear:
    return Linear(MolarEnergy64(a), MolarEntropy64(b))


def _zero() -> Linear:
    return _linear(0, 0)


def _regular(w: Float64) raises -> PhaseModel:
    var l: List[Linear] = [_linear(w, 0)]
    return PhaseModel("alpha", _zero(), _zero(), l^)


def _binodal(w: Float64, t: Float64) -> Float64:
    """The lower edge of a symmetric gap, by bisection."""
    var lo = 1e-12
    var hi = 0.5 - 1e-9
    for _ in range(200):
        var mid = 0.5 * (lo + hi)
        var f = log(mid / (1 - mid)) - w * (2 * mid - 1) / (R * t)
        if f < 0:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def test_miscibility_gap() raises:
    var w = 20000.0
    var phases: List[PhaseModel] = [_regular(w)]
    var lines = phase_boundaries(phases, _t(1000), 4000)
    assert_equal(len(lines), 1)
    var edge = _binodal(w, 1000)
    assert_almost_equal(lines[0].left, edge, atol=5e-4)
    assert_almost_equal(lines[0].right, 1 - edge, atol=5e-4)
    assert_equal(lines[0].left_phase, 0)
    assert_equal(lines[0].right_phase, 0)
    # Above Tc = W / 2R = 1202.7 K the gap closes.
    assert_equal(len(phase_boundaries(phases, _t(1300))), 0)


def test_ideal_lens() raises:
    # Two components that melt at 1500 K and 1000 K, each with an entropy
    # of fusion of 10 J/(mol K). The solid is the reference.
    var solid = PhaseModel("solid", _zero(), _zero(), List[Linear]())
    var liquid = PhaseModel(
        "liquid", _linear(15000, -10), _linear(10000, -10), List[Linear]()
    )
    var phases: List[PhaseModel] = [solid^, liquid^]
    var t = 1200.0
    var k1 = exp(-10 * (1500 - t) / (R * t))
    var k2 = exp(-10 * (1000 - t) / (R * t))
    var solidus = (1 - k1) / (k2 - k1)
    var lines = phase_boundaries(phases, _t(t), 4000)
    assert_equal(len(lines), 1)
    assert_equal(lines[0].left_phase, 0)
    assert_equal(lines[0].right_phase, 1)
    assert_almost_equal(lines[0].left, solidus, atol=5e-4)
    assert_almost_equal(lines[0].right, k2 * solidus, atol=5e-4)


def test_eutectic_structure() raises:
    # Two components that melt at 1200 K and do not mix in the solid.
    var solid = PhaseModel("solid", _zero(), _zero(), [_linear(30000, 0)])
    var liquid = PhaseModel(
        "liquid", _linear(12000, -10), _linear(12000, -10), List[Linear]()
    )
    var phases: List[PhaseModel] = [solid^, liquid^]
    # Just below the melting point: solid + liquid on each side.
    var hot = phase_boundaries(phases, _t(1150))
    assert_equal(len(hot), 2)
    assert_equal(hot[0].right_phase, 1)
    assert_equal(hot[1].left_phase, 1)
    assert_almost_equal(hot[0].right, 1 - hot[1].left, atol=1e-3)
    # Below the eutectic: two solids.
    var cold = phase_boundaries(phases, _t(700))
    assert_equal(len(cold), 1)
    assert_equal(cold[0].left_phase, 0)
    assert_equal(cold[0].right_phase, 0)


def _excess_derivative(
    phase: PhaseModel, x: Float64, t: Float64
) raises -> Float64:
    var h = 1e-6
    return (phase.excess(x + h, _t(t)) - phase.excess(x - h, _t(t))) / (2 * h)


def test_activity_coefficients() raises:
    var w = 12000.0
    var regular = _regular(w)
    var t = 900.0
    var x = 0.3
    assert_almost_equal(
        regular.log_gamma(1, x, _t(t)), w * x * x / (R * t), atol=1e-12
    )
    assert_almost_equal(
        regular.log_gamma(2, x, _t(t)), w * 0.49 / (R * t), atol=1e-12
    )
    assert_almost_equal(
        regular.activity(1, x, _t(t)),
        0.7 * exp(w * x * x / (R * t)),
        atol=1e-12,
    )
    # A three-term series against the finite difference of its excess.
    var rk = PhaseModel(
        "liquid",
        _zero(),
        _zero(),
        [_linear(-8000, 2), _linear(3000, 0), _linear(-1500, 1)],
    )
    var g = rk.excess(x, _t(t))
    var dg = _excess_derivative(rk, x, t)
    var mu1 = g - x * dg
    var mu2 = g + (1 - x) * dg
    assert_almost_equal(rk.log_gamma(1, x, _t(t)), mu1 / (R * t), atol=1e-7)
    assert_almost_equal(rk.log_gamma(2, x, _t(t)), mu2 / (R * t), atol=1e-7)
    assert_almost_equal(
        rk.activity(2, x, _t(t)), x * exp(mu2 / (R * t)), atol=1e-7
    )
    # An ideal solution has no excess: gamma is one.
    var ideal = PhaseModel("ideal", _zero(), _zero(), List[Linear]())
    assert_almost_equal(ideal.log_gamma(1, x, _t(t)), 0.0, atol=0)
    assert_almost_equal(ideal.activity(2, x, _t(t)), x, atol=0)
    # Pure end members have zero excess and an ideal mixing term of zero.
    assert_almost_equal(rk.gibbs(0, _t(t)), 0.0, atol=0)
    assert_almost_equal(rk.gibbs(1, _t(t)), 0.0, atol=0)


def test_bad_values() raises:
    var phase = _regular(1000)
    with assert_raises(contains="components 1 and 2"):
        _ = phase.log_gamma(3, 0.5, _t(1000))
    with assert_raises(contains="components 1 and 2"):
        _ = phase.log_gamma(0, 0.5, _t(1000))
    with assert_raises(contains="from 0 to 1"):
        _ = phase.log_gamma(1, 1.5, _t(1000))
    with assert_raises(contains="from 0 to 1"):
        _ = phase.excess(-0.1, _t(1000))
    with assert_raises(contains="finite and positive"):
        _ = phase.gibbs(0.5, _t(0))
    with assert_raises(contains="finite and positive"):
        _ = phase.gibbs(0.5, _t(inf[DType.float64]()))
    with assert_raises(contains="must be finite"):
        _ = PhaseModel(
            "x", _linear(nan[DType.float64](), 0), _zero(), List[Linear]()
        )
    with assert_raises(contains="must be finite"):
        _ = PhaseModel(
            "x", _zero(), _zero(), [_linear(0, inf[DType.float64]())]
        )
    with assert_raises(contains="needs a phase"):
        _ = phase_boundaries(List[PhaseModel](), _t(1000))
    var phases: List[PhaseModel] = [_regular(1000)]
    with assert_raises(contains="10 to 100000 samples"):
        _ = phase_boundaries(phases, _t(1000), 5)
    with assert_raises(contains="10 to 100000 samples"):
        _ = phase_boundaries(phases, _t(1000), 200000)
    with assert_raises(contains="finite and positive"):
        _ = phase_boundaries(phases, _t(-1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
