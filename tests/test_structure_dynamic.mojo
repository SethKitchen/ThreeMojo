# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the time-history analysis of `extensions.structure`.

The single-degree references are tables E5.3 and E5.4 of Chopra,
"Dynamics of Structures", 4th edition: a half-cycle sine pulse on a
system with a mass of 0.2533, a stiffness of 10 and 5% damping, at a step
of 0.1. The two-degree reference is the modal solution of an undamped
system under a step load. The model references are the closed form of an
undamped oscillator and the static solution that a damped model settles
to.
"""

from std.math import cos, inf, nan, pi, sqrt
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
from extensions.numerics.sparse import CsrMatrix, SparseBuilder
from extensions.structure.dynamic import (
    GroundMotion,
    HistoryOptions,
    NewmarkMethod,
    RayleighDamping,
    TimeSeries,
    average_acceleration,
    combine,
    constant_series,
    linear_acceleration,
    newmark,
    no_damping,
    rayleigh_damping,
    solve_ground_motion,
    solve_load_history,
)
from extensions.structure.ids import LoadCaseId, NodeId
from extensions.structure.kinds import RX, RY, RZ, UX, UY, UZ
from extensions.structure.modal import solve_modes
from extensions.structure.model import StructuralModel
from extensions.structure.static import solve_static
from generators.utils import Vec3d
from units.si import (
    Acceleration64,
    Duration64,
    Force64,
    Frequency64,
    Length64,
    METER,
    METER_PER_SECOND_SQUARED,
    NEWTON,
    PER_SECOND,
    SECOND,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _s(v: Float64) -> Duration64:
    return Duration64(v, SECOND)


def _one(value: Float64) raises -> CsrMatrix:
    """A 1 by 1 matrix."""
    var builder = SparseBuilder(1)
    builder.add(0, 0, value)
    return builder.build()


def _pulse() raises -> TimeSeries:
    """Chopra's half-cycle sine pulse, as a factor of its peak of 10."""
    var half = sqrt(3.0) / 2
    return TimeSeries(
        _s(0.1), [0.0, 0.5, half, 1.0, half, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0]
    )


def _chopra(
    method: NewmarkMethod, damping: RayleighDamping
) raises -> List[Float64]:
    """Return the ten displacements of Chopra's example 5.3."""
    var response = newmark(
        _one(10),
        _one(0.2533),
        [10.0],
        _pulse(),
        HistoryOptions(_s(0.1), 10, method, damping),
    )
    var out = List[Float64]()
    for i in range(1, 11):
        out.append(response.displacements[i][0])
    return out^


def test_average_acceleration_table() raises:
    """The constant average acceleration method on one degree of freedom.

    Reference: Chopra, table E5.3, to the four decimals of the table. The
    damping is c = 2 ζ m ω, first as a mass factor and then as a
    stiffness factor of the same value.
    """
    var expected = [
        0.0437,
        0.2326,
        0.6121,
        1.0825,
        1.4309,
        1.4231,
        0.9622,
        0.1908,
        -0.6044,
        -1.1442,
    ]
    var omega = sqrt(10 / 0.2533)
    var by_mass = _chopra(
        average_acceleration(), RayleighDamping(2 * 0.05 * omega, 0)
    )
    var by_stiffness = _chopra(
        average_acceleration(), RayleighDamping(0, 2 * 0.05 / omega)
    )
    for i in range(10):
        assert_almost_equal(by_mass[i], expected[i], atol=1.5e-4)
        assert_almost_equal(by_stiffness[i], by_mass[i], atol=1e-12)


def test_linear_acceleration_table() raises:
    """The linear acceleration method on one degree of freedom.

    Reference: Chopra, table E5.4, to the four decimals of the table.
    """
    var expected = [
        0.0300,
        0.2193,
        0.6166,
        1.1130,
        1.4782,
        1.4625,
        0.9514,
        0.1273,
        -0.6954,
        -1.2208,
    ]
    var omega = sqrt(10 / 0.2533)
    var got = _chopra(
        linear_acceleration(), RayleighDamping(2 * 0.05 * omega, 0)
    )
    for i in range(10):
        assert_almost_equal(got[i], expected[i], atol=1e-4)


