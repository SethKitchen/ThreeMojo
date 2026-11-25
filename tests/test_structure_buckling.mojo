# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the buckling and second-order analysis of
`extensions.structure`.

The references are the Euler loads of a column with four pairs of end
conditions and the closed forms of a beam-column, from Timoshenko and
Gere, "Theory of Elastic Stability", 2nd edition, 1961, chapters 1 and 2.
"""

from std.math import inf, nan, pi, sqrt, tan, tanh
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.building.material import concrete, steel
from extensions.building.model import rectangle
from extensions.numerics.skyline import SkylineFactor, identity_order
from extensions.numerics.sparse import CsrMatrix, SparseBuilder
from extensions.structure.buckling import (
    SecondOrderOptions,
    assemble_geometric_stiffness,
    default_second_order,
    dominant_ratio,
    frame_geometric_stiffness,
    is_positive_definite,
    member_tensions,
    solve_buckling,
    solve_second_order,
    stable_scale,
)
from extensions.structure.ids import LoadCaseId, NodeId
from extensions.structure.kinds import Dof, RX, RY, RZ, UX, UY, UZ
from extensions.structure.model import StructuralModel
from extensions.structure.static import solve_static
from generators.utils import Vec3d
from units.si import (
    Acceleration64,
    Force64,
    Length64,
    METER,
    METER_PER_SECOND_SQUARED,
    NEWTON,
    NEWTON_METER,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _ei_weak() -> Float64:
    # Bending in the x-y plane uses the weak axis of a 100 by 200 mm bar.
    return 200e9 * 0.2 * 0.1 * 0.1 * 0.1 / 12


def _planar(length: Float64, pieces: Int) raises -> StructuralModel:
    """A steel bar along x that moves only in the x-y plane."""
    var model = StructuralModel()
    for i in range(pieces + 1):
        var node = model.add_node(
            Vec3d(length * Float64(i) / Float64(pieces), 0, 0)
        )
        model.add_support(node, [UZ, RX, RY])
    for i in range(pieces):
        _ = model.add_member(
            NodeId(i),
            NodeId(i + 1),
            rectangle(_m(0.1), _m(0.2)),
            steel(),
            Vec3d(0, 0, 1),
        )
    return model^


def _diagonal(values: List[Float64]) raises -> CsrMatrix:
    var builder = SparseBuilder(len(values))
    for i in range(len(values)):
        builder.add(i, i, values[i])
    return builder.build()


def test_geometric_stiffness_matrix() raises:
    """The terms of the geometric stiffness of one member.

    Reference: McGuire, Gallagher and Ziemian, chapter 9: N / (30 L)
    times 36, 3 L, 4 L² and -L². A rigid translation has no geometric
    force.
    """
    var kg = frame_geometric_stiffness(_m(2), Force64(60, NEWTON))
    assert_almost_equal(kg.get(1, 1), 36.0, atol=1e-12)
    assert_almost_equal(kg.get(2, 2), 36.0, atol=1e-12)
    assert_almost_equal(kg.get(1, 5), 6.0, atol=1e-12)
    assert_almost_equal(kg.get(2, 4), -6.0, atol=1e-12)
    assert_almost_equal(kg.get(5, 5), 16.0, atol=1e-12)
    assert_almost_equal(kg.get(4, 4), 16.0, atol=1e-12)
    assert_almost_equal(kg.get(5, 11), -4.0, atol=1e-12)
    assert_almost_equal(kg.get(4, 10), -4.0, atol=1e-12)
    assert_almost_equal(kg.get(1, 7), -36.0, atol=1e-12)
    assert_almost_equal(kg.get(8, 10), 6.0, atol=1e-12)
    assert_almost_equal(kg.get(0, 0), 0.0, atol=0)
    assert_almost_equal(kg.get(3, 3), 0.0, atol=0)
    for i in range(12):
        for j in range(12):
            assert_almost_equal(kg.get(i, j), kg.get(j, i), atol=0)
    for d in range(1, 3):
        var move = List[Float64](length=12, fill=0)
        move[d] = 1
        move[d + 6] = 1
        var force = kg.multiply_vector(move)
        for i in range(12):
            assert_almost_equal(force[i], 0.0, atol=1e-12)
    with assert_raises(contains="length"):
        _ = frame_geometric_stiffness(_m(0), Force64(1, NEWTON))
    with assert_raises(contains="axial force"):
        _ = frame_geometric_stiffness(
            _m(1), Force64(nan[DType.float64](), NEWTON)
        )


def _euler(
    start: List[Dof], end: List[Dof], coefficient: Float64, tolerance: Float64
) raises:
    """Check a 4 m column in 8 pieces against coefficient E I / L²."""
    var model = _planar(4, 8)
    model.add_support(NodeId(0), start)
    model.add_support(NodeId(8), end)
    var push = model.add_load_case("push")
    model.add_force(push, NodeId(8), UX, Force64(-1, NEWTON))
    var result = solve_buckling(model, push, 1)
    var expected = coefficient * _ei_weak() / 16
    var error = abs(result.factors[0] / expected - 1)
    assert_true(error < tolerance, String(coefficient, " ", error))


def test_euler_columns() raises:
    """The Euler load of a column with four pairs of end conditions.

    Reference: P = π² E I / (K L)², with K = 2 for a cantilever, 1 for
    pinned ends, 0.5 for fixed ends and 0.699 for a fixed and a pinned
    end, where k L = 4.4934 solves tan k L = k L. Eight elements are
    within 0.001%, 0.005%, 0.1% and 0.03%.
    """
    var none = List[Dof]()
    _euler([UX, UY, RZ], none, pi * pi / 4, 1e-5)
    _euler([UX, UY], [UY], pi * pi, 5e-5)
    _euler([UX, UY, RZ], [UY, RZ], 4 * pi * pi, 1e-3)
    _euler([UX, UY, RZ], [UY], 4.493409457909064**2, 3e-4)


def _column() raises -> StructuralModel:
    """A 3 m vertical steel cantilever in 6 pieces, free in space."""
    var model = StructuralModel()
    for i in range(7):
        _ = model.add_node(Vec3d(0, 0, 0.5 * Float64(i)))
    model.fix(NodeId(0))
    for i in range(6):
        _ = model.add_member(
            NodeId(i),
            NodeId(i + 1),
            rectangle(_m(0.1), _m(0.2)),
            steel(),
            Vec3d(1, 0, 0),
        )
    return model^


def test_column_in_space_buckles_about_each_axis() raises:
    """A vertical cantilever under a load at its top.

    Reference: π² E I / (4 L²) about the weak axis, then about the strong
    axis, which is four times stiffer, then the second weak mode at nine
    times the first. The shape has its largest entry at one, at the top.
    """
    var model = _column()
    var push = model.add_load_case("push")
    model.add_force(push, NodeId(6), UZ, Force64(-1000, NEWTON))
    var result = solve_buckling(model, push, 3)
    var expected = pi * pi * _ei_weak() / (4 * 9) / 1000
    assert_true(abs(result.factors[0] / expected - 1) < 1e-5)
    assert_true(abs(result.factors[1] / (4 * expected) - 1) < 1e-5)
    assert_true(abs(result.factors[2] / (9 * expected) - 1) < 1e-3)
    # The section depth of a column lies along x, so the weak mode sways
    # along y.
    var shape = result.shapes[0].copy()
    assert_almost_equal(abs(shape[6 * 6 + 1]), 1.0, atol=1e-12)
    assert_almost_equal(shape[1], 0.0, atol=0)
    assert_true(abs(shape[6 * 6]) < 1e-6)


def test_buckling_refusals() raises:
    var model = _planar(2, 2)
    model.fix(NodeId(0))
    var pull = model.add_load_case("pull")
    model.add_force(pull, NodeId(2), UX, Force64(1, NEWTON))
    var side = model.add_load_case("side")
    model.add_force(side, NodeId(2), UY, Force64(1, NEWTON))
    with assert_raises(contains="fewer positive"):
        _ = solve_buckling(model, pull, 1)
    with assert_raises(contains="no axial force"):
        _ = solve_buckling(model, side, 1)
    with assert_raises(contains="mode count"):
        _ = solve_buckling(model, pull, 0)
    with assert_raises(contains="mode count"):
        _ = solve_buckling(model, pull, 7)
    with assert_raises(contains="load case"):
        _ = solve_buckling(model, LoadCaseId(5), 1)
    with assert_raises(contains="mode count"):
        _ = solve_buckling(StructuralModel(), pull, 1)
    var loose = _planar(2, 2)
    var load = loose.add_load_case("load")
    with assert_raises(contains="mechanism"):
        _ = solve_buckling(loose, load, 1)
    with assert_raises(contains="one entry per member"):
        _ = assemble_geometric_stiffness(model, [1.0])


def test_scale_helpers() raises:
    """The helpers that scale the geometric stiffness."""
    assert_true(is_positive_definite(_diagonal([1.0, 2.0])))
    assert_false(is_positive_definite(_diagonal([1.0, -2.0])))
    # A zero pivot stops the factorization.
    assert_false(is_positive_definite(_diagonal([1.0, 0.0])))
    var k = _diagonal([4.0, 4.0])
    var kg = _diagonal([-1.0, 1.0])
    # K + s Kg is positive definite below s = 4: 16 halves to 2.
    assert_almost_equal(stable_scale(k, kg, 16), 2.0, atol=0)
    assert_almost_equal(stable_scale(k, kg, 3), 3.0, atol=0)
    with assert_raises(contains="scale"):
        _ = stable_scale(k, kg, 0)
    with assert_raises(contains="scale"):
        _ = stable_scale(k, kg, inf[DType.float64]())
    with assert_raises(contains="stiffness must be positive definite"):
        _ = stable_scale(kg, k, 1)
    with assert_raises(contains="same size"):
        _ = stable_scale(k, _diagonal([1.0]), 1)
    # The largest eigenvalue of K⁻¹ Kg is 3 / 4 in size.
    var factor = SkylineFactor(k, identity_order(2))
    var ratio = dominant_ratio(factor, _diagonal([-3.0, 1.0]), 60)
    assert_almost_equal(ratio, 0.75, atol=1e-12)
    assert_almost_equal(
        dominant_ratio(factor, SparseBuilder(2).build(), 3), 0.0, atol=0
    )
    var empty = SparseBuilder(0).build()
    var none = SkylineFactor(empty, identity_order(0))
    assert_almost_equal(dominant_ratio(none, empty, 1), 0.0, atol=0)
    with assert_raises(contains="one step"):
        _ = dominant_ratio(factor, kg, 0)


def _beam_column(axial: Float64) raises -> StructuralModel:
    """A 4 m cantilever with a 1 kN side load and an axial load at its tip."""
    var model = _planar(4, 8)
    model.fix(NodeId(0))
    var load = model.add_load_case("load")
    model.add_force(load, NodeId(8), UY, Force64(1000, NEWTON))
    model.add_force(load, NodeId(8), UX, Force64(axial, NEWTON))
    return model^


def test_beam_column_in_compression() raises:
    """A cantilever with a side load H and half its Euler load.

    Reference: Timoshenko and Gere, chapter 1. With u = L sqrt(P / E I)
    the tip moves H L³ / (3 E I) times 3 (tan u - u) / u³ and the base
    moment is H L tan u / u. Eight elements are within 0.001%.
    """
    var euler = pi * pi * _ei_weak() / (4 * 16)
    var model = _beam_column(-0.5 * euler)
    var result = solve_second_order(
        model, LoadCaseId(0), default_second_order()
    )
    var u = 4 * sqrt(0.5 * euler / _ei_weak())
    var linear = 1000 * 64 / (3 * _ei_weak())
    var expected = linear * 3 * (tan(u) - u) / (u * u * u)
    var got = result.translation(NodeId(8), UY).to(METER)
    assert_true(abs(got / expected - 1) < 1e-5, String(got, " ", expected))
    # The amplification is close to 1 / (1 - P / P_e) = 2.
    assert_true(got / linear > 1.9 and got / linear < 2.1)
    var moment = result.reaction_moment(NodeId(0), RZ).to(NEWTON_METER)
    var expected_moment = -1000 * 4 * tan(u) / u
    assert_true(abs(moment / expected_moment - 1) < 1e-5, String(moment))
    assert_almost_equal(
        result.reaction_force(NodeId(0), UY).to(NEWTON), -1000.0, atol=1e-6
    )
    # The member at the base carries the amplified moment too.
    var at_base = result.member_forces[0].start.moment_z.to(NEWTON_METER)
    assert_true(abs(at_base / expected_moment - 1) < 1e-5, String(at_base))


def test_beam_column_in_tension() raises:
    """The same cantilever with a tension of twice its Euler load.

    Reference: the tip moves H L³ / (3 E I) times 3 (u - tanh u) / u³.
    Tension stiffens the member.
    """
    var euler = pi * pi * _ei_weak() / (4 * 16)
    var model = _beam_column(2 * euler)
    var result = solve_second_order(
        model, LoadCaseId(0), default_second_order()
    )
    var u = 4 * sqrt(2 * euler / _ei_weak())
    var linear = 1000 * 64 / (3 * _ei_weak())
    var expected = linear * 3 * (u - tanh(u)) / (u * u * u)
    var got = result.translation(NodeId(8), UY).to(METER)
    assert_true(abs(got / expected - 1) < 1e-4, String(got, " ", expected))
    assert_true(got < 0.5 * linear)


def test_second_order_frame_with_a_shell() raises:
    """A two-column frame with a shell slab on it, under weight and sway.

    Reference: statics. The reactions balance the loads with and without
    the geometric stiffness, and the sway is larger with it.
    """
    var model = StructuralModel()
    var corners = [
        Vec3d(0, 0, 0),
        Vec3d(4, 0, 0),
        Vec3d(0, 0, 3),
        Vec3d(4, 0, 3),
    ]
    for i in range(4):
        _ = model.add_node(corners[i])
    var back = model.add_node(Vec3d(2, 3, 3))
    model.fix(NodeId(0))
    model.fix(NodeId(1))
    model.add_support(back, [UX, UY, UZ])
    var section = rectangle(_m(0.1), _m(0.1))
    _ = model.add_member(NodeId(0), NodeId(2), section, steel(), Vec3d(1, 0, 0))
    _ = model.add_member(NodeId(1), NodeId(3), section, steel(), Vec3d(1, 0, 0))
    _ = model.add_member(NodeId(2), NodeId(3), section, steel(), Vec3d(0, 0, 1))
    _ = model.add_shell(NodeId(2), NodeId(3), back, _m(0.2), concrete())
    var load = model.add_load_case("load")
    model.add_self_weight(
        load, Acceleration64(9.80665, METER_PER_SECOND_SQUARED)
    )
    model.add_force(load, NodeId(2), UZ, Force64(-4e5, NEWTON))
    model.add_force(load, NodeId(3), UZ, Force64(-4e5, NEWTON))
    model.add_force(load, NodeId(2), UX, Force64(5e3, NEWTON))
    var first = solve_static(model, load)
    var second = solve_second_order(model, load, default_second_order())
    assert_equal(len(second.shell_resultants), 1)
    assert_equal(len(second.member_forces), 3)
    var sway_first = first.translation(NodeId(2), UX).to(METER)
    var sway_second = second.translation(NodeId(2), UX).to(METER)
    assert_true(sway_second > 1.02 * sway_first, String(sway_second))
    for d in range(3):
        var applied = Float64(0)
        var held = Float64(0)
        for n in range(5):
            applied += second.loads[6 * n + d]
            held += second.reactions[6 * n + d]
        assert_almost_equal(held, -applied, atol=1e-6 * 8e5)
    # The columns carry the compression that amplifies the sway.
    var tensions = member_tensions(second.member_forces)
    assert_true(tensions[0] < -3e5)
    assert_true(tensions[1] < -3e5)


def test_hanging_bar_tension_is_the_mean() raises:
    """A bar that hangs under its own weight W.

    Reference: the tension falls from W at the top to zero at the bottom,
    so the value of the member is W / 2.
    """
    var model = StructuralModel()
    var top = model.add_node(Vec3d(0, 0, 2))
    var bottom = model.add_node(Vec3d(0, 0, 0))
    model.fix(top)
    _ = model.add_member(
        top, bottom, rectangle(_m(0.1), _m(0.2)), steel(), Vec3d(1, 0, 0)
    )
    var weight = model.add_load_case("weight")
    model.add_self_weight(weight, Acceleration64(10, METER_PER_SECOND_SQUARED))
    var result = solve_static(model, weight)
    var tensions = member_tensions(result.member_forces)
    assert_almost_equal(tensions[0], 7850 * 0.02 * 2 * 10 / 2, atol=1e-6)


def test_second_order_refusals() raises:
    var euler = pi * pi * _ei_weak() / (4 * 16)
    var over = _beam_column(-1.5 * euler)
    with assert_raises(contains="buckling load"):
        _ = solve_second_order(over, LoadCaseId(0), default_second_order())
    var under = _beam_column(-0.5 * euler)
    with assert_raises(contains="did not converge"):
        _ = solve_second_order(
            under, LoadCaseId(0), SecondOrderOptions(1e-10, 1)
        )
    with assert_raises(contains="load case"):
        _ = solve_second_order(under, LoadCaseId(3), default_second_order())
    var loose = _planar(2, 2)
    var load = loose.add_load_case("load")
    with assert_raises(contains="mechanism"):
        _ = solve_second_order(loose, load, default_second_order())
    with assert_raises(contains="tolerance"):
        _ = SecondOrderOptions(0, 5)
    with assert_raises(contains="iteration budget"):
        _ = SecondOrderOptions(1e-6, 0)
    # A model with no node has nothing to solve.
    var empty = StructuralModel()
    var nothing = empty.add_load_case("nothing")
    var result = solve_second_order(empty, nothing, default_second_order())
    assert_equal(len(result.displacements), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
