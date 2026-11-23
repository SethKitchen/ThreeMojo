# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the nonlinear truss analysis of `extensions.structure`.

The bar references are the bilinear law and the Bauschinger effect of
kinematic hardening, from Simo and Hughes, "Computational Inelasticity",
1998, chapter 1. The truss reference is the three-bar truss, a standard
example of limit analysis: see Chen and Han, "Plasticity for Structural
Engineers", 1988, chapter 1. Its first-yield load is σ A (1 + 2 cos³ θ)
and its collapse load is σ A (1 + 2 cos θ).
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
from extensions.structure.ids import MemberId, NodeId
from extensions.structure.kinds import Dof, RX, UX, UY, UZ
from extensions.structure.nonlinear import (
    BarState,
    NewtonOptions,
    SteelLaw,
    TrussModel,
    TrussState,
    bar_response,
    default_newton,
    displacement_step,
    load_step,
)
from generators.utils import Vec3d
from units.si import (
    Area64,
    Force64,
    Length64,
    METER,
    NEWTON,
    PASCAL,
    Pressure64,
    SQUARE_METER,
)


def _law(hardening: Float64) raises -> SteelLaw:
    """A steel of 200 GPa that yields at 250 MPa."""
    return SteelLaw(
        Pressure64(200e9, PASCAL), Pressure64(250e6, PASCAL), hardening
    )


def test_bar_law_is_bilinear() raises:
    """A bar strained past its yield strain of 0.00125.

    Reference: σ = E ε up to the yield stress, then σ_y + b E (ε - ε_y).
    The tangent is E and then b E.
    """
    var law = _law(0.1)
    var rest = BarState(0, 0)
    var elastic = bar_response(law, rest, 0.001)
    assert_almost_equal(elastic.stress, 200e6, atol=1e-6)
    assert_almost_equal(elastic.tangent, 200e9, atol=0)
    assert_almost_equal(elastic.state.plastic_strain, 0.0, atol=0)
    var plastic = bar_response(law, rest, 0.00325)
    assert_almost_equal(plastic.stress, 250e6 + 20e9 * 0.002, atol=1e-3)
    assert_almost_equal(plastic.tangent, 20e9, atol=1e-3)
    var squeezed = bar_response(law, rest, -0.00325)
    assert_almost_equal(squeezed.stress, -290e6, atol=1e-3)
    # A perfectly plastic bar stays at its yield stress.
    var flat = bar_response(_law(0), rest, 0.01)
    assert_almost_equal(flat.stress, 250e6, atol=1e-3)
    assert_almost_equal(flat.tangent, 0.0, atol=0)
    assert_almost_equal(flat.state.back_stress, 0.0, atol=0)


def test_bar_law_has_the_bauschinger_effect() raises:
    """A bar yielded in tension to 290 MPa and then strained back.

    Reference: kinematic hardening keeps the elastic range at twice the
    yield stress. So the bar yields again at 290 - 500 = -210 MPa, not at
    -250 MPa.
    """
    var law = _law(0.1)
    var loaded = bar_response(law, BarState(0, 0), 0.00325)
    assert_almost_equal(loaded.stress, 290e6, atol=1e-3)
    # Unloading by 500 MPa of elastic strain reaches the other edge.
    var edge = 0.00325 - 500e6 / 200e9
    var back = bar_response(law, loaded.state, edge)
    assert_almost_equal(back.stress, -210e6, atol=1e-3)
    assert_almost_equal(back.tangent, 200e9, atol=0)
    var past = bar_response(law, loaded.state, edge - 0.001)
    assert_almost_equal(past.stress, -210e6 - 20e9 * 0.001, atol=1e-3)
    assert_almost_equal(past.tangent, 20e9, atol=1e-3)
    with assert_raises(contains="modulus"):
        _ = SteelLaw(Pressure64(0, PASCAL), Pressure64(1, PASCAL), 0)
    with assert_raises(contains="yield stress"):
        _ = SteelLaw(Pressure64(1, PASCAL), Pressure64(-1, PASCAL), 0)
    with assert_raises(contains="hardening"):
        _ = SteelLaw(Pressure64(1, PASCAL), Pressure64(1, PASCAL), 1)
    with assert_raises(contains="hardening"):
        _ = SteelLaw(Pressure64(1, PASCAL), Pressure64(1, PASCAL), -0.1)