def _two_story() raises -> CsrMatrix:
    """The stiffness [[2, -1], [-1, 1]] of a two-story shear building."""
    var builder = SparseBuilder(2)
    builder.add(0, 0, 2)
    builder.add(0, 1, -1)
    builder.add(1, 0, -1)
    builder.add(1, 1, 1)
    return builder.build()


def _unit_mass() raises -> CsrMatrix:
    var builder = SparseBuilder(2)
    builder.add(0, 0, 1)
    builder.add(1, 1, 1)
    return builder.build()


def _two_story_exact(time: Float64) -> Float64:
    """The roof displacement under a unit step load at the roof.

    The squared frequencies are (3 ∓ √5) / 2. The shapes are
    (1, (1 ± √5) / 2), not yet normalized.
    """
    var total = Float64(0)
    var signs = [1.0, -1.0]
    for i in range(2):
        var w2 = (3 - signs[i] * sqrt(5.0)) / 2
        var top = (1 + signs[i] * sqrt(5.0)) / 2
        var norm = 1 + top * top
        total += top * top / (norm * w2) * (1 - cos(sqrt(w2) * time))
    return total


def _two_story_error(step: Float64, steps: Int) raises -> Float64:
    var response = newmark(
        _two_story(),
        _unit_mass(),
        [0.0, 1.0],
        constant_series(_s(100)),
        HistoryOptions(_s(step), steps, average_acceleration(), no_damping()),
    )
    var worst = Float64(0)
    for i in range(steps + 1):
        var exact = _two_story_exact(Float64(i) * step)
        worst = max(worst, abs(response.displacements[i][1] - exact))
    return worst


def test_two_degrees_converge_at_second_order() raises:
    """A step load on two degrees of freedom against the modal solution.

    Reference: u(t) = Σ φ (φᵀ s / ω²) (1 - cos ω t). Halving the step
    must cut the error by four, within 10%, and the fine step must be
    within 2e-3.
    """
    var coarse = _two_story_error(0.1, 100)
    var fine = _two_story_error(0.05, 200)
    assert_true(abs(coarse / fine - 4) < 0.4, String(coarse, " ", fine))
    assert_true(fine < 2e-3, String(fine))


def test_average_acceleration_keeps_energy() raises:
    """The energy of an undamped system under a constant load.

    Reference: with γ = 1/2 and β = 1/4 the sum of the kinetic energy,
    the strain energy and the potential of the load stays at its start
    value of zero, for any step.
    """
    var k = _two_story()
    var m = _unit_mass()
    var response = newmark(
        k,
        m,
        [0.0, 1.0],
        constant_series(_s(1000)),
        HistoryOptions(_s(0.7), 300, average_acceleration(), no_damping()),
    )
    var worst = Float64(0)
    for i in range(301):
        var u = response.displacements[i].copy()
        var v = response.velocities[i].copy()
        var ku = k.multiply(u)
        var energy = 0.5 * (v[0] * v[0] + v[1] * v[1]) - u[1]
        energy += 0.5 * (u[0] * ku[0] + u[1] * ku[1])
        worst = max(worst, abs(energy))
    assert_true(worst < 1e-11, String(worst))
    # The first acceleration solves M a = s.
    assert_almost_equal(response.accelerations[0][1], 1.0, atol=1e-15)
    assert_almost_equal(response.step, 0.7, atol=0)


def test_series() raises:
    """A series interpolates, ends at its last value and is zero outside."""
    var series = TimeSeries(_s(0.5), [1.0, 3.0, 2.0])
    assert_almost_equal(series.at(-0.1), 0.0, atol=0)
    assert_almost_equal(series.at(nan[DType.float64]()), 0.0, atol=0)
    assert_almost_equal(series.at(0), 1.0, atol=0)
    assert_almost_equal(series.at(0.25), 2.0, atol=1e-15)
    assert_almost_equal(series.at(0.75), 2.5, atol=1e-15)
    assert_almost_equal(series.at(1.0), 2.0, atol=0)
    assert_almost_equal(series.at(1.01), 0.0, atol=0)
    with assert_raises(contains="interval"):
        _ = TimeSeries(_s(0), [1.0])
    with assert_raises(contains="interval"):
        _ = TimeSeries(_s(inf[DType.float64]()), [1.0])
    with assert_raises(contains="at least one"):
        _ = TimeSeries(_s(1), List[Float64]())
    with assert_raises(contains="finite"):
        _ = TimeSeries(_s(1), [nan[DType.float64]()])
    with assert_raises(contains="interval"):
        _ = constant_series(_s(-1))


