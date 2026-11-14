# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Static solves, reactions, boundary faces and stress colors."""

from core.buffer_geometry import COLOR, POSITION
from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.ids import DOF_X, DOF_Y, DOF_Z, DofAxis, MaterialId, NodeId
from extensions.fem.mesh import TetMesh, box_mesh, quadratic_mesh
from extensions.fem.mesh import boundary_faces
from extensions.fem.post import stress_color, stress_geometry
from extensions.fem.static import StaticProblem, StaticResult, solve_static
from extensions.numerics.iterative import BUDGET_EXHAUSTED, CONVERGED
from extensions.sdf.vector import v3
from render.srgb import srgb_to_linear
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    Acceleration64,
    Density64,
    Force64,
    KILOGRAM_PER_CUBIC_METER,
    METER_PER_SECOND_SQUARED,
    GIGAPASCAL,
    Length64,
    MEGAPASCAL,
    METER,
    NEWTON,
    PASCAL,
    Pressure64,
)


def _m(value: Float64) -> Length64:
    return Length64(value, METER)


def _steel() raises -> IsotropicMaterial:
    return IsotropicMaterial(Pressure64(200, GIGAPASCAL), 0.3)


def _bar() raises -> StaticProblem:
    """A 2 by 1 by 1 m steel bar on symmetry supports, its end pulled 1 mm."""
    var mesh = box_mesh(_m(2), _m(1), _m(1), 4, 2, 2)
    var problem = StaticProblem(mesh^, [_steel()])
    var tolerance = _m(1e-9)
    for n in problem.mesh.nodes_on_plane(DOF_X, _m(0), tolerance):
        problem.fix(n, DOF_X, _m(0))
    for n in problem.mesh.nodes_on_plane(DOF_Y, _m(0), tolerance):
        problem.fix(n, DOF_Y, _m(0))
    for n in problem.mesh.nodes_on_plane(DOF_Z, _m(0), tolerance):
        problem.fix(n, DOF_Z, _m(0))
    for n in problem.mesh.nodes_on_plane(DOF_X, _m(2), tolerance):
        problem.fix(n, DOF_X, _m(0.001))
    return problem^


def test_patch_test_is_exact() raises:
    # A strain of 0.0005 along x in a bar free to narrow: the stress is
    # E times the strain in every element, and the bar narrows by nu.
    var problem = _bar()
    var result = solve_static(problem, 1e-12, 2000)
    assert_true(result.status == CONVERGED)
    assert_true(result.iterations > 0)
    var worst = 0.0
    var shear = 0.0
    for e in range(problem.mesh.element_count()):
        worst = max(worst, abs(result.stresses[6 * e] - 100e6))
        shear = max(shear, abs(result.stresses[6 * e + 5]))
        worst = max(worst, abs(result.von_mises[e].to(PASCAL) - 100e6))
    assert_true(worst < 1e-3)
    assert_true(shear < 1e-3)
    assert_almost_equal(result.strains[0], 0.0005, atol=1e-15)
    var corner = result.displacement(NodeId(problem.mesh.node_count() - 1))
    assert_almost_equal(corner.x, 0.001, atol=1e-15)
    assert_almost_equal(corner.y, -0.3 * 0.0005, atol=1e-15)
    assert_almost_equal(corner.z, -0.3 * 0.0005, atol=1e-15)
    # The far face pulls with the stress times its area.
    var pull = 0.0
    for n in problem.mesh.nodes_on_plane(DOF_X, _m(2), _m(1e-9)):
        pull += result.reactions[3 * n.value]
    assert_almost_equal(pull, 100e6, atol=1e-3)
    with assert_raises(contains="node id"):
        _ = result.displacement(NodeId(problem.mesh.node_count()))