def _three_bars(hardening: Float64) raises -> TrussModel:
    """Three bars of 1e-3 m² from a ceiling to one node 2 m below it.

    The middle bar is vertical. The outer bars are at 45 degrees. A load
    of 1 N pulls the node down.
    """
    var model = TrussModel()
    var tops = [Vec3d(-2, 0, 2), Vec3d(0, 0, 2), Vec3d(2, 0, 2)]
    var joint = model.add_node(Vec3d(0, 0, 0))
    model.add_support(joint, [UY])
    for i in range(3):
        var top = model.add_node(tops[i])
        model.add_support(top, [UX, UY, UZ])
        _ = model.add_bar(
            top, joint, Area64(1e-3, SQUARE_METER), _law(hardening)
        )
    model.add_load(joint, UZ, Force64(-1, NEWTON))
    return model^


def test_three_bar_truss_yields_and_collapses() raises:
    """The three-bar truss of perfectly plastic bars under a growing load.

    Reference: with σ A = 250 kN and θ = 45 degrees, the middle bar yields
    at σ A (1 + 2 cos³ θ) = 426.8 kN, and the truss collapses at
    σ A (1 + 2 cos θ) = 603.6 kN. Below first yield the middle bar carries
    P / (1 + 2 cos³ θ). Between the two loads it carries σ A and each
    outer bar carries (P - σ A) / (2 cos θ).
    """
    var model = _three_bars(0)
    var state = TrussState(model)
    var yield_force = 250e3
    var cosine = sqrt(0.5)
    var first = yield_force * (1 + 2 * cosine**3)
    var collapse = yield_force * (1 + 2 * cosine)
    load_step(model, state, 400e3, default_newton())
    assert_equal(state.iterations, 1)
    assert_false(state.has_yielded(MemberId(1)))
    assert_almost_equal(
        state.bar_force(MemberId(1)).to(NEWTON),
        400e3 / (1 + 2 * cosine**3),
        atol=1e-4,
    )
    # The node moves down by F L / (E A) of the middle bar.
    var sag = 400e3 / (1 + 2 * cosine**3) * 2 / (200e9 * 1e-3)
    assert_almost_equal(
        state.translation(NodeId(0), UZ).to(METER), -sag, atol=1e-12
    )
    assert_true(first > 400e3 and first < 500e3)
    load_step(model, state, 100e3, default_newton())
    assert_true(state.has_yielded(MemberId(1)))
    assert_false(state.has_yielded(MemberId(0)))
    assert_almost_equal(
        state.bar_force(MemberId(1)).to(NEWTON), yield_force, atol=1e-4
    )
    assert_almost_equal(
        state.bar_force(MemberId(0)).to(NEWTON),
        (500e3 - yield_force) / (2 * cosine),
        atol=1e-4,
    )
    assert_almost_equal(state.load_factor, 500e3, atol=0)
    # A load above the collapse load has no state, and the state stays.
    with assert_raises(contains="collapse load"):
        load_step(model, state, collapse + 1 - 500e3, default_newton())
    assert_almost_equal(state.load_factor, 500e3, atol=0)
    load_step(model, state, collapse - 1 - 500e3, default_newton())
    assert_false(state.has_yielded(MemberId(2)))


def test_unloading_leaves_residual_forces() raises:
    """The truss loaded to 550 kN and then unloaded to zero.

    Reference: the unloading is elastic. The residual force of a bar is
    its force at 550 kN less the elastic force of 550 kN. The middle bar
    ends in compression and the outer bars in tension, and the three
    balance.
    """
    var model = _three_bars(0)
    var state = TrussState(model)
    load_step(model, state, 550e3, default_newton())
    load_step(model, state, -550e3, default_newton())
    var cosine = sqrt(0.5)
    var middle = 250e3 - 550e3 / (1 + 2 * cosine**3)
    assert_true(middle < 0)
    assert_almost_equal(
        state.bar_force(MemberId(1)).to(NEWTON), middle, atol=1e-4
    )
    var outer = state.bar_force(MemberId(0)).to(NEWTON)
    assert_almost_equal(outer, -middle / (2 * cosine), atol=1e-4)
    assert_almost_equal(
        state.bar_force(MemberId(2)).to(NEWTON), outer, atol=1e-4
    )
    # The node does not return to its place.
    assert_true(state.translation(NodeId(0), UZ).to(METER) < -1e-4)