def test_methods_and_damping() raises:
    """The validity of each method and each damping."""
    assert_true(average_acceleration().is_valid())
    assert_true(average_acceleration().is_usable())
    # The linear acceleration method is conditionally stable.
    assert_false(linear_acceleration().is_valid())
    assert_true(linear_acceleration().is_usable())
    assert_false(NewmarkMethod(0.4, 0.25).is_valid())
    assert_false(NewmarkMethod(0.4, 0.25).is_usable())
    assert_false(NewmarkMethod(0.5, 0).is_usable())
    var bad = nan[DType.float64]()
    assert_false(NewmarkMethod(bad, 0.25).is_valid())
    assert_false(NewmarkMethod(0.5, bad).is_valid())
    assert_false(NewmarkMethod(bad, 0.25).is_usable())
    assert_false(NewmarkMethod(0.5, bad).is_usable())
    assert_true(no_damping().is_valid())
    assert_false(RayleighDamping(-1, 0).is_valid())
    assert_false(RayleighDamping(0, -1).is_valid())
    assert_false(RayleighDamping(bad, 0).is_valid())
    assert_false(RayleighDamping(0, bad).is_valid())
    # 5% at 1 Hz and 4 Hz: a = 2 ζ ω₁ ω₂ / (ω₁ + ω₂), b = 2 ζ / (ω₁ + ω₂).
    var damping = rayleigh_damping(
        0.05, Frequency64(1, PER_SECOND), Frequency64(4, PER_SECOND)
    )
    assert_almost_equal(damping.mass_factor, 0.16 * pi, atol=1e-15)
    assert_almost_equal(damping.stiffness_factor, 0.01 / pi, atol=1e-15)
    # The ratio a / (2 ω) + b ω / 2 is 5% at each of the two.
    for f in [1.0, 4.0]:
        var w = 2 * pi * f
        var ratio = (
            damping.mass_factor / (2 * w) + damping.stiffness_factor * w / 2
        )
        assert_almost_equal(ratio, 0.05, atol=1e-15)
    with assert_raises(contains="ratio"):
        _ = rayleigh_damping(
            -0.1, Frequency64(1, PER_SECOND), Frequency64(4, PER_SECOND)
        )
    with assert_raises(contains="frequency"):
        _ = rayleigh_damping(
            0.1, Frequency64(0, PER_SECOND), Frequency64(4, PER_SECOND)
        )
    with assert_raises(contains="frequency"):
        _ = rayleigh_damping(
            0.1, Frequency64(1, PER_SECOND), Frequency64(bad, PER_SECOND)
        )
    with assert_raises(contains="frequency"):
        _ = rayleigh_damping(
            0.1,
            Frequency64(inf[DType.float64](), PER_SECOND),
            Frequency64(1, PER_SECOND),
        )
    with assert_raises(contains="frequency"):
        _ = rayleigh_damping(
            0.1, Frequency64(1, PER_SECOND), Frequency64(-1, PER_SECOND)
        )
    with assert_raises(contains="frequency"):
        _ = rayleigh_damping(
            0.1,
            Frequency64(1, PER_SECOND),
            Frequency64(inf[DType.float64](), PER_SECOND),
        )