def test_pressure_load_matches_the_formula() raises:
    # The same bar, pulled by a stress of 9 MPa on its far face instead.
    var problem = _bar()
    var tolerance = _m(1e-9)
    for n in problem.mesh.nodes_on_plane(DOF_X, _m(2), tolerance):
        problem.prescribed[3 * n.value] = False
    var faces = problem.press_plane(
        DOF_X, _m(2), tolerance, Pressure64(9, MEGAPASCAL)
    )
    assert_equal(faces, 8)
    var nowhere = problem.press_plane(
        DOF_Y, _m(7), tolerance, Pressure64(1, PASCAL)
    )
    assert_equal(nowhere, 0)
    var result = solve_static(problem, 1e-12, 2000)
    # 9 MPa on steel over 2 m stretches the bar 9e6 * 2 / 200e9 = 90
    # micrometers, and the stress is 9 MPa in every element.
    var tip = result.displacement(NodeId(problem.mesh.node_count() - 1))
    assert_almost_equal(tip.x, 9e-5, atol=1e-13)
    var worst = 0.0
    for e in range(problem.mesh.element_count()):
        worst = max(worst, abs(result.stresses[6 * e] - 9e6))
    assert_true(worst < 1e-3)
    with assert_raises(contains="stress must be finite"):
        _ = problem.press_plane(
            DOF_X, _m(2), tolerance, Pressure64(nan[DType.float64](), PASCAL)
        )
    with assert_raises(contains="axis must be 0 to 2"):
        _ = problem.press_plane(
            DofAxis(4), _m(2), tolerance, Pressure64(1, PASCAL)
        )


def test_everything_prescribed() raises:
    var mesh = box_mesh(_m(1), _m(1), _m(1), 1, 1, 1)
    var problem = StaticProblem(mesh^, [_steel()])
    for n in range(problem.mesh.node_count()):
        problem.fix(NodeId(n), DOF_X, _m(0.001 * Float64(n)))
        problem.fix(NodeId(n), DOF_Y, _m(0))
        problem.fix(NodeId(n), DOF_Z, _m(0))
    var result = solve_static(problem, 1e-10, 10)
    assert_equal(result.iterations, 0)
    assert_almost_equal(result.displacement(NodeId(3)).x, 0.003)


def test_budget_and_free_meshes() raises:
    var problem = _bar()
    var short = solve_static(problem, 1e-12, 1)
    assert_true(short.status == BUDGET_EXHAUSTED)
    var mesh = box_mesh(_m(1), _m(1), _m(1), 1, 1, 1)
    var free = StaticProblem(mesh^, [_steel()])
    free.load(NodeId(7), DOF_Y, Force64(1, NEWTON))
    free.load(NodeId(1), DOF_X, Force64(1, NEWTON))
    # A mesh free to move either raises or does not converge.
    var refused: Bool
    try:
        var loose = solve_static(free, 1e-10, 100)
        refused = loose.status == BUDGET_EXHAUSTED
    except:
        refused = True
    assert_true(refused)
    # A node that no element holds has no stiffness.
    var orphan_mesh = box_mesh(_m(1), _m(1), _m(1), 1, 1, 1)
    _ = orphan_mesh.add_node(v3(5, 5, 5))
    var orphan = StaticProblem(orphan_mesh^, [_steel()])
    with assert_raises(contains="positive diagonal"):
        _ = solve_static(orphan, 1e-10, 100)


def test_problem_refusals() raises:
    with assert_raises(contains="at least one element"):
        _ = StaticProblem(TetMesh(), [_steel()])
    with assert_raises(contains="material id"):
        _ = StaticProblem(box_mesh(_m(1), _m(1), _m(1), 1, 1, 1), [])
    var problem = _bar()
    with assert_raises(contains="node id"):
        problem.fix(NodeId(-1), DOF_X, _m(0))
    with assert_raises(contains="axis must be 0 to 2"):
        problem.fix(NodeId(0), DofAxis(3), _m(0))
    with assert_raises(contains="displacement must be finite"):
        problem.fix(NodeId(0), DOF_X, _m(nan[DType.float64]()))
    with assert_raises(contains="node id"):
        problem.load(NodeId(999), DOF_X, Force64(1, NEWTON))
    with assert_raises(contains="axis must be 0 to 2"):
        problem.load(NodeId(0), DofAxis(-1), Force64(1, NEWTON))
    with assert_raises(contains="force must be finite"):
        problem.load(NodeId(0), DOF_Y, Force64(inf[DType.float64](), NEWTON))
    problem.load(NodeId(0), DOF_Y, Force64(2, NEWTON))
    problem.load(NodeId(0), DOF_Y, Force64(3, NEWTON))
    assert_equal(problem.forces[1], 5)