def test_displacement_control_follows_the_path() raises:
    """The truss with 1% hardening, pushed down in steps of 1 mm.

    Reference: the middle bar yields at a sag of σ L / E = 2.5 mm and the
    outer bars at 5 mm. The load at each sag is the sum of the bar forces
    from the bilinear law. Past 5 mm the load grows at 1% of its first
    rate, so the path is close to a plateau at the collapse load.
    """
    var model = _three_bars(0.01)
    var state = TrussState(model)
    var cosine = sqrt(0.5)
    var stiffness = 200e9 * 1e-3 / 2
    for step in range(1, 9):
        displacement_step(
            model,
            state,
            NodeId(0),
            UZ,
            Length64(-0.001, METER),
            default_newton(),
        )
        var sag = 0.001 * Float64(step)
        # The middle bar strains by sag / L. An outer bar strains by half.
        var middle = stiffness * sag
        if sag > 0.0025:
            middle = 250e3 + 0.01 * stiffness * (sag - 0.0025)
        var outer = 0.5 * stiffness * sag
        if sag > 0.005:
            outer = 250e3 + 0.01 * 0.5 * stiffness * (sag - 0.005)
        var expected = middle + 2 * cosine * outer
        assert_almost_equal(state.load_factor, expected, atol=1e-3)
        assert_almost_equal(
            state.translation(NodeId(0), UZ).to(METER), -sag, atol=1e-12
        )
    assert_true(state.has_yielded(MemberId(0)))
    # A step back of 0.5 mm unloads the truss along its elastic slope.
    var before = state.load_factor
    displacement_step(
        model, state, NodeId(0), UZ, Length64(0.0005, METER), default_newton()
    )
    # The elastic stiffness of the truss is (E A / L) (1 + cos θ).
    var drop = 0.0005 * stiffness * (1 + cosine)
    assert_almost_equal(state.load_factor, before - drop, atol=1e-3)


def _shallow_truss(corotational: Bool) raises -> TrussModel:
    """Two elastic bars from supports 4 m apart to an apex 0.2 m above.

    The apex moves only up and down. A load of 1 N pushes it down.
    """
    var model = TrussModel()
    var elastic = SteelLaw(
        Pressure64(200e9, PASCAL), Pressure64(1e15, PASCAL), 0
    )
    var left = model.add_node(Vec3d(-2, 0, 0))
    var right = model.add_node(Vec3d(2, 0, 0))
    var apex = model.add_node(Vec3d(0, 0, 0.2))
    model.add_support(left, [UX, UY, UZ])
    model.add_support(right, [UX, UY, UZ])
    model.add_support(apex, [UX, UY])
    _ = model.add_bar(left, apex, Area64(1e-3, SQUARE_METER), elastic)
    _ = model.add_bar(right, apex, Area64(1e-3, SQUARE_METER), elastic)
    model.add_load(apex, UZ, Force64(-1, NEWTON))
    model.set_corotational(corotational)
    return model^


def _shallow_load(sag: Float64) -> Float64:
    """Return the load that holds the apex of the shallow truss at a sag.

    Each bar has the length l = sqrt(a² + (h - w)²) and the force
    E A (l - L) / L. The load is -2 N (h - w) / l.
    """
    var first = sqrt(4 + 0.04)
    var now = sqrt(4 + (0.2 - sag) * (0.2 - sag))
    var force = 2e8 * (now - first) / first
    return -2 * force * (0.2 - sag) / now


