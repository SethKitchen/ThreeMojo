# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Consistent mass matrices and the natural modes of a mesh."""

from core.buffer_geometry import COLOR, POSITION
from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.ids import DOF_X, DOF_Y, DOF_Z
from extensions.fem.mesh import TetMesh, box_mesh, quadratic_mesh
from extensions.fem.export import vtk_modes
from extensions.fem.modal import (
    ModalResult,
    assemble_mass,
    mass_coefficients,
    natural_modes,
)
from extensions.fem.post import mode_geometry
from extensions.fem.static import StaticProblem
from std.math import inf, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    Density64,
    GIGAPASCAL,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    PER_SECOND,
    Pressure64,
)

comptime STEEL_DENSITY = 7850.0
comptime YOUNG = 200.0e9


def _steel() -> List[Density64]:
    return [Density64(STEEL_DENSITY, KILOGRAM_PER_CUBIC_METER)]


def test_mass_coefficients() raises:
    for nodes in [4, 10]:
        var c = mass_coefficients(nodes)
        var total = 0.0
        for value in c:
            total += value
        # The element's whole mass, once along each axis.
        assert_almost_equal(total, 1.0, atol=1e-14)
        for a in range(nodes):
            for b in range(nodes):
                assert_equal(c[a * nodes + b], c[b * nodes + a])
    var linear = mass_coefficients(4)
    assert_almost_equal(linear[0], 0.1)
    assert_almost_equal(linear[1], 0.05)
    var quadratic = mass_coefficients(10)
    # Corner 0 and edge 0-1, which holds it; corner 3 and edge 0-1.
    assert_almost_equal(quadratic[4], -4.0 / 420)
    assert_almost_equal(quadratic[3 * 10 + 4], -6.0 / 420)
    # Edges 0-1 and 2-3 are opposite.
    assert_almost_equal(quadratic[4 * 10 + 9], 8.0 / 420)
    with assert_raises(contains="4 or 10 nodes"):
        _ = mass_coefficients(8)


def test_assembled_mass_is_the_weight() raises:
    var mesh = box_mesh(
        Length64(0.2, METER),
        Length64(0.1, METER),
        Length64(0.1, METER),
        2,
        1,
        1,
    )
    for quadratic in [False, True]:
        var m = assemble_mass(
            quadratic_mesh(mesh) if quadratic else mesh.copy(), _steel()
        )
        var ones = List[Float64](length=m.size, fill=0)
        for row in range(0, m.size, 3):
            ones[row] = 1
        var total = 0.0
        for value in m.multiply(ones):
            total += value
        # A rigid move along x carries the whole mass.
        assert_almost_equal(total, STEEL_DENSITY * 0.002, rtol=1e-12)
    with assert_raises(contains="positive and finite"):
        _ = assemble_mass(mesh, [Density64(0, KILOGRAM_PER_CUBIC_METER)])
    with assert_raises(contains="positive and finite"):
        _ = assemble_mass(
            mesh, [Density64(inf[DType.float64](), KILOGRAM_PER_CUBIC_METER)]
        )
    with assert_raises(contains="without a density"):
        _ = assemble_mass(mesh, List[Density64]())


def _bar(var mesh: TetMesh, poisson: Float64) raises -> StaticProblem:
    """A steel bar along x, clamped at x = 0."""
    var problem = StaticProblem(
        mesh^, [IsotropicMaterial(Pressure64(YOUNG / 1e9, GIGAPASCAL), poisson)]
    )
    var near = Length64(1e-9, METER)
    for node in problem.mesh.nodes_on_plane(DOF_X, Length64(0, METER), near):
        problem.fix(node, DOF_X, Length64(0, METER))
        problem.fix(node, DOF_Y, Length64(0, METER))
        problem.fix(node, DOF_Z, Length64(0, METER))
    return problem^


def test_axial_modes_of_a_rod() raises:
    # Only motion along x, and no Poisson coupling: a rod of length L,
    # fixed at one end, rings at (2 n - 1) c / (4 L).
    var length = 1.0
    var mesh = quadratic_mesh(
        box_mesh(
            Length64(length, METER),
            Length64(0.1, METER),
            Length64(0.1, METER),
            8,
            1,
            1,
        )
    )
    var problem = _bar(mesh^, 0.0)
    for node in range(problem.mesh.node_count()):
        problem.prescribed[3 * node + 1] = True
        problem.prescribed[3 * node + 2] = True
    var result = natural_modes(problem, _steel(), 2, 1e-12, 200)
    var c = sqrt(YOUNG / STEEL_DENSITY)
    assert_almost_equal(
        result.frequencies[0].to(PER_SECOND), c / (4 * length), rtol=1e-5
    )
    assert_almost_equal(
        result.frequencies[1].to(PER_SECOND), 3 * c / (4 * length), rtol=1e-3
    )
    # Each shape is zero at the clamp and along y and z.
    var shape = result.shapes[0].copy()
    assert_equal(shape[0], 0)
    assert_equal(shape[1 + 3 * 7], 0)
    assert_true(result.iterations > 0)


