# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the frame element and the static solver of
`extensions.structure`.

The references are closed forms of Euler-Bernoulli beam theory, from
Timoshenko and Gere, "Mechanics of Materials", and Przemieniecki, "Theory
of Matrix Structural Analysis", 1968. The portal frame is checked against
the slope-deflection method, as in Hibbeler, "Structural Analysis",
chapter 11.
"""

from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.building.material import BuildingMaterial, steel
from extensions.building.model import Section, i_shape, rectangle
from extensions.building.kinds import CIRCLE
from extensions.numerics.sparse import SparseBuilder
from extensions.structure.frame import (
    LocalAxes,
    frame_local_mass,
    frame_local_stiffness,
    frame_transformation,
    member_axes,
    uniform_load_vector,
)
from extensions.structure.ids import LoadCaseId, MemberId, NodeId, ShellId
from extensions.structure.kinds import Dof, RX, RY, RZ, UX, UY, UZ
from extensions.structure.model import StructuralModel
from extensions.structure.static import (
    StaticSolver,
    assemble_stiffness,
    factor_stiffness,
    free_equations,
    load_vector,
    member_loads,
    reduce_matrix,
    solve_static,
)
from generators.utils import Vec3d
from units.si import (
    Acceleration64,
    Force64,
    GIGAPASCAL,
    KILOGRAM_PER_CUBIC_METER,
    KILONEWTON,
    KILONEWTON_METER,
    KILONEWTON_PER_METER,
    Length64,
    LineLoad64,
    METER,
    METER_TO_THE_FOURTH,
    Mass64,
    Moment64,
    NEWTON,
    NEWTON_METER,
    PASCAL,
    Pressure64,
    RADIAN,
    SQUARE_METER,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _section() -> Section:
    # 100 mm wide, 200 mm deep: the strong axis is four times stiffer.
    return rectangle(_m(0.1), _m(0.2))


def _ei_strong() -> Float64:
    return 200e9 * 0.1 * 0.2 * 0.2 * 0.2 / 12


def _ei_weak() -> Float64:
    return 200e9 * 0.2 * 0.1 * 0.1 * 0.1 / 12


def _line(
    mut model: StructuralModel, length: Float64, pieces: Int
) raises -> List[NodeId]:
    """Add a straight member along x from the origin, in equal pieces."""
    var nodes = List[NodeId]()
    for i in range(pieces + 1):
        nodes.append(
            model.add_node(Vec3d(length * Float64(i) / Float64(pieces), 0, 0))
        )
    for i in range(pieces):
        _ = model.add_member(
            nodes[i], nodes[i + 1], _section(), steel(), Vec3d(0, 0, 1)
        )
    return nodes^


def _close(got: Float64, expected: Float64, rtol: Float64) raises:
    assert_true(
        abs(got - expected) <= rtol * abs(expected),
        String("got ", got, " expected ", expected),
    )


def _check_equilibrium(
    model: StructuralModel, reactions: List[Float64], loads: List[Float64]
) raises:
    """Assert the reactions balance the loads in force and moment."""
    var force = Vec3d(0, 0, 0)
    var moment = Vec3d(0, 0, 0)
    var scale = Float64(0)
    for n in range(len(model.nodes)):
        var f = Vec3d(
            reactions[6 * n] + loads[6 * n],
            reactions[6 * n + 1] + loads[6 * n + 1],
            reactions[6 * n + 2] + loads[6 * n + 2],
        )
        var c = Vec3d(
            reactions[6 * n + 3] + loads[6 * n + 3],
            reactions[6 * n + 4] + loads[6 * n + 4],
            reactions[6 * n + 5] + loads[6 * n + 5],
        )
        force = force + f
        moment = moment + c + model.nodes[n].cross(f)
        for d in range(6):
            scale = max(scale, abs(loads[6 * n + d]))
    assert_true(force.length() <= 1e-9 * scale)
    assert_true(moment.length() <= 1e-8 * scale)


# --- kinds and ids -----------------------------------------------------------


def test_kinds_and_ids() raises:
    assert_true(UX.is_valid())
    assert_true(RZ.is_valid())
    assert_false(Dof(6).is_valid())
    assert_false(Dof(-1).is_valid())
    assert_true(UZ.is_translation())
    assert_false(RX.is_translation())
    assert_false(Dof(-1).is_translation())
    assert_true(RY.is_rotation())
    assert_false(UY.is_rotation())
    assert_false(Dof(6).is_rotation())
    assert_true(NodeId(0).is_valid())
    assert_false(NodeId(-1).is_valid())
    assert_false(MemberId(-1).is_valid())
    assert_false(ShellId(-1).is_valid())
    assert_false(LoadCaseId(-1).is_valid())


# --- the element -------------------------------------------------------------


def test_member_axes_and_fallbacks() raises:
    var a = member_axes(Vec3d(0, 0, 0), Vec3d(2, 0, 0), Vec3d(0, 0, 5))
    assert_almost_equal(a.y.y, 1, atol=1e-15)
    assert_almost_equal(a.z.z, 1, atol=1e-15)
    # A vertical member with a vertical reference uses global x.
    var column = member_axes(Vec3d(1, 1, 0), Vec3d(1, 1, 3), Vec3d(0, 0, 1))
    assert_almost_equal(column.z.x, 1, atol=1e-15)
    assert_almost_equal(column.y.y, -1, atol=1e-15)
    # A reference along a horizontal member falls back to global z.
    var beam = member_axes(Vec3d(0, 0, 0), Vec3d(0, 4, 0), Vec3d(0, -1, 0))
    assert_almost_equal(beam.z.z, 1, atol=1e-15)
    var v = Vec3d(0.3, -0.2, 0.9)
    var back = beam.to_global(beam.to_local(v))
    assert_almost_equal(back.distance_to(v), 0, atol=1e-15)
    with assert_raises(contains="finite"):
        _ = member_axes(Vec3d(nan[DType.float64](), 0, 0), Vec3d(1, 0, 0), v)
    with assert_raises(contains="finite"):
        _ = member_axes(
            Vec3d(0, 0, 0), Vec3d(1, 0, 0), Vec3d(0, 0, inf[DType.float64]())
        )
    with assert_raises(contains="differ"):
        _ = member_axes(Vec3d(1, 0, 0), Vec3d(1, 0, 0), v)
    with assert_raises(contains="zero"):
        _ = member_axes(Vec3d(0, 0, 0), Vec3d(1, 0, 0), Vec3d(0, 0, 0))


def test_element_matrices_are_symmetric_and_rigid() raises:
    """Each matrix is symmetric, and a rigid motion has no strain energy.

    The consistent mass carries the member mass ρ A L in each direction.
    """
    var axes = member_axes(Vec3d(0, 0, 0), Vec3d(1, 2, 2), Vec3d(0, 0, 1))
    var t = frame_transformation(axes)
    var section = i_shape(_m(0.2), _m(0.3), _m(0.012), _m(0.008))
    var k = t.triple_product(frame_local_stiffness(_m(3), section, steel()))
    var m = t.triple_product(frame_local_mass(_m(3), section, steel()))
    for i in range(12):
        for j in range(12):
            assert_almost_equal(k.get(i, j), k.get(j, i), atol=1e-3)
            assert_almost_equal(m.get(i, j), m.get(j, i), atol=1e-9)
    # A rigid rotation about z through the origin, plus a translation.
    var rigid = List[Float64](length=12, fill=0)
    var nodes = [Vec3d(0, 0, 0), Vec3d(1, 2, 2)]
    for e in range(2):
        rigid[6 * e] = 0.5 - 0.01 * nodes[e].y
        rigid[6 * e + 1] = 0.01 * nodes[e].x
        rigid[6 * e + 5] = 0.01
    var force = k.multiply_vector(rigid)
    for i in range(12):
        assert_almost_equal(force[i], 0, atol=1e-2)
    var translate = List[Float64](length=12, fill=0)
    translate[2] = 1
    translate[8] = 1
    var mt = m.multiply_vector(translate)
    var total = mt[2] + mt[8]
    var expected = 7850 * section.area().to(SQUARE_METER) * 3
    _close(total, expected, 1e-12)


def test_element_refusals() raises:
    var bad = steel()
    bad.poisson_ratio = 0.6
    with assert_raises(contains="length"):
        _ = frame_local_stiffness(_m(0), _section(), steel())
    with assert_raises(contains="length"):
        _ = frame_local_mass(_m(inf[DType.float64]()), _section(), steel())
    with assert_raises(contains="width"):
        _ = frame_local_stiffness(_m(1), rectangle(_m(0), _m(1)), steel())
    with assert_raises(contains="Poisson"):
        _ = frame_local_mass(_m(1), _section(), bad)
    var zero = LineLoad64(0, KILONEWTON_PER_METER)
    with assert_raises(contains="length"):
        _ = uniform_load_vector(_m(-1), zero, zero, zero)
    with assert_raises(contains="length"):
        _ = uniform_load_vector(_m(inf[DType.float64]()), zero, zero, zero)
    var big = LineLoad64(inf[DType.float64]())
    with assert_raises(contains="finite"):
        _ = uniform_load_vector(_m(1), big, zero, zero)
    with assert_raises(contains="finite"):
        _ = uniform_load_vector(_m(1), zero, big, zero)
    with assert_raises(contains="finite"):
        _ = uniform_load_vector(_m(1), zero, zero, big)


# --- closed forms ------------------------------------------------------------


def test_cantilever_tip_loads() raises:
    """A cantilever of length L with a tip load P.

    Reference: tip deflection P L³ / (3 E I) and rotation P L² / (2 E I),
    in both bending planes; axial shortening P L / (E A); twist T L / (G J).
    Hermite elements are exact for these at the nodes.
    """
    var model = StructuralModel()
    var nodes = _line(model, 3, 3)
    model.fix(nodes[0])
    var bend_z = model.add_load_case("down")
    var bend_y = model.add_load_case("sideways")
    var axial = model.add_load_case("axial")
    var twist = model.add_load_case("twist")
    var tip = nodes[3]
    var p = Force64(10, KILONEWTON)
    model.add_force(bend_z, tip, UZ, -p)
    model.add_force(bend_y, tip, UY, p)
    model.add_force(axial, tip, UX, p)
    model.add_moment(twist, tip, RX, Moment64(2, KILONEWTON_METER))
    var solver = StaticSolver(model^)
    var l = 3.0
    var r = solver.solve(bend_z)
    _close(
        r.translation(tip, UZ).to(METER),
        -1e4 * l**3 / (3 * _ei_strong()),
        1e-9,
    )
    _close(
        r.rotation(tip, RY).to(RADIAN), 1e4 * l**2 / (2 * _ei_strong()), 1e-9
    )
    _close(r.reaction_force(nodes[0], UZ).to(NEWTON), 1e4, 1e-9)
    _close(r.reaction_moment(nodes[0], RY).to(NEWTON_METER), -3e4, 1e-9)
    _check_equilibrium(solver.model, r.reactions, r.loads)
    r = solver.solve(bend_y)
    _close(
        r.translation(tip, UY).to(METER), 1e4 * l**3 / (3 * _ei_weak()), 1e-9
    )
    _close(
        r.rotation(tip, RZ).to(RADIAN), 1e4 * l**2 / (2 * _ei_weak()), 1e-9
    )
    # The fixed end of the first member carries the full moment P L.
    _close(r.member_forces[0].start.moment_z.to(NEWTON_METER), -3e4, 1e-9)
    _close(r.member_forces[0].start.shear_y.to(NEWTON), -1e4, 1e-9)
    r = solver.solve(axial)
    _close(r.translation(tip, UX).to(METER), 1e4 * l / (200e9 * 0.02), 1e-9)
    _close(r.member_forces[2].end.axial.to(NEWTON), 1e4, 1e-9)
    r = solver.solve(twist)
    var section = _section()
    var gj = steel().shear_modulus().to(PASCAL) * section.torsion_constant().to(
        METER_TO_THE_FOURTH
    )
    _close(r.rotation(tip, RX).to(RADIAN), 2e3 * l / gj, 1e-9)
    _close(r.member_forces[1].end.torque.to(NEWTON_METER), 2e3, 1e-9)


def test_fixed_beam_under_uniform_load() raises:
    """A fixed-fixed beam of span L under a uniform load w.

    Reference: midspan deflection w L⁴ / (384 E I) and end moments
    w L² / 12, each end reaction w L / 2. Consistent loads make the nodal
    values exact.
    """
    var model = StructuralModel()
    var nodes = _line(model, 6, 2)
    model.fix(nodes[0])
    model.fix(nodes[2])
    var c = model.add_load_case("uniform")
    var w = LineLoad64(-10, KILONEWTON_PER_METER)
    model.add_line_load(c, MemberId(0), UZ, w)
    model.add_line_load(c, MemberId(1), UZ, w)
    var r = solve_static(model, c)
    var l = 6.0
    _close(
        r.translation(nodes[1], UZ).to(METER),
        -1e4 * l**4 / (384 * _ei_strong()),
        1e-9,
    )
    _close(r.reaction_force(nodes[0], UZ).to(NEWTON), 1e4 * l / 2, 1e-9)
    _close(
        abs(r.reaction_moment(nodes[0], RY).to(NEWTON_METER)),
        1e4 * l * l / 12,
        1e-9,
    )
    # The member end forces subtract the fixed-end forces.
    var start = r.member_forces[0].start
    _close(abs(start.moment_y.to(NEWTON_METER)), 1e4 * l * l / 12, 1e-9)
    _close(start.shear_z.to(NEWTON), 1e4 * l / 2, 1e-9)
    # At midspan the moment is w L² / 24.
    _close(
        abs(r.member_forces[0].end.moment_y.to(NEWTON_METER)),
        1e4 * l * l / 24,
        1e-9,
    )
    _check_equilibrium(model, r.reactions, r.loads)


def test_simply_supported_beam() raises:
    """A simply supported beam of span L under a uniform load w.

    Reference: midspan deflection 5 w L⁴ / (384 E I).
    """
    var model = StructuralModel()
    var nodes = _line(model, 5, 2)
    model.add_support(nodes[0], [UX, UY, UZ, RX])
    model.add_support(nodes[2], [UY, UZ])
    assert_true(model.is_fixed(nodes[0], RX))
    assert_false(model.is_fixed(nodes[2], UX))
    var c = model.add_load_case("uniform")
    var w = LineLoad64(-4, KILONEWTON_PER_METER)
    model.add_line_load(c, MemberId(0), UZ, w)
    model.add_line_load(c, MemberId(1), UZ, w)
    var r = solve_static(model, c)
    _close(
        r.translation(nodes[1], UZ).to(METER),
        -5 * 4e3 * 5.0**4 / (384 * _ei_strong()),
        1e-9,
    )
    _close(
        r.member_forces[0].end.moment_y.to(NEWTON_METER), -4e3 * 25 / 8, 1e-9
    )
    _check_equilibrium(model, r.reactions, r.loads)


def _portal_error(scale: Float64) raises -> Float64:
    """Return the sway error of a portal frame against slope-deflection.

    The frame is 4 m tall and 6 m wide, times `scale`.
    """
    var h = 4 * scale
    var span = 6 * scale
    var model = StructuralModel()
    var a0 = model.add_node(Vec3d(0, 0, 0))
    var b0 = model.add_node(Vec3d(0, 0, h))
    var c0 = model.add_node(Vec3d(span, 0, h))
    var d0 = model.add_node(Vec3d(span, 0, 0))
    var section = i_shape(_m(0.3), _m(0.3), _m(0.02), _m(0.012))
    var up = Vec3d(0, 0, 1)
    _ = model.add_member(a0, b0, section, steel(), up)
    _ = model.add_member(b0, c0, section, steel(), up)
    _ = model.add_member(d0, c0, section, steel(), up)
    model.fix(a0)
    model.fix(d0)
    var c = model.add_load_case("wind")
    model.add_force(c, b0, UX, Force64(20, KILONEWTON))
    var r = solve_static(model, c)
    _check_equilibrium(model, r.reactions, r.loads)
    var ei = 200e9 * section.strong_inertia().to(METER_TO_THE_FOURTH)
    var a = ei / h
    var b = ei / span
    var sway = 2e4 * h * h * (2 * a + 3 * b) / (12 * a * (a + 6 * b))
    var psi = sway / h
    var theta = 3 * a * psi / (2 * a + 3 * b)
    var base = abs(2 * a * (theta - 3 * psi))
    var errors = [
        abs(r.translation(b0, UX).to(METER) / sway - 1),
        abs(r.translation(c0, UX).to(METER) / sway - 1),
        abs(abs(r.rotation(b0, RY).to(RADIAN)) / theta - 1),
        abs(abs(r.reaction_moment(a0, RY).to(NEWTON_METER)) / base - 1),
        abs(r.reaction_force(a0, UX).to(NEWTON) / -1e4 - 1),
    ]
    var worst = Float64(0)
    for i in range(len(errors)):
        worst = max(worst, errors[i])
    return worst


def test_portal_frame_sway() raises:
    """A fixed-base portal frame under a lateral load H at the beam.

    Reference: the slope-deflection method (Hibbeler, "Structural
    Analysis", chapter 11). With a = E Ic / h and b = E Ib / L, the sway
    is Δ = H h² (2a + 3b) / (12 a (a + 6b)), the joint rotation is
    θ = 3 a ψ / (2a + 3b) with ψ = Δ / h, the base moment is
    2 a (θ - 3ψ) and each base takes H / 2.

    The method ignores axial strain. Its share falls with r² / (h L), so
    the difference must be under 2% for a 4 m by 6 m frame and must
    fall by 50 times or more for a frame ten times larger.
    """
    var small = _portal_error(1)
    var large = _portal_error(10)
    assert_true(small < 0.02, String(small))
    assert_true(large < small / 50, String(large))


def test_inclined_cantilever() raises:
    """An inclined cantilever along (2, 3, 6), 7 m long, with a tip load.

    Reference: the load splits into an axial part, with shortening
    P L / (E A), and a transverse part, with deflection P L³ / (3 E I).
    A round section bends the same in every direction. A rectangle loaded
    along its local z axis bends about the strong axis.
    """
    var round = Section(CIRCLE, _m(0.15), _m(0.15), _m(0), _m(0))
    var model = StructuralModel()
    var base = model.add_node(Vec3d(0, 0, 0))
    var tip = model.add_node(Vec3d(2, 3, 6))
    _ = model.add_member(base, tip, round, steel(), Vec3d(0, 0, 1))
    model.fix(base)
    var c = model.add_load_case("tip")
    var p = Vec3d(3e3, -1e3, 2e3)
    model.add_force(c, tip, UX, Force64(p.x))
    model.add_force(c, tip, UY, Force64(p.y))
    model.add_force(c, tip, UZ, Force64(p.z))
    var r = solve_static(model, c)
    var axis = Vec3d(2, 3, 6) * (1.0 / 7)
    var along = p.dot(axis)
    var across = p - axis * along
    var e = 200e9
    var area = round.area().to(SQUARE_METER)
    var inertia = round.strong_inertia().to(METER_TO_THE_FOURTH)
    var expected = axis * (along * 7 / (e * area)) + across * (
        7.0**3 / (3 * e * inertia)
    )
    var got = Vec3d(
        r.translation(tip, UX).to(METER),
        r.translation(tip, UY).to(METER),
        r.translation(tip, UZ).to(METER),
    )
    assert_true(got.distance_to(expected) <= 1e-9 * expected.length())
    _check_equilibrium(model, r.reactions, r.loads)
    # A rectangle, loaded along the local z axis of a skew reference.
    var rect = StructuralModel()
    var b2 = rect.add_node(Vec3d(0, 0, 0))
    var t2 = rect.add_node(Vec3d(2, 3, 6))
    var reference = Vec3d(1, -1, 0.2)
    _ = rect.add_member(b2, t2, _section(), steel(), reference)
    rect.fix(b2)
    var axes = member_axes(Vec3d(0, 0, 0), Vec3d(2, 3, 6), reference)
    var c2 = rect.add_load_case("local z")
    rect.add_force(c2, t2, UX, Force64(1e3 * axes.z.x))
    rect.add_force(c2, t2, UY, Force64(1e3 * axes.z.y))
    rect.add_force(c2, t2, UZ, Force64(1e3 * axes.z.z))
    var r2 = solve_static(rect, c2)
    var u = Vec3d(
        r2.translation(t2, UX).to(METER),
        r2.translation(t2, UY).to(METER),
        r2.translation(t2, UZ).to(METER),
    )
    _close(u.dot(axes.z), 1e3 * 7.0**3 / (3 * _ei_strong()), 1e-9)
    assert_almost_equal(u.dot(axes.y), 0, atol=1e-12)


def test_self_weight_of_a_cantilever() raises:
    """A cantilever under its own weight q = ρ A g.

    Reference: tip deflection q L⁴ / (8 E I) and a base reaction q L.
    Each element carries consistent loads, so the nodes are exact.
    """
    var model = StructuralModel()
    var nodes = _line(model, 4, 4)
    model.fix(nodes[0])
    var c = model.add_load_case("dead")
    model.add_self_weight(c, Acceleration64(9.81))
    var r = solve_static(model, c)
    var q = 7850 * 0.02 * 9.81
    _close(r.reaction_force(nodes[0], UZ).to(NEWTON), q * 4, 1e-9)
    _close(
        r.translation(nodes[4], UZ).to(METER),
        -q * 4.0**4 / (8 * _ei_strong()),
        1e-9,
    )
    _check_equilibrium(model, r.reactions, r.loads)
    # The loads of a member come back in local axes, without other cases.
    var other = model.add_load_case("empty")
    var local = member_loads(model, other, MemberId(0))
    for i in range(12):
        assert_equal(local[i], 0)
    var f = load_vector(model, other)
    assert_equal(len(f), 30)


# --- refusals ----------------------------------------------------------------


def test_model_refusals() raises:
    var model = StructuralModel()
    var a = model.add_node(Vec3d(0, 0, 0))
    var b = model.add_node(Vec3d(1, 0, 0))
    var c = model.add_load_case("c")
    _ = model.add_member(a, b, _section(), steel(), Vec3d(0, 0, 1))
    var bad = steel()
    bad.density = bad.density.scaled(-1)
    with assert_raises(contains="finite"):
        _ = model.add_node(Vec3d(0, inf[DType.float64](), 0))
    with assert_raises(contains="finite"):
        _ = model.add_node(Vec3d(nan[DType.float64](), 0, 0))
    with assert_raises(contains="finite"):
        _ = model.add_node(Vec3d(0, 0, -inf[DType.float64]()))
    model.add_support(a, [])
    assert_false(model.is_fixed(a, UX))
    with assert_raises(contains="node id"):
        model.fix(NodeId(2))
    with assert_raises(contains="node id"):
        model.add_support(NodeId(-1), [UX])
    with assert_raises(contains="degree of freedom"):
        model.add_support(a, [UX, Dof(7)])
    with assert_raises(contains="degree of freedom"):
        _ = model.is_fixed(a, Dof(-2))
    with assert_raises(contains="node id"):
        _ = model.add_member(a, NodeId(5), _section(), steel(), Vec3d(0, 0, 1))
    with assert_raises(contains="node id"):
        _ = model.add_member(NodeId(5), a, _section(), steel(), Vec3d(0, 0, 1))
    with assert_raises(contains="differ"):
        _ = model.add_member(a, a, _section(), steel(), Vec3d(0, 0, 1))
    with assert_raises(contains="width"):
        _ = model.add_member(
            a, b, rectangle(_m(-1), _m(1)), steel(), Vec3d(0, 0, 1)
        )
    with assert_raises(contains="density"):
        _ = model.add_member(a, b, _section(), bad, Vec3d(0, 0, 1))
    with assert_raises(contains="load case id"):
        model.add_force(LoadCaseId(1), a, UX, Force64(1))
    with assert_raises(contains="node id"):
        model.add_force(c, NodeId(9), UX, Force64(1))
    with assert_raises(contains="translation"):
        model.add_force(c, a, RX, Force64(1))
    with assert_raises(contains="finite"):
        model.add_force(c, a, UX, Force64(nan[DType.float64]()))
    with assert_raises(contains="load case id"):
        model.add_moment(LoadCaseId(-1), a, RX, Moment64(1))
    with assert_raises(contains="node id"):
        model.add_moment(c, NodeId(-1), RX, Moment64(1))
    with assert_raises(contains="rotation"):
        model.add_moment(c, a, UZ, Moment64(1))
    with assert_raises(contains="finite"):
        model.add_moment(c, a, RZ, Moment64(inf[DType.float64]()))
    with assert_raises(contains="load case id"):
        model.add_line_load(LoadCaseId(3), MemberId(0), UX, LineLoad64(1))
    with assert_raises(contains="member id"):
        model.add_line_load(c, MemberId(1), UX, LineLoad64(1))
    with assert_raises(contains="member id"):
        model.add_line_load(c, MemberId(-1), UX, LineLoad64(1))
    with assert_raises(contains="translation"):
        model.add_line_load(c, MemberId(0), RY, LineLoad64(1))
    with assert_raises(contains="finite"):
        model.add_line_load(
            c, MemberId(0), UY, LineLoad64(nan[DType.float64]())
        )
    with assert_raises(contains="load case id"):
        model.add_self_weight(LoadCaseId(4), Acceleration64(9.81))
    with assert_raises(contains="gravity"):
        model.add_self_weight(c, Acceleration64(-1))
    with assert_raises(contains="gravity"):
        model.add_self_weight(c, Acceleration64(inf[DType.float64]()))
    with assert_raises(contains="node id"):
        model.add_mass(NodeId(3), Mass64(1))
    with assert_raises(contains="mass"):
        model.add_mass(a, Mass64(-1))
    with assert_raises(contains="mass"):
        model.add_mass(a, Mass64(nan[DType.float64]()))
    with assert_raises(contains="mass"):
        model.add_mass(a, Mass64(inf[DType.float64]()))
    with assert_raises(contains="load case id"):
        _ = load_vector(model, LoadCaseId(7))
    with assert_raises(contains="load case id"):
        _ = member_loads(model, LoadCaseId(7), MemberId(0))
    with assert_raises(contains="member id"):
        _ = member_loads(model, c, MemberId(2))


def test_mechanism_is_refused() raises:
    """A beam on one pin and one roller in 3D can spin about its axis."""
    var model = StructuralModel()
    var nodes = _line(model, 2, 1)
    model.add_support(nodes[0], [UX, UY, UZ])
    model.add_support(nodes[1], [UY, UZ])
    _ = model.add_load_case("c")
    with assert_raises(contains="mechanism"):
        _ = StaticSolver(model^)
    # A free node with nothing attached is a mechanism too.
    var loose = StructuralModel()
    _ = loose.add_node(Vec3d(0, 0, 0))
    with assert_raises(contains="singular"):
        _ = StaticSolver(loose^)
    # An indefinite matrix factors but is refused.
    var builder = SparseBuilder(2)
    builder.add(0, 0, 1)
    builder.add(1, 1, -1)
    with assert_raises(contains="not positive definite"):
        _ = factor_stiffness(builder.build())


def test_empty_model() raises:
    """A model with no nodes solves to empty vectors."""
    var model = StructuralModel()
    var c = model.add_load_case("nothing")
    var r = solve_static(model, c)
    assert_equal(len(r.displacements), 0)
    assert_equal(len(r.member_forces), 0)


def test_result_refusals_and_reduction() raises:
    var model = StructuralModel()
    var nodes = _line(model, 2, 1)
    model.fix(nodes[0])
    model.fix(nodes[1])
    var c = model.add_load_case("c")
    var solver = StaticSolver(model^)
    var r = solver.solve(c)
    assert_equal(r.translation(nodes[1], UX).to(METER), 0)
    with assert_raises(contains="load case id"):
        _ = solver.solve(LoadCaseId(1))
    with assert_raises(contains="node id"):
        _ = r.translation(NodeId(2), UX)
    with assert_raises(contains="node id"):
        _ = r.rotation(NodeId(-1), RX)
    with assert_raises(contains="UX"):
        _ = r.translation(nodes[0], RX)
    with assert_raises(contains="RX"):
        _ = r.rotation(nodes[0], UZ)
    with assert_raises(contains="UX"):
        _ = r.reaction_force(nodes[0], RZ)
    with assert_raises(contains="RX"):
        _ = r.reaction_moment(nodes[0], UY)
    var k = assemble_stiffness(solver.model)
    var equation = free_equations(solver.model)
    assert_equal(equation[0], -1)
    with assert_raises(contains="numbering"):
        _ = reduce_matrix(k, [0, 1], 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