def test_boundary_faces() raises:
    var one = TetMesh()
    _ = one.add_node(v3(0, 0, 0))
    _ = one.add_node(v3(1, 0, 0))
    _ = one.add_node(v3(0, 1, 0))
    _ = one.add_node(v3(0, 0, 1))
    _ = one.add_element(
        NodeId(0), NodeId(1), NodeId(2), NodeId(3), MaterialId(0)
    )
    var faces = boundary_faces(one)
    assert_equal(len(faces), 16)
    # A cube of six tetrahedra has two triangles on each of its six faces.
    var cube = box_mesh(_m(1), _m(1), _m(1), 1, 1, 1)
    assert_equal(len(boundary_faces(cube)) // 4, 12)
    var bar = box_mesh(_m(2), _m(1), _m(1), 4, 2, 2)
    assert_equal(len(boundary_faces(bar)) // 4, 80)
    assert_equal(len(boundary_faces(TetMesh())), 0)


def test_stress_colors() raises:
    var low = Pressure64(0, PASCAL)
    var high = Pressure64(4, PASCAL)
    var blue = stress_color(Pressure64(-1, PASCAL), low, high)
    assert_almost_equal(blue.z, Float64(srgb_to_linear(0.9)), atol=1e-6)
    var red = stress_color(Pressure64(9, PASCAL), low, high)
    assert_almost_equal(red.x, Float64(srgb_to_linear(0.9)), atol=1e-6)
    var green = stress_color(Pressure64(2, PASCAL), low, high)
    assert_almost_equal(green.y, Float64(srgb_to_linear(0.8)), atol=1e-6)
    var top = stress_color(high, low, high)
    assert_almost_equal(top.x, red.x, atol=1e-9)


def test_stress_geometry() raises:
    var problem = _bar()
    var result = solve_static(problem, 1e-12, 2000)
    var mesh = stress_geometry(
        problem.mesh,
        result,
        100,
        Pressure64(0, PASCAL),
        Pressure64(200, MEGAPASCAL),
    )
    assert_equal(mesh.triangle_count(), 80)
    ref p = mesh.attribute_view(String(POSITION)).data
    var far = 0.0
    for index in range(len(p) // 3):
        far = max(far, Float64(p[3 * index]))
    # The far face moves 1 mm, drawn 100 times larger.
    assert_almost_equal(far, 2.1, atol=1e-5)
    ref c = mesh.attribute_view(String(COLOR)).data
    # 100 MPa is the middle of the scale: green.
    assert_almost_equal(c[1], srgb_to_linear(0.8), atol=1e-5)
    var empty = stress_geometry(
        TetMesh(),
        StaticResult(0, 0),
        1,
        Pressure64(0, PASCAL),
        Pressure64(1, PASCAL),
    )
    assert_equal(empty.vertex_count(), 0)
    var other = StaticResult(problem.mesh.node_count() + 1, 1)
    with assert_raises(contains="not for this mesh"):
        _ = stress_geometry(
            problem.mesh, other, 1, Pressure64(0, PASCAL), Pressure64(1, PASCAL)
        )
    var fewer = StaticResult(problem.mesh.node_count(), 1)
    with assert_raises(contains="not for this mesh"):
        _ = stress_geometry(
            problem.mesh, fewer, 1, Pressure64(0, PASCAL), Pressure64(1, PASCAL)
        )
    with assert_raises(contains="scale must be finite"):
        _ = stress_geometry(
            problem.mesh,
            result,
            inf[DType.float64](),
            Pressure64(0, PASCAL),
            Pressure64(1, PASCAL),
        )
    with assert_raises(contains="high end above"):
        _ = stress_geometry(
            problem.mesh,
            result,
            1,
            Pressure64(1, PASCAL),
            Pressure64(1, PASCAL),
        )


def _quadratic_bar() raises -> StaticProblem:
    """The bar of `_bar`, with ten-node elements, its end free along x."""
    var mesh = quadratic_mesh(box_mesh(_m(2), _m(1), _m(1), 2, 1, 1))
    var problem = StaticProblem(mesh^, [_steel()])
    var tolerance = _m(1e-9)
    for n in problem.mesh.nodes_on_plane(DOF_X, _m(0), tolerance):
        problem.fix(n, DOF_X, _m(0))
    for n in problem.mesh.nodes_on_plane(DOF_Y, _m(0), tolerance):
        problem.fix(n, DOF_Y, _m(0))
    for n in problem.mesh.nodes_on_plane(DOF_Z, _m(0), tolerance):
        problem.fix(n, DOF_Z, _m(0))
    return problem^


def test_quadratic_patch_and_pressure() raises:
    # A pull of 1 mm on the end: the stress is uniform and exact.
    var pulled = _quadratic_bar()
    for n in pulled.mesh.nodes_on_plane(DOF_X, _m(2), _m(1e-9)):
        pulled.fix(n, DOF_X, _m(0.001))
    var result = solve_static(pulled, 1e-12, 2000)
    var worst = 0.0
    for e in range(pulled.mesh.element_count()):
        worst = max(worst, abs(result.stresses[6 * e] - 100e6))
    assert_true(worst < 1e-3)
    # A pressure of 9 MPa loads only the edge nodes of the end faces, and
    # stretches the bar sigma L / E = 90 micrometers.
    var pressed = _quadratic_bar()
    var faces = pressed.press_plane(
        DOF_X, _m(2), _m(1e-9), Pressure64(9, MEGAPASCAL)
    )
    assert_equal(faces, 2)
    var corner = pressed.mesh.nodes_on_plane(DOF_X, _m(2), _m(1e-9))[0]
    assert_equal(pressed.forces[3 * corner.value], 0)
    var stretched = solve_static(pressed, 1e-12, 2000)
    var tip = stretched.displacement(corner)
    assert_almost_equal(tip.x, 9e-5, atol=1e-13)


def test_quadratic_cantilever_bends_like_a_beam() raises:
    # Sixty ten-node elements reach 98 percent of beam theory, where the
    # same cubes as four-node elements reach 51 percent.
    var length = 0.6
    var side = 0.06
    var mesh = quadratic_mesh(
        box_mesh(_m(length), _m(side), _m(side), 10, 1, 1)
    )
    var problem = StaticProblem(mesh^, [_steel()])
    var tolerance = _m(1e-9)
    for n in problem.mesh.nodes_on_plane(DOF_X, _m(0), tolerance):
        problem.fix(n, DOF_X, _m(0))
        problem.fix(n, DOF_Y, _m(0))
        problem.fix(n, DOF_Z, _m(0))
    var tip = problem.mesh.nodes_on_plane(DOF_X, _m(length), tolerance)
    for n in tip:
        problem.load(n, DOF_Z, Force64(-20000.0 / Float64(len(tip)), NEWTON))
    var result = solve_static(problem, 1e-10, 5000)
    var deflection = 0.0
    for n in tip:
        deflection -= result.displacement(n).z
    deflection /= Float64(len(tip))
    var beam = 20000.0 * length**3 / (3 * 200e9 * side**4 / 12)
    assert_true(deflection > 0.98 * beam)
    assert_true(deflection < 1.01 * beam)
    var drawn = stress_geometry(
        problem.mesh, result, 10, Pressure64(0, PASCAL), Pressure64(1, PASCAL)
    )
    assert_equal(drawn.triangle_count(), len(boundary_faces(problem.mesh)) // 4)


def _column(quadratic: Bool) raises -> StaticProblem:
    """A column 1 m tall and 0.1 m square, standing on its base. Poisson's
    ratio is zero, so a flat base holds it in a state of uniaxial stress.
    """
    var mesh = box_mesh(_m(0.1), _m(0.1), _m(1), 1, 1, 4)
    if quadratic:
        mesh = quadratic_mesh(mesh)
    var material = IsotropicMaterial(Pressure64(200, GIGAPASCAL), 0.0)
    var problem = StaticProblem(mesh^, [material])
    var near = _m(1e-9)
    for n in problem.mesh.nodes_on_plane(DOF_Z, _m(0), near):
        problem.fix(n, DOF_Z, _m(0))
    for n in problem.mesh.nodes_on_plane(DOF_X, _m(0), near):
        problem.fix(n, DOF_X, _m(0))
    for n in problem.mesh.nodes_on_plane(DOF_Y, _m(0), near):
        problem.fix(n, DOF_Y, _m(0))
    problem.apply_gravity(
        [Density64(7850, KILOGRAM_PER_CUBIC_METER)],
        Acceleration64(9.80665, METER_PER_SECOND_SQUARED),
        v3(0, 0, -2),
    )
    return problem^


def test_a_column_under_its_own_weight() raises:
    var weight = 7850.0 * 9.80665 * 0.01
    # A column shortens by rho g L^2 / (2 E) at its top. Quadratic elements
    # hold the quadratic displacement exactly.
    var exact = -7850.0 * 9.80665 / (2 * 200e9)
    for quadratic in [False, True]:
        var problem = _column(quadratic)
        var result = solve_static(problem, 1e-13, 5000)
        var base = 0.0
        for n in problem.mesh.nodes_on_plane(DOF_Z, _m(0), _m(1e-9)):
            base += result.reactions[3 * n.value + 2]
        # The base holds the whole weight.
        assert_almost_equal(base, weight, atol=1e-9 * weight)
        var top = problem.mesh.nodes_on_plane(DOF_Z, _m(1), _m(1e-9))
        var drop = result.displacement(top[0]).z
        if quadratic:
            assert_almost_equal(drop, exact, atol=1e-6 * abs(exact))
        else:
            assert_true(abs(drop - exact) < 0.05 * abs(exact))


def test_gravity_refusals() raises:
    var problem = _bar()
    var steel = Density64(7850, KILOGRAM_PER_CUBIC_METER)
    var g = Acceleration64(9.8, METER_PER_SECOND_SQUARED)
    with assert_raises(contains="one density for each material"):
        problem.apply_gravity([steel, steel], g, v3(0, 0, -1))
    with assert_raises(contains="density must be zero or more"):
        problem.apply_gravity(
            [Density64(-1, KILOGRAM_PER_CUBIC_METER)], g, v3(0, 0, -1)
        )
    with assert_raises(contains="density must be zero or more"):
        problem.apply_gravity(
            [Density64(inf[DType.float64](), KILOGRAM_PER_CUBIC_METER)],
            g,
            v3(0, 0, -1),
        )
    with assert_raises(contains="gravity must be finite"):
        problem.apply_gravity(
            [steel],
            Acceleration64(nan[DType.float64](), METER_PER_SECOND_SQUARED),
            v3(0, 0, -1),
        )
    with assert_raises(contains="direction that is not zero"):
        problem.apply_gravity([steel], g, v3(0, 0, 0))
    with assert_raises(contains="direction that is not zero"):
        problem.apply_gravity([steel], g, v3(inf[DType.float64](), 0, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