def test_shallow_truss_snaps_through() raises:
    """The two-bar truss of von Mises, pushed down through its flat state.

    Reference: the closed form of the load at each sag. The load rises to
    a limit, falls to zero when the truss is flat, is negative until the
    truss is its own mirror image, and then rises. Displacement control
    follows the whole path within 1e-6 of the limit load.
    """
    var model = _shallow_truss(True)
    var state = TrussState(model)
    var limit = Float64(0)
    var lowest = Float64(0)
    for step in range(1, 51):
        displacement_step(
            model,
            state,
            NodeId(2),
            UZ,
            Length64(-0.01, METER),
            default_newton(),
        )
        var sag = 0.01 * Float64(step)
        var expected = _shallow_load(sag)
        assert_almost_equal(state.load_factor, expected, atol=1e-2)
        if sag < 0.2:
            limit = max(limit, state.load_factor)
        lowest = min(lowest, state.load_factor)
    # The limit load of a shallow truss is close to
    # (E A h³ / L³) times 2 / (3 sqrt(3)), at a sag of h (1 - 1 / sqrt(3)).
    var shallow = 2e8 * 0.008 / sqrt(4.04) ** 3 * 2 / (3 * sqrt(3.0))
    assert_true(abs(limit / shallow - 1) < 0.02, String(limit))
    assert_true(abs(lowest / -limit - 1) < 0.03, String(lowest))
    # At a sag of 0.2 m the truss is flat, and at 0.4 m it has no force.
    assert_almost_equal(_shallow_load(0.2), 0.0, atol=0)
    assert_almost_equal(_shallow_load(0.4), 0.0, atol=1e-6)
    # Load control holds a load below the limit at its closed-form sag.
    var held = TrussState(model)
    load_step(model, held, 0.8 * limit, default_newton())
    var sag = -held.translation(NodeId(2), UZ).to(METER)
    assert_true(sag > 0 and sag < 0.1)
    assert_almost_equal(_shallow_load(sag), 0.8 * limit, atol=1e-4)
    assert_almost_equal(
        held.bar_force(MemberId(0)).to(NEWTON),
        2e8 * (sqrt(4 + (0.2 - sag) ** 2) - sqrt(4.04)) / sqrt(4.04),
        atol=1e-3,
    )


def test_small_displacements_miss_the_snap() raises:
    """The same truss with small displacements, which stays linear.

    Reference: the stiffness 2 E A h² / L³. The corotational truss has
    this stiffness at its start and loses it as it flattens.
    """
    var linear = _shallow_truss(False)
    var state = TrussState(linear)
    load_step(linear, state, 1000, default_newton())
    var stiffness = 2 * 2e8 * 0.04 / sqrt(4.04) ** 3
    assert_almost_equal(
        state.translation(NodeId(2), UZ).to(METER),
        -1000 / stiffness,
        atol=1e-12,
    )
    var exact = _shallow_truss(True)
    var soft = TrussState(exact)
    load_step(exact, soft, 1000, default_newton())
    var sag = -soft.translation(NodeId(2), UZ).to(METER)
    assert_true(sag > 1000 / stiffness and sag < 1.1 * 1000 / stiffness)
    assert_almost_equal(_shallow_load(sag), 1000.0, atol=1e-5)


def test_chain_of_two_bars() raises:
    """Two bars in a line from a support, pulled at the far end.

    Reference: the end moves by F L / (E A) of each bar, 1 mm and 2 mm
    here, with both geometries. The middle node is free at both of its
    bars.
    """
    var geometries = [False, True]
    for k in range(2):
        var model = TrussModel()
        var elastic = SteelLaw(
            Pressure64(200e9, PASCAL), Pressure64(1e15, PASCAL), 0
        )
        var area = Area64(1e-3, SQUARE_METER)
        var a = model.add_node(Vec3d(0, 0, 0))
        var b = model.add_node(Vec3d(2, 0, 0))
        var c = model.add_node(Vec3d(4, 0, 0))
        model.add_support(a, [UX, UY, UZ])
        model.add_support(b, [UY, UZ])
        model.add_support(c, [UY, UZ])
        _ = model.add_bar(a, b, area, elastic)
        _ = model.add_bar(b, c, area, elastic)
        model.add_load(c, UX, Force64(100e3, NEWTON))
        model.set_corotational(geometries[k])
        var state = TrussState(model)
        load_step(model, state, 1, default_newton())
        assert_almost_equal(
            state.translation(b, UX).to(METER), 0.001, atol=1e-12
        )
        assert_almost_equal(
            state.translation(c, UX).to(METER), 0.002, atol=1e-12
        )
        assert_almost_equal(
            state.bar_force(MemberId(1)).to(NEWTON), 100e3, atol=1e-5
        )