def test_bending_of_a_cantilever() raises:
    # A steel cantilever 0.6 m long and 60 mm square. Euler-Bernoulli
    # gives f = (1.8751^2 / (2 pi L^2)) sqrt(E I / (rho A)).
    var side = 0.06
    var length = 0.6
    var mesh = quadratic_mesh(
        box_mesh(
            Length64(length, METER),
            Length64(side, METER),
            Length64(side, METER),
            10,
            1,
            1,
        )
    )
    var problem = _bar(mesh^, 0.3)
    var result = natural_modes(problem, _steel(), 2, 1e-10, 200)
    var beam = (
        1.875104**2
        / (2 * pi * length**2)
        * side
        * sqrt(YOUNG / (12 * STEEL_DENSITY))
    )
    var first = result.frequencies[0].to(PER_SECOND)
    var second = result.frequencies[1].to(PER_SECOND)
    # Shear and the coarse mesh move the first mode a few percent from
    # beam theory. The square section bends alike both ways.
    assert_almost_equal(first, beam, rtol=0.04)
    assert_almost_equal(second, first, rtol=0.01)


def _rod_modes() raises -> Tuple[TetMesh, ModalResult]:
    """The axial modes of a rod 1 m long along x, fixed at x = 0."""
    var mesh = quadratic_mesh(
        box_mesh(
            Length64(1, METER),
            Length64(0.1, METER),
            Length64(0.1, METER),
            4,
            1,
            1,
        )
    )
    var problem = _bar(mesh^, 0.0)
    for node in range(problem.mesh.node_count()):
        problem.prescribed[3 * node + 1] = True
        problem.prescribed[3 * node + 2] = True
    var result = natural_modes(problem, _steel(), 2, 1e-12, 200)
    return (problem.mesh.copy(), result^)


def test_mode_geometry() raises:
    var rod = _rod_modes()
    ref mesh = rod[0]
    ref modes = rod[1]
    var amplitude = Length64(0.05, METER)
    var drawn = mode_geometry(mesh, modes.shapes[0], amplitude)
    ref points = drawn.attribute_view(POSITION)
    ref colors = drawn.attribute_view(COLOR)
    # The free end moves by the amplitude and is red. The clamp is blue.
    # A shape has an arbitrary sign, so the end can move either way.
    var reach = 0.0
    var free_end = 0
    for v in range(points.count()):
        var x = Float64(points.vector3(v).x)
        if x == 0:
            assert_true(colors.component(v, 2) > colors.component(v, 0))
        if x > 0.9 and abs(x - 1.0) > reach:
            reach = abs(x - 1.0)
            free_end = v
    assert_almost_equal(reach, 0.05, rtol=1e-6)
    assert_true(colors.component(free_end, 0) > 0.7)
    with assert_raises(contains="not for this mesh"):
        _ = mode_geometry(mesh, [0.0, 0.0, 0.0], amplitude)
    with assert_raises(contains="positive and finite"):
        _ = mode_geometry(mesh, modes.shapes[0], Length64(0, METER))
    with assert_raises(contains="positive and finite"):
        _ = mode_geometry(
            mesh, modes.shapes[0], Length64(inf[DType.float64](), METER)
        )
    var still = List[Float64](length=len(modes.shapes[0]), fill=0)
    with assert_raises(contains="node that moves"):
        _ = mode_geometry(mesh, still, amplitude)
    with assert_raises(contains="node that moves"):
        _ = mode_geometry(TetMesh(), List[Float64](), amplitude)


def test_vtk_modes() raises:
    var rod = _rod_modes()
    ref mesh = rod[0]
    ref modes = rod[1]
    var text = vtk_modes(mesh, modes)
    var lines = text.split("\n")
    assert_true(
        String(lines[1]).startswith("ThreeMojo natural modes, meters, Hz: ")
    )
    var title = String(lines[1]).split(" ")
    assert_almost_equal(
        atof(title[len(title) - 2]), modes.frequencies[0].to(PER_SECOND)
    )
    assert_true("POINT_DATA " + String(mesh.node_count()) + "\n" in text)
    assert_true("VECTORS mode_1 double\n" in text)
    assert_true("VECTORS mode_2 double\n" in text)
    # A result without modes has no vectors.
    var empty = vtk_modes(TetMesh(), ModalResult())
    assert_true("POINT_DATA 0\n" in empty)
    var hollow = ModalResult()
    hollow.shapes.append(List[Float64]())
    assert_true(
        String(vtk_modes(TetMesh(), hollow)).endswith("VECTORS mode_1 double\n")
    )
    var wrong = ModalResult()
    wrong.shapes.append([1.0])
    with assert_raises(contains="not for this mesh"):
        _ = vtk_modes(mesh, wrong)


def test_refusals() raises:
    var mesh = box_mesh(
        Length64(1, METER), Length64(1, METER), Length64(1, METER), 1, 1, 1
    )
    var problem = _bar(mesh^, 0.3)
    for dof in range(len(problem.prescribed)):
        problem.prescribed[dof] = True
    with assert_raises(contains="free degree of freedom"):
        _ = natural_modes(problem, _steel(), 1, 1e-10, 50)
    problem.prescribed[3] = False
    with assert_raises(contains="mode count"):
        _ = natural_modes(problem, _steel(), 2, 1e-10, 50)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
