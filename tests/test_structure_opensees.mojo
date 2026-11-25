# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests of the truss and section solvers against OpenSeesPy 3.8.0.

`assets/opensees/make_opensees_reference.py` runs OpenSees on the models
of the nonlinear, transient and section tests, over paths longer than
their closed forms can check. Each test runs the same model with the
port and compares each step. Both programs iterate to round-off, so the
values agree to about ten digits.
"""

from std.math import sqrt
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from extensions.structure.dynamic import RayleighDamping, average_acceleration
from extensions.structure.ids import MemberId, NodeId
from extensions.structure.kinds import UX, UY, UZ
from extensions.structure.nonlinear import (
    SteelLaw,
    TrussModel,
    TrussState,
    default_newton,
    displacement_step,
)
from extensions.structure.section import (
    ConcreteLaw,
    FiberSection,
    moment_curvature,
)
from extensions.structure.transient import (
    dynamic_step,
    set_ground_motion_load,
    start_motion,
)
from generators.utils import Vec3d
from units.si import (
    Area64,
    Duration64,
    Force64,
    InverseLength64,
    KILOGRAM,
    Length64,
    METER,
    Mass64,
    NEWTON,
    NEWTON_METER,
    PASCAL,
    PER_METER,
    Pressure64,
    SECOND,
    SQUARE_METER,
)


def _rows(name: String) raises -> List[List[Float64]]:
    """Read the rows of one reference file.

    Args:
        name: The file in `assets/opensees`.

    Returns:
        The numbers of each line that is not a comment.

    Raises:
        Error: The file is missing or holds a word that is not a number.
    """
    var text = Path(String("assets/opensees/", name)).read_text()
    var rows = List[List[Float64]]()
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        var row = List[Float64]()
        for word in line.split():
            row.append(Float64(word))
        rows.append(row^)
    return rows^


def _close(
    got: Float64, expected: Float64, scale: Float64, what: String
) raises:
    """Check that two values agree to 1e-9 of a scale.

    Args:
        got: The value of the port.
        expected: The value of OpenSees.
        scale: The size of the values of the curve.
        what: The name of the value, for the message.

    Raises:
        Error: The values differ by more than 1e-9 of the scale.
    """
    assert_true(
        abs(got - expected) <= 1e-9 * scale,
        String(what, ": ", got, " against ", expected),
    )


def _steel(
    modulus: Float64, yield_stress: Float64, hardening: Float64
) raises -> SteelLaw:
    """Return a bilinear steel law.

    Args:
        modulus: Young's modulus, in pascals.
        yield_stress: The yield stress, in pascals.
        hardening: The modulus after yield over Young's modulus.

    Returns:
        The law.

    Raises:
        Error: A value is out of range.
    """
    return SteelLaw(
        Pressure64(modulus, PASCAL), Pressure64(yield_stress, PASCAL), hardening
    )


def test_three_bar_truss_on_a_cyclic_path() raises:
    """The three-bar truss with 1% hardening, down, up and down again.

    Reference: OpenSees Truss elements of Steel01 under DisplacementControl.
    The bars yield in tension, then in compression, then in tension again,
    so kinematic hardening sets each later yield.
    """
    var model = TrussModel()
    var joint = model.add_node(Vec3d(0, 0, 0))
    model.add_support(joint, [UY])
    var tops = [Vec3d(-2, 0, 2), Vec3d(0, 0, 2), Vec3d(2, 0, 2)]
    for i in range(3):
        var top = model.add_node(tops[i])
        model.add_support(top, [UX, UY, UZ])
        _ = model.add_bar(
            top, joint, Area64(1e-3, SQUARE_METER), _steel(200e9, 250e6, 0.01)
        )
    model.add_load(joint, UZ, Force64(-1, NEWTON))
    var state = TrussState(model)
    var rows = _rows("truss_cyclic.txt")
    assert_equal(len(rows), 34)
    var previous = Float64(0)
    for row in rows:
        displacement_step(
            model,
            state,
            joint,
            UZ,
            Length64(row[1] - previous, METER),
            default_newton(),
        )
        previous = row[1]
        _close(state.load_factor, row[0], 1e6, "load factor")
        for bar in range(3):
            _close(
                state.bar_force(MemberId(bar)).to(NEWTON),
                row[2 + bar],
                1e6,
                String("bar ", bar),
            )


def test_shallow_truss_snaps_like_corot_truss() raises:
    """The shallow truss of two corotational bars, through its snap.

    Reference: OpenSees corotTruss elements under DisplacementControl.
    """
    var model = TrussModel()
    var elastic = _steel(200e9, 1e15, 0)
    var left = model.add_node(Vec3d(-2, 0, 0))
    var right = model.add_node(Vec3d(2, 0, 0))
    var apex = model.add_node(Vec3d(0, 0, 0.2))
    model.add_support(left, [UX, UY, UZ])
    model.add_support(right, [UX, UY, UZ])
    model.add_support(apex, [UX, UY])
    _ = model.add_bar(left, apex, Area64(1e-3, SQUARE_METER), elastic)
    _ = model.add_bar(right, apex, Area64(1e-3, SQUARE_METER), elastic)
    model.add_load(apex, UZ, Force64(-1, NEWTON))
    model.set_corotational(True)
    var state = TrussState(model)
    var rows = _rows("truss_snap.txt")
    assert_equal(len(rows), 50)
    for row in rows:
        displacement_step(
            model,
            state,
            apex,
            UZ,
            Length64(-0.01, METER),
            default_newton(),
        )
        _close(state.translation(apex, UZ).to(METER), row[1], 1, "sag")
        _close(state.load_factor, row[0], 1e5, "load factor")
        _close(state.bar_force(MemberId(0)).to(NEWTON), row[2], 1e6, "force")


def test_elastoplastic_oscillator_over_many_cycles() raises:
    """Chopra's elastoplastic oscillator under a harmonic force for 30 s.

    Reference: OpenSees Newmark with γ = 1/2 and β = 1/4, a Truss of
    Steel01 with no hardening, and mass-proportional Rayleigh damping.
    The oscillator yields in both directions many times.
    """
    var model = TrussModel()
    var base = model.add_node(Vec3d(0, 0, 0))
    var end = model.add_node(Vec3d(1, 0, 0))
    model.add_support(base, [UX, UY, UZ])
    model.add_support(end, [UY, UZ])
    _ = model.add_bar(base, end, Area64(1, SQUARE_METER), _steel(10, 7.5, 0))
    model.add_load(end, UX, Force64(10, NEWTON))
    model.add_mass(end, Mass64(0.2533, KILOGRAM))
    var state = TrussState(model)
    var motion = start_motion(model, state)
    var damping = RayleighDamping(2 * 0.05 * sqrt(10 / 0.2533), 0)
    var rows = _rows("oscillator_cyclic.txt")
    assert_equal(len(rows), 300)
    var yields = 0
    for row in rows:
        dynamic_step(
            model,
            state,
            motion,
            row[1],
            Duration64(0.1, SECOND),
            average_acceleration(),
            damping,
            default_newton(),
        )
        _close(state.displacements[3], row[2], 10, "displacement")
        if state.has_yielded(MemberId(0)):
            yields += 1
    assert_true(yields > 10, String(yields))


def test_chain_under_a_ground_motion() raises:
    """Two yielding bars and two masses under a ground acceleration.

    Reference: OpenSees UniformExcitation of Steel01 trusses with Rayleigh
    damping of the mass and of the initial stiffness.
    """
    var model = TrussModel()
    var base = model.add_node(Vec3d(0, 0, 0))
    var middle = model.add_node(Vec3d(1, 0, 0))
    var end = model.add_node(Vec3d(2, 0, 0))
    model.add_support(base, [UX, UY, UZ])
    model.add_support(middle, [UY, UZ])
    model.add_support(end, [UY, UZ])
    var area = Area64(1, SQUARE_METER)
    _ = model.add_bar(base, middle, area, _steel(1000, 15, 0.05))
    _ = model.add_bar(middle, end, area, _steel(600, 8, 0.02))
    model.add_mass(middle, Mass64(2, KILOGRAM))
    model.add_mass(end, Mass64(1, KILOGRAM))
    set_ground_motion_load(model, UX)
    var state = TrussState(model)
    var motion = start_motion(model, state)
    var damping = RayleighDamping(0.2, 0.002)
    var rows = _rows("chain_ground.txt")
    assert_equal(len(rows), 300)
    for row in rows:
        dynamic_step(
            model,
            state,
            motion,
            row[1],
            Duration64(0.02, SECOND),
            average_acceleration(),
            damping,
            default_newton(),
        )
        _close(state.displacements[3], row[2], 1, "middle")
        _close(state.displacements[6], row[3], 1, "end")
    assert_true(
        state.has_yielded(MemberId(0)) or state.has_yielded(MemberId(1))
    )


def _compare_curve(
    section: FiberSection,
    axial: Float64,
    name: String,
    moment_scale: Float64,
    exact_steps: Int,
) raises:
    """Compare a moment-curvature curve with that of OpenSees.

    Args:
        section: The section.
        axial: The axial force, tension positive, in newtons.
        name: The reference file.
        moment_scale: The size of the moments of the curve, in N m.
        exact_steps: How many points must agree to 1e-9. After them the
            moment must agree to 0.2% and the axial strain to 1%.

    Raises:
        Error: A point differs.
    """
    var rows = _rows(name)
    var steps = len(rows) - 1
    var curve = moment_curvature(
        section,
        Force64(axial, NEWTON),
        InverseLength64(rows[steps][0], PER_METER),
        steps,
        1e-12,
    )
    assert_equal(len(curve), len(rows))
    for i in range(len(rows)):
        _close(curve[i].curvature.to(PER_METER), rows[i][0], 1, "curvature")
        var strain = curve[i].strain
        var moment = curve[i].moment.to(NEWTON_METER)
        if i < exact_steps:
            _close(strain, rows[i][1], 1e-2, "strain")
            _close(moment, rows[i][2], moment_scale, "moment")
        else:
            assert_true(
                abs(moment / rows[i][2] - 1) < 2e-3, String(i, " ", moment)
            )
            assert_true(
                abs(strain / rows[i][1] - 1) < 1e-2, String(i, " ", strain)
            )


def test_reinforced_beam_curve() raises:
    """The moment-curvature curve of the reinforced concrete beam.

    Reference: OpenSees Concrete01 and Steel01 fibers in a fiber section,
    in a zeroLengthSection element under DisplacementControl. Up to the
    yield of the steel, in step 15, each point agrees to 1e-9. Then the
    neutral axis rises, and the compressed fibers just above it unload.
    Concrete01 unloads them along a line, and the law of the port, which
    has no memory, takes them back along the envelope. From then on the
    moments differ by up to 0.10% and the axial strains by up to 0.58%.
    """
    var section = FiberSection()
    section.add_concrete_patch(
        Length64(-0.25, METER),
        Length64(0.25, METER),
        Length64(0.3, METER),
        100,
        ConcreteLaw(
            Pressure64(30e6, PASCAL), 0.002, Pressure64(6e6, PASCAL), 0.006
        ),
    )
    section.add_steel(
        Length64(-0.19, METER),
        Area64(1500e-6, SQUARE_METER),
        _steel(200e9, 420e6, 0),
    )
    _compare_curve(section, 0, "section_beam.txt", 3e5, 15)


def test_steel_column_curve() raises:
    """The steel rectangle at 0.4 of its squash load, to 40 yield curvatures.

    Reference: OpenSees Steel01 fibers in a zeroLengthSection element,
    with the axial load held constant.
    """
    var section = FiberSection()
    section.add_steel_patch(
        Length64(-0.1, METER),
        Length64(0.1, METER),
        Length64(0.1, METER),
        400,
        _steel(200e9, 250e6, 0),
    )
    _compare_curve(section, -0.4 * 250e6 * 0.02, "section_column.txt", 1e5, 81)


def main() raises:
    """Run the tests.

    Raises:
        Error: A test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()