def test_option_refusals() raises:
    var method = average_acceleration()
    var damping = no_damping()
    with assert_raises(contains="time step"):
        _ = HistoryOptions(_s(0), 1, method, damping)
    with assert_raises(contains="time step"):
        _ = HistoryOptions(_s(inf[DType.float64]()), 1, method, damping)
    with assert_raises(contains="step count"):
        _ = HistoryOptions(_s(1), 0, method, damping)
    with assert_raises(contains="larger"):
        _ = HistoryOptions(_s(1), 1048577, method, damping)
    with assert_raises(contains="gamma"):
        _ = HistoryOptions(_s(1), 1, NewmarkMethod(0.5, 0), damping)
    with assert_raises(contains="damping"):
        _ = HistoryOptions(_s(1), 1, method, RayleighDamping(-1, 0))
    var options = HistoryOptions(_s(0.5), 1048576, method, damping)
    assert_equal(options.steps, 1048576)


def test_combine() raises:
    """A sum of two matrices, each with an empty row."""
    var first = SparseBuilder(2)
    first.add(0, 0, 2)
    var second = SparseBuilder(2)
    second.add(1, 1, 3)
    var sum = combine(first.build(), second.build(), 10, 100)
    assert_almost_equal(sum.get(0, 0), 20.0, atol=0)
    assert_almost_equal(sum.get(1, 1), 300.0, atol=0)
    assert_equal(sum.nonzeros(), 2)
    with assert_raises(contains="same size"):
        _ = combine(_one(1), _unit_mass(), 1, 1)


def test_newmark_refusals() raises:
    var options = HistoryOptions(
        _s(0.1), 2, average_acceleration(), no_damping()
    )
    var series = constant_series(_s(1))
    with assert_raises(contains="load shape"):
        _ = newmark(_one(1), _one(1), [1.0, 2.0], series, options)
    with assert_raises(contains="same size"):
        _ = newmark(_one(1), _unit_mass(), [1.0], series, options)
    with assert_raises(contains="mass must be positive definite"):
        _ = newmark(_one(1), _one(-1), [1.0], series, options)
    with assert_raises(contains="effective stiffness"):
        _ = newmark(_one(-1000), _one(1), [1.0], series, options)
    # An empty system has an empty response at every step.
    var empty = newmark(
        SparseBuilder(0).build(),
        SparseBuilder(0).build(),
        List[Float64](),
        series,
        options,
    )
    assert_equal(len(empty.displacements), 3)
    assert_equal(len(empty.displacements[2]), 0)


def _bar() raises -> StructuralModel:
    """A 2 m steel bar along x. Only the axial motion of its tip is free."""
    var model = StructuralModel()
    var base = model.add_node(Vec3d(0, 0, 0))
    var tip = model.add_node(Vec3d(2, 0, 0))
    model.fix(base)
    model.add_support(tip, [UY, UZ, RX, RY, RZ])
    _ = model.add_member(
        base, tip, rectangle(_m(0.1), _m(0.2)), steel(), Vec3d(0, 0, 1)
    )
    return model^


def test_bar_under_step_load() raises:
    """A bar with one free degree of freedom under a step load.

    Reference: u(t) = (P / k) (1 - cos ω t), with k = E A / L and the
    consistent mass m = ρ A L / 3. A step of 1/200 of the period is within
    0.1% of P / k at every time, and the peak is twice the static value.
    """
    var model = _bar()
    var push = model.add_load_case("push")
    model.add_force(push, NodeId(1), UX, Force64(1000, NEWTON))
    var k = 200e9 * 0.02 / 2
    var mass = 7850 * 0.02 * 2 / 3
    var omega = sqrt(k / mass)
    var step = 2 * pi / omega / 200
    var history = solve_load_history(
        model,
        push,
        constant_series(_s(1)),
        HistoryOptions(_s(step), 400, average_acceleration(), no_damping()),
    )
    assert_equal(history.count(), 401)
    var static_value = 1000 / k
    for i in range(401):
        var exact = static_value * (1 - cos(omega * Float64(i) * step))
        var got = history.translation(i, NodeId(1), UX).to(METER)
        assert_true(abs(got - exact) < 1e-3 * static_value, String(i))
    var peak = history.peak_translation(NodeId(1), UX).to(METER)
    assert_true(abs(peak / (2 * static_value) - 1) < 1e-3, String(peak))
    assert_almost_equal(history.time(400).to(SECOND), 400 * step, atol=1e-15)
    # The fixed node does not move.
    assert_almost_equal(
        history.peak_translation(NodeId(0), UX).to(METER), 0.0, atol=0
    )
    assert_almost_equal(history.velocities[0][6], 0.0, atol=0)
    assert_almost_equal(history.accelerations[0][6], 1000 / mass, atol=1e-9)


