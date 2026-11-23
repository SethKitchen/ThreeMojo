# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the nonlinear time history of `extensions.structure`.

The references are tables E5.3 and E5.5 of Chopra, "Dynamics of
Structures", 4th edition: a system with a mass of 0.2533, a stiffness of
10 and 5% damping under a half-cycle sine pulse, at a step of 0.1 with
the average acceleration method. In table E5.3 the system is linear. In
table E5.5 it is elastoplastic with a yield force of 7.5.
"""

from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.structure.dynamic import (
    NewmarkMethod,
    RayleighDamping,
    average_acceleration,
    no_damping,
)
from extensions.structure.ids import MemberId, NodeId
from extensions.structure.kinds import UX, UY, UZ
from extensions.structure.nonlinear import (
    NewtonOptions,
    assemble_truss,
    SteelLaw,
    TrussModel,
    TrussState,
    default_newton,
)
from extensions.structure.transient import dynamic_step, start_motion
from generators.utils import Vec3d
from units.si import (
    Area64,
    Duration64,
    Force64,
    KILOGRAM,
    Mass64,
    NEWTON,
    PASCAL,
    Pressure64,
    SECOND,
    SQUARE_METER,
)


def _s(v: Float64) -> Duration64:
    return Duration64(v, SECOND)


def _oscillator(yield_force: Float64) raises -> TrussModel:
    """One bar with a stiffness of 10 and a mass of 0.2533 at its end.

    The numbers are those of Chopra, in any consistent units. A bar of
    1 m with an area of 1 m² and a modulus of 10 Pa has a stiffness of
    10 N/m.
    """
    var model = TrussModel()
    var base = model.add_node(Vec3d(0, 0, 0))
    var end = model.add_node(Vec3d(1, 0, 0))
    model.add_support(base, [UX, UY, UZ])
    model.add_support(end, [UY, UZ])
    var law = SteelLaw(
        Pressure64(10, PASCAL), Pressure64(yield_force, PASCAL), 0
    )
    _ = model.add_bar(base, end, Area64(1, SQUARE_METER), law)
    model.add_load(end, UX, Force64(10, NEWTON))
    model.add_mass(end, Mass64(0.2533, KILOGRAM))
    return model^


def _pulse(step: Int) -> Float64:
    """Chopra's half-cycle sine pulse at a step, over its peak of 10."""
    var half = sqrt(3.0) / 2
    var values = [0.0, 0.5, half, 1.0, half, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0]
    return values[step]


def _run(
    model: TrussModel, damping: RayleighDamping, steps: Int
) raises -> List[Float64]:
    """Return the displacement of the oscillator after each step."""
    var state = TrussState(model)
    var motion = start_motion(model, state)
    var out = List[Float64]()
    for step in range(1, steps + 1):
        dynamic_step(
            model,
            state,
            motion,
            _pulse(step),
            _s(0.1),
            average_acceleration(),
            damping,
            default_newton(),
        )
        out.append(state.displacements[3])
    assert_almost_equal(motion.time, 0.1 * Float64(steps), atol=1e-12)
    return out^


def test_elastoplastic_system_meets_chopra() raises:
    """An elastoplastic system that yields at a force of 7.5.

    Reference: Chopra, table E5.5, the displacements at the first nine
    steps, to the four decimals of the table. The system yields in the
    fourth step and unloads after the seventh.
    """
    var expected = [
        0.0437,
        0.2326,
        0.6121,
        1.1143,
        1.6214,
        1.9891,
        2.0951,
        1.9240,
        1.5602,
    ]
    var omega = sqrt(10 / 0.2533)
    var got = _run(_oscillator(7.5), RayleighDamping(2 * 0.05 * omega, 0), 9)
    for i in range(9):
        assert_almost_equal(got[i], expected[i], atol=2e-4)