def test_model_refusals() raises:
    var bad = nan[DType.float64]()
    var model = TrussModel()
    with assert_raises(contains="position"):
        _ = model.add_node(Vec3d(bad, 0, 0))
    var a = model.add_node(Vec3d(0, 0, 0))
    var b = model.add_node(Vec3d(1, 0, 0))
    var area = Area64(1e-4, SQUARE_METER)
    with assert_raises(contains="node id"):
        model.add_support(NodeId(2), [UX])
    with assert_raises(contains="node id"):
        model.add_support(NodeId(-1), [UX])
    with assert_raises(contains="translations"):
        model.add_support(a, [UX, RX])
    assert_false(model.fixed[0])
    with assert_raises(contains="node id"):
        _ = model.add_bar(NodeId(5), b, area, _law(0))
    with assert_raises(contains="node id"):
        _ = model.add_bar(a, NodeId(5), area, _law(0))
    with assert_raises(contains="ends must differ"):
        _ = model.add_bar(a, a, area, _law(0))
    with assert_raises(contains="bar area"):
        _ = model.add_bar(a, b, Area64(0, SQUARE_METER), _law(0))
    with assert_raises(contains="load must be finite"):
        model.add_load(b, UX, Force64(inf[DType.float64](), NEWTON))
    with assert_raises(contains="translations"):
        model.add_load(b, RX, Force64(1, NEWTON))
    model.add_support(a, List[Dof]())
    assert_false(model.fixed[0])
    with assert_raises(contains="tolerance"):
        _ = NewtonOptions(0, 5)
    with assert_raises(contains="iteration budget"):
        _ = NewtonOptions(1e-8, 0)


def test_step_refusals() raises:
    var model = _three_bars(0.01)
    var state = TrussState(model)
    var options = default_newton()
    with assert_raises(contains="load factor change"):
        load_step(model, state, nan[DType.float64](), options)
    with assert_raises(contains="node id"):
        displacement_step(
            model, state, NodeId(9), UZ, Length64(1, METER), options
        )
    with assert_raises(contains="translations"):
        displacement_step(
            model, state, NodeId(0), RX, Length64(1, METER), options
        )
    with assert_raises(contains="must be free"):
        displacement_step(
            model, state, NodeId(0), UY, Length64(1, METER), options
        )
    with assert_raises(contains="not zero"):
        displacement_step(
            model, state, NodeId(0), UZ, Length64(0, METER), options
        )
    with assert_raises(contains="not zero"):
        displacement_step(
            model,
            state,
            NodeId(0),
            UZ,
            Length64(inf[DType.float64](), METER),
            options,
        )
    # The load is vertical and the truss is symmetric, so the load does
    # not move the node sideways.
    with assert_raises(contains="does not move"):
        displacement_step(
            model, state, NodeId(0), UX, Length64(0.001, METER), options
        )
    # One iteration cannot pass a yield point.
    with assert_raises(contains="did not converge"):
        load_step(model, state, 500e3, NewtonOptions(1e-10, 1))
    with assert_raises(contains="translations"):
        _ = state.translation(NodeId(0), RX)
    with assert_raises(contains="node id"):
        _ = state.translation(NodeId(4), UX)
    with assert_raises(contains="node id"):
        _ = state.translation(NodeId(-1), UX)
    with assert_raises(contains="bar id"):
        _ = state.bar_force(MemberId(3))
    with assert_raises(contains="bar id"):
        _ = state.has_yielded(MemberId(-1))
    var other = TrussModel()
    var first = other.add_node(Vec3d(0, 0, 0))
    var wrong = TrussState(other)
    with assert_raises(contains="does not fit"):
        load_step(model, wrong, 1, options)
    var second = other.add_node(Vec3d(1, 0, 0))
    var third = other.add_node(Vec3d(2, 0, 0))
    _ = other.add_node(Vec3d(3, 0, 0))
    var larger = TrussState(other)
    with assert_raises(contains="does not fit"):
        load_step(model, larger, 1, options)
    # A truss with no load, and a bar that is free to swing.
    other.add_support(first, [UX, UY, UZ])
    _ = other.add_bar(first, second, Area64(1e-4, SQUARE_METER), _law(0))
    other.add_support(third, [UX, UY, UZ])
    var loose = TrussState(other)
    with assert_raises(contains="needs a load"):
        load_step(other, loose, 1, options)
    other.add_load(second, UX, Force64(1, NEWTON))
    with assert_raises(contains="mechanism"):
        load_step(other, loose, 1, options)


def test_empty_models_are_refused() raises:
    var empty = TrussModel()
    var nothing = TrussState(empty)
    with assert_raises(contains="needs a load"):
        load_step(empty, nothing, 1, default_newton())
    # A loaded node with no bar is a mechanism.
    var lonely = TrussModel()
    var node = lonely.add_node(Vec3d(0, 0, 0))
    lonely.add_load(node, UX, Force64(1, NEWTON))
    var state = TrussState(lonely)
    with assert_raises(contains="mechanism"):
        load_step(lonely, state, 1, default_newton())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