def _cantilever(pieces: Int) raises -> StructuralModel:
    """A 3 m steel cantilever along x that moves in the x-z plane."""
    var model = StructuralModel()
    for i in range(pieces + 1):
        var node = model.add_node(Vec3d(3 * Float64(i) / Float64(pieces), 0, 0))
        model.add_support(node, [UY, RX, RZ])
    model.fix(NodeId(0))
    for i in range(pieces):
        _ = model.add_member(
            NodeId(i),
            NodeId(i + 1),
            rectangle(_m(0.1), _m(0.2)),
            steel(),
            Vec3d(0, 0, 1),
        )
    return model^


def test_ground_motion_settles_to_static() raises:
    """A cantilever on ground that accelerates up at a constant g.

    Reference: the effective load -M r g of a consistent mass is the
    consistent load of the self-weight. With critical damping at the
    first frequency, the relative motion settles to the static deflection
    under self-weight, within 1e-8.
    """
    var model = _cantilever(4)
    var first = solve_modes(model, 1).frequencies[0]
    var motion = GroundMotion(
        UZ,
        constant_series(_s(1000)),
        Acceleration64(9.80665, METER_PER_SECOND_SQUARED),
    )
    var period = 1 / first.to(PER_SECOND)
    var history = solve_ground_motion(
        model,
        motion,
        HistoryOptions(
            _s(period / 20),
            400,
            average_acceleration(),
            rayleigh_damping(1, first, first),
        ),
    )
    var weight = model.add_load_case("weight")
    model.add_self_weight(
        weight, Acceleration64(9.80665, METER_PER_SECOND_SQUARED)
    )
    var expected = solve_static(model, weight).translation(NodeId(4), UZ)
    var got = history.translation(400, NodeId(4), UZ)
    assert_true(expected.to(METER) < 0)
    assert_true(
        abs(got.to(METER) / expected.to(METER) - 1) < 1e-8,
        String(got.to(METER), " ", expected.to(METER)),
    )


def test_history_refusals() raises:
    var model = _bar()
    var push = model.add_load_case("push")
    var options = HistoryOptions(
        _s(1e-4), 2, average_acceleration(), no_damping()
    )
    var series = constant_series(_s(1))
    var history = solve_load_history(model, push, series, options)
    with assert_raises(contains="history index"):
        _ = history.time(-1)
    with assert_raises(contains="history index"):
        _ = history.time(3)
    with assert_raises(contains="history index"):
        _ = history.translation(3, NodeId(1), UX)
    with assert_raises(contains="UX, UY or UZ"):
        _ = history.translation(0, NodeId(1), RX)
    with assert_raises(contains="node id"):
        _ = history.translation(0, NodeId(-1), UX)
    with assert_raises(contains="node id"):
        _ = history.peak_translation(NodeId(2), UX)
    with assert_raises(contains="load case"):
        _ = solve_load_history(model, LoadCaseId(4), series, options)
    with assert_raises(contains="translation"):
        _ = GroundMotion(
            RY, series.copy(), Acceleration64(1, METER_PER_SECOND_SQUARED)
        )
    with assert_raises(contains="scale"):
        _ = GroundMotion(
            UX,
            series.copy(),
            Acceleration64(inf[DType.float64](), METER_PER_SECOND_SQUARED),
        )
    var loose = _cantilever(2)
    loose.fixed[0] = False
    loose.fixed[2] = False
    loose.fixed[4] = False
    var shake = GroundMotion(
        UX, series.copy(), Acceleration64(1, METER_PER_SECOND_SQUARED)
    )
    with assert_raises(contains="mechanism"):
        _ = solve_ground_motion(loose, shake, options)
    # A model with no node has a history with no entry per time.
    var empty = solve_ground_motion(StructuralModel(), shake, options)
    assert_equal(empty.count(), 3)
    assert_equal(len(empty.displacements[0]), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