def test_linear_system_meets_chopra() raises:
    """The same system with no yield, by both kinds of damping.

    Reference: Chopra, table E5.3. The damping 2 ζ m ω is given first as
    a mass factor and then as a stiffness factor.
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
    var by_mass = _run(
        _oscillator(1e9), RayleighDamping(2 * 0.05 * omega, 0), 10
    )
    var by_stiffness = _run(
        _oscillator(1e9), RayleighDamping(0, 2 * 0.05 / omega), 10
    )
    for i in range(10):
        assert_almost_equal(by_mass[i], expected[i], atol=1.5e-4)
        assert_almost_equal(by_stiffness[i], by_mass[i], atol=1e-10)


def test_elastic_chain_keeps_its_energy() raises:
    """Two bars and two masses in a line, under a constant load.

    Reference: with the average acceleration method and no damping, the
    kinetic energy plus the strain energy less the work of the load stays
    at zero. The start acceleration is the load over the mass.
    """
    var model = TrussModel()
    var law = SteelLaw(Pressure64(200e9, PASCAL), Pressure64(1e15, PASCAL), 0)
    var area = Area64(1e-3, SQUARE_METER)
    var a = model.add_node(Vec3d(0, 0, 0))
    var b = model.add_node(Vec3d(2, 0, 0))
    var c = model.add_node(Vec3d(4, 0, 0))
    model.add_support(a, [UX, UY, UZ])
    model.add_support(b, [UY, UZ])
    model.add_support(c, [UY, UZ])
    _ = model.add_bar(a, b, area, law)
    _ = model.add_bar(b, c, area, law)
    model.add_load(c, UX, Force64(50e3, NEWTON))
    model.add_mass(b, Mass64(2000, KILOGRAM))
    model.add_mass(c, Mass64(1000, KILOGRAM))
    var state = TrussState(model)
    state.load_factor = 1
    var motion = start_motion(model, state)
    assert_almost_equal(motion.accelerations[6], 50.0, atol=1e-12)
    assert_almost_equal(motion.accelerations[3], 0.0, atol=0)
    var stiffness = 200e9 * 1e-3 / 2
    var worst = Float64(0)
    var largest = Float64(0)
    for _ in range(200):
        dynamic_step(
            model,
            state,
            motion,
            1,
            _s(0.002),
            average_acceleration(),
            no_damping(),
            default_newton(),
        )
        var ub = state.displacements[3]
        var uc = state.displacements[6]
        var kinetic = (
            0.5 * 2000 * motion.velocities[3] ** 2
            + 0.5 * 1000 * motion.velocities[6] ** 2
        )
        var strain = 0.5 * stiffness * (ub * ub + (uc - ub) * (uc - ub))
        worst = max(worst, abs(kinetic + strain - 50e3 * uc))
        largest = max(largest, strain)
    assert_true(largest > 1)
    assert_true(worst < 1e-9 * largest, String(worst, " ", largest))
    assert_true(state.iterations <= 2)


def test_transient_refusals() raises:
    var model = _oscillator(7.5)
    var state = TrussState(model)
    var motion = start_motion(model, state)
    var method = average_acceleration()
    var damping = no_damping()
    var options = default_newton()
    with assert_raises(contains="load factor"):
        dynamic_step(
            model,
            state,
            motion,
            nan[DType.float64](),
            _s(0.1),
            method,
            damping,
            options,
        )
    with assert_raises(contains="time step"):
        dynamic_step(model, state, motion, 0, _s(0), method, damping, options)
    with assert_raises(contains="gamma"):
        dynamic_step(
            model,
            state,
            motion,
            0,
            _s(0.1),
            NewmarkMethod(0.5, 0),
            damping,
            options,
        )
    with assert_raises(contains="damping factor"):
        dynamic_step(
            model,
            state,
            motion,
            0,
            _s(0.1),
            method,
            RayleighDamping(-1, 0),
            options,
        )
    # One iteration cannot pass a yield point.
    with assert_raises(contains="did not converge"):
        dynamic_step(
            model,
            state,
            motion,
            50,
            _s(0.1),
            method,
            damping,
            NewtonOptions(1e-12, 1),
        )
    assert_almost_equal(motion.time, 0.0, atol=0)
    assert_almost_equal(state.load_factor, 0.0, atol=0)
    var other = TrussModel()
    _ = other.add_node(Vec3d(0, 0, 0))
    var lone = TrussState(other)
    with assert_raises(contains="motion does not fit"):
        dynamic_step(other, lone, motion, 0, _s(0.1), method, damping, options)
    with assert_raises(contains="needs a mass"):
        _ = start_motion(other, TrussState(other))
    with assert_raises(contains="does not fit"):
        _ = start_motion(model, TrussState(other))
    with assert_raises(contains="mass must be zero or more"):
        model.add_mass(NodeId(1), Mass64(-1, KILOGRAM))
    with assert_raises(contains="mass must be zero or more"):
        model.add_mass(NodeId(1), Mass64(inf[DType.float64](), KILOGRAM))
    with assert_raises(contains="node id"):
        model.add_mass(NodeId(7), Mass64(1, KILOGRAM))
    with assert_raises(contains="displacements do not fit"):
        _ = assemble_truss(model, state, [0.0])
    var tangent = assemble_truss(model, state, state.displacements)
    assert_almost_equal(tangent.matrix.get(0, 0), 10.0, atol=1e-12)
    assert_equal(len(tangent.internal), 6)
    # A model with no node has an empty tangent and an empty motion.
    var empty = TrussModel()
    var nothing = TrussState(empty)
    assert_equal(assemble_truss(empty, nothing, List[Float64]()).matrix.size, 0)
    assert_equal(len(start_motion(empty, nothing).velocities), 0)
    # A negative stiffness with a mass that cancels it is singular.
    var odd = _oscillator(7.5)
    var odd_state = TrussState(odd)
    var odd_motion = start_motion(odd, odd_state)
    odd_motion.mass.values[0] = -10 * 0.25 * 0.01
    with assert_raises(contains="singular"):
        dynamic_step(
            odd, odd_state, odd_motion, 1, _s(0.1), method, damping, options
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
