# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the flat shell element of `extensions.structure`.

The references are the patch tests of Irons and Razzaque, "Experience
with the patch test for convergence of finite elements", 1972, and the
plate solutions of Timoshenko and Woinowsky-Krieger, "Theory of Plates
and Shells", 2nd edition, 1959, tables 8 and 35. The discrete Kirchhoff
triangle is Batoz, Bathe and Ho, 1980.
"""

from std.math import inf, nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.building.material import BuildingMaterial, concrete, steel
from extensions.numerics.dense import DenseMatrix, solve
from extensions.structure.ids import LoadCaseId, NodeId, ShellId
from extensions.structure.kinds import RX, RY, RZ, UX, UY, UZ
from extensions.structure.modal import solve_modes
from extensions.structure.model import StructuralModel
from extensions.structure.shell import ShellElement
from extensions.structure.static import StaticSolver, solve_static
from generators.utils import Vec3d
from units.si import (
    Acceleration64,
    RADIAN,
    Force64,
    Length64,
    METER,
    NEWTON,
    PASCAL,
    PER_SECOND,
    Pressure64,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _patch_points() -> List[Vec3d]:
    """A 2 m by 1 m patch with two irregular interior nodes."""
    return [
        Vec3d(0, 0, 0),
        Vec3d(2, 0, 0),
        Vec3d(2, 1, 0),
        Vec3d(0, 1, 0),
        Vec3d(0.5, 0.3, 0),
        Vec3d(1.4, 0.6, 0),
    ]


def _patch_triangles() -> List[Int]:
    return [0, 1, 4, 1, 5, 4, 1, 2, 5, 2, 3, 5, 3, 4, 5, 3, 0, 4]


def test_membrane_patch_test() raises:
    """A uniform tension σ on an irregular patch.

    Reference: the constant-strain triangle passes the patch test, so each
    element has σx = σ, σy = τxy = 0 exactly, and the displacements are
    u = σ x / E and v = -ν σ y / E.
    """
    var model = StructuralModel()
    var points = _patch_points()
    for i in range(len(points)):
        _ = model.add_node(points[i])
    var t = _m(0.01)
    var tri = _patch_triangles()
    for e in range(6):
        _ = model.add_shell(
            NodeId(tri[3 * e]),
            NodeId(tri[3 * e + 1]),
            NodeId(tri[3 * e + 2]),
            t,
            steel(),
        )
    for n in range(6):
        model.add_support(NodeId(n), [UZ, RX, RY])
    model.add_support(NodeId(0), [UX, UY])
    model.add_support(NodeId(3), [UX])
    var c = model.add_load_case("tension")
    var sigma = 1e6
    # Each right-edge node takes half of σ t times the 1 m edge.
    model.add_force(c, NodeId(1), UX, Force64(sigma * 0.01 / 2))
    model.add_force(c, NodeId(2), UX, Force64(sigma * 0.01 / 2))
    var r = solve_static(model, c)
    for e in range(6):
        var s = r.shell_resultants[e]
        # The local x axis of each element differs, so rotate back.
        var cx = s.axes.x.x
        var sx = s.axes.x.y
        var sxx = s.sigma_x.to(PASCAL)
        var syy = s.sigma_y.to(PASCAL)
        var txy = s.tau_xy.to(PASCAL)
        var global_xx = cx * cx * sxx + sx * sx * syy - 2 * cx * sx * txy
        var global_yy = sx * sx * sxx + cx * cx * syy + 2 * cx * sx * txy
        var global_xy = cx * sx * (sxx - syy) + (cx * cx - sx * sx) * txy
        assert_almost_equal(global_xx, sigma, atol=1e-6 * sigma)
        assert_almost_equal(global_yy, 0, atol=1e-6 * sigma)
        assert_almost_equal(global_xy, 0, atol=1e-6 * sigma)
        assert_almost_equal(s.m_x.to(NEWTON), 0, atol=1e-6)
    var e_mod = 200e9
    assert_almost_equal(
        r.translation(NodeId(5), UX).to(METER),
        sigma * 1.4 / e_mod,
        atol=1e-9 * sigma / e_mod,
    )
    assert_almost_equal(
        r.translation(NodeId(5), UY).to(METER),
        -0.3 * sigma * 0.6 / e_mod,
        atol=1e-9 * sigma / e_mod,
    )
    # The drilling rotations follow the zero membrane rotation.
    assert_almost_equal(r.rotation(NodeId(4), RZ).to(RADIAN), 0, atol=1e-12)


def test_plate_patch_test() raises:
    """A constant-curvature field on an irregular patch.

    Reference: w = a x²/2 + b y²/2 + c x y has constant moments
    mx = -D (a + ν b), my = -D (b + ν a) and mxy = -D (1 - ν) c. With the
    boundary nodes set from the field, the DKT gives the interior nodes and
    the moments exactly (Batoz, Bathe and Ho, 1980, section 5).
    """
    var points = _patch_points()
    var tri = _patch_triangles()
    var t = 0.02
    var k = DenseMatrix(36, 36)
    for e in range(6):
        var element = ShellElement(
            points[tri[3 * e]],
            points[tri[3 * e + 1]],
            points[tri[3 * e + 2]],
            _m(t),
            steel(),
        )
        var ke = element.stiffness()
        for i in range(18):
            for j in range(18):
                k.add(
                    6 * tri[3 * e + i // 6] + i % 6,
                    6 * tri[3 * e + j // 6] + j % 6,
                    ke.get(i, j),
                )
    var a = 1e-3
    var b = 2e-3
    var c = 5e-4
    var exact = List[Float64](length=36, fill=0)
    for n in range(6):
        var p = points[n]
        exact[6 * n + 2] = a * p.x * p.x / 2 + b * p.y * p.y / 2 + c * p.x * p.y
        exact[6 * n + 3] = b * p.y + c * p.x
        exact[6 * n + 4] = -(a * p.x + c * p.y)
    # Solve for the interior nodes 4 and 5.
    var kii = DenseMatrix(12, 12)
    var rhs = List[Float64](length=12, fill=0)
    for i in range(12):
        for j in range(12):
            kii.set(i, j, k.get(24 + i, 24 + j))
        for j in range(24):
            rhs[i] -= k.get(24 + i, j) * exact[j]
    var interior = solve(kii, rhs)
    for i in range(12):
        assert_almost_equal(interior[i], exact[24 + i], atol=1e-12)
    var d = 200e9 * t * t * t / (12 * (1 - 0.09))
    for e in range(6):
        var element = ShellElement(
            points[tri[3 * e]],
            points[tri[3 * e + 1]],
            points[tri[3 * e + 2]],
            _m(t),
            steel(),
        )
        var ue = List[Float64](capacity=18)
        for i in range(18):
            ue.append(exact[6 * tri[3 * e + i // 6] + i % 6])
        var s = element.resultants(ue)
        var cx = s.axes.x.x
        var sx = s.axes.x.y
        var mx = s.m_x.to(NEWTON)
        var my = s.m_y.to(NEWTON)
        var mxy = s.m_xy.to(NEWTON)
        var gx = cx * cx * mx + sx * sx * my - 2 * cx * sx * mxy
        var gy = sx * sx * mx + cx * cx * my + 2 * cx * sx * mxy
        var gxy = cx * sx * (mx - my) + (cx * cx - sx * sx) * mxy
        assert_almost_equal(gx, -d * (a + 0.3 * b), atol=1e-9 * d * b)
        assert_almost_equal(gy, -d * (b + 0.3 * a), atol=1e-9 * d * b)
        assert_almost_equal(gxy, -d * 0.7 * c, atol=1e-9 * d * b)
        assert_almost_equal(s.sigma_x.to(PASCAL), 0, atol=1e-3)


def test_rigid_motion_has_no_strain() raises:
    """A tilted element: a rigid translation and rotation give no force,
    and the stiffness is symmetric."""
    var element = ShellElement(
        Vec3d(0.2, 0.1, 0.3),
        Vec3d(1.5, 0.4, 0.9),
        Vec3d(0.6, 1.3, 1.4),
        _m(0.05),
        concrete(),
    )
    var k = element.stiffness()
    var corners = [
        Vec3d(0.2, 0.1, 0.3),
        Vec3d(1.5, 0.4, 0.9),
        Vec3d(0.6, 1.3, 1.4),
    ]
    var omega = Vec3d(0.01, -0.02, 0.015)
    var shift = Vec3d(0.3, 0.1, -0.2)
    var u = List[Float64](length=18, fill=0)
    for c in range(3):
        var d = shift + omega.cross(corners[c])
        u[6 * c] = d.x
        u[6 * c + 1] = d.y
        u[6 * c + 2] = d.z
        u[6 * c + 3] = omega.x
        u[6 * c + 4] = omega.y
        u[6 * c + 5] = omega.z
    var f = k.multiply_vector(u)
    var scale = Float64(0)
    for i in range(18):
        scale = max(scale, abs(k.get(i, i)))
        for j in range(18):
            assert_almost_equal(
                k.get(i, j), k.get(j, i), atol=1e-6 * abs(k.get(i, i))
            )
    for i in range(18):
        assert_almost_equal(f[i], 0, atol=1e-9 * scale)
    var s = element.resultants(u)
    assert_almost_equal(s.sigma_x.to(PASCAL), 0, atol=1e-3)
    assert_almost_equal(s.m_xy.to(NEWTON), 0, atol=1e-3)


def _plate(n: Int, clamped: Bool) raises -> Float64:
    """Return the center deflection of a 1 m square plate, 10 mm thick,
    under 1 kPa, on an n by n mesh."""
    var model = StructuralModel()
    var a = 1.0
    for j in range(n + 1):
        for i in range(n + 1):
            var node = model.add_node(
                Vec3d(
                    a * Float64(i) / Float64(n), a * Float64(j) / Float64(n), 0
                )
            )
            model.add_support(node, [UX, UY, RZ])
            if i == 0 or j == 0 or i == n or j == n:
                model.add_support(node, [UZ])
                if clamped:
                    model.add_support(node, [RX, RY])
    var c = model.add_load_case("pressure")
    for j in range(n):
        for i in range(n):
            var p = j * (n + 1) + i
            # Alternate the diagonals so the mesh has the plate's symmetry.
            if (i + j) % 2 == 0:
                _ = model.add_shell(
                    NodeId(p),
                    NodeId(p + 1),
                    NodeId(p + n + 2),
                    _m(0.01),
                    steel(),
                )
                _ = model.add_shell(
                    NodeId(p),
                    NodeId(p + n + 2),
                    NodeId(p + n + 1),
                    _m(0.01),
                    steel(),
                )
            else:
                _ = model.add_shell(
                    NodeId(p),
                    NodeId(p + 1),
                    NodeId(p + n + 1),
                    _m(0.01),
                    steel(),
                )
                _ = model.add_shell(
                    NodeId(p + 1),
                    NodeId(p + n + 2),
                    NodeId(p + n + 1),
                    _m(0.01),
                    steel(),
                )
    for s in range(len(model.shells)):
        model.add_pressure(c, ShellId(s), Pressure64(1000))
    var r = solve_static(model, c)
    var total = Float64(0)
    for i in range(len(model.nodes)):
        total += r.reactions[6 * i + 2]
    assert_almost_equal(total, 1000 * a * a, atol=1e-9 * 1000)
    var d = 200e9 * 1e-6 / (12 * (1 - 0.09))
    var center = NodeId((n // 2) * (n + 1) + n // 2)
    return -r.translation(center, UZ).to(METER) * d / (1000 * a**4)


def test_simply_supported_plate_converges() raises:
    """A simply supported square plate under a uniform load q.

    Reference: w_max = 0.00406 q a⁴ / D with D = E t³ / (12 (1 - ν²)) and
    ν = 0.3 (Timoshenko and Woinowsky-Krieger, table 8). The error must
    fall with each refinement and be under 1% on a 16 by 16 mesh.
    """
    var errors = List[Float64]()
    var meshes = [4, 8, 16]
    for i in range(3):
        errors.append(abs(_plate(meshes[i], False) / 0.00406 - 1))
    assert_true(errors[1] < errors[0], String(errors[0], " ", errors[1]))
    assert_true(errors[2] < errors[1], String(errors[1], " ", errors[2]))
    assert_true(errors[2] < 0.01, String(errors[2]))


def test_clamped_plate_converges() raises:
    """A clamped square plate under a uniform load q.

    Reference: w_max = 0.00126 q a⁴ / D, ν = 0.3 (Timoshenko and
    Woinowsky-Krieger, table 35). The error must fall with each
    refinement and be under 2% on a 16 by 16 mesh.
    """
    var errors = List[Float64]()
    var meshes = [4, 8, 16]
    for i in range(3):
        errors.append(abs(_plate(meshes[i], True) / 0.00126 - 1))
    assert_true(errors[1] < errors[0], String(errors[0], " ", errors[1]))
    assert_true(errors[2] < errors[1], String(errors[1], " ", errors[2]))
    assert_true(errors[2] < 0.02, String(errors[2]))


def test_tilted_pressure_and_weight_balance() raises:
    """A tilted triangle under pressure and its own weight.

    Reference: the reactions sum to p A n plus the weight ρ t A g.
    """
    var model = StructuralModel()
    var a = model.add_node(Vec3d(0, 0, 0))
    var b = model.add_node(Vec3d(2, 0, 1))
    var c = model.add_node(Vec3d(0, 3, 0))
    var s = model.add_shell(a, b, c, _m(0.1), concrete())
    model.fix(a)
    model.fix(b)
    model.fix(c)
    var lc = model.add_load_case("wind and weight")
    model.add_pressure(lc, s, Pressure64(500))
    model.add_self_weight(lc, Acceleration64(10))
    var r = solve_static(model, lc)
    var element = model.shell_element(s)
    var expected = element.axes.z * (500 * element.area) + Vec3d(
        0, 0, 2400 * 0.1 * element.area * 10
    )
    var got = Vec3d(0, 0, 0)
    for n in range(3):
        got = got + Vec3d(
            r.reactions[6 * n], r.reactions[6 * n + 1], r.reactions[6 * n + 2]
        )
    assert_true(got.distance_to(expected) <= 1e-9 * expected.length())


def test_plate_frequency() raises:
    """The first natural frequency of a simply supported square plate.

    Reference: ω = 2 π² / a² sqrt(D / (ρ t)) (Timoshenko and
    Woinowsky-Krieger; Leissa, "Vibration of Plates", NASA SP-160, 1969).
    The lumped mass is within 1% on a 12 by 12 mesh.
    """
    var n = 12
    var model = StructuralModel()
    for j in range(n + 1):
        for i in range(n + 1):
            var node = model.add_node(
                Vec3d(Float64(i) / Float64(n), Float64(j) / Float64(n), 0)
            )
            model.add_support(node, [UX, UY, RZ])
            if i == 0 or j == 0 or i == n or j == n:
                model.add_support(node, [UZ])
    for j in range(n):
        for i in range(n):
            var p = j * (n + 1) + i
            _ = model.add_shell(
                NodeId(p), NodeId(p + 1), NodeId(p + n + 2), _m(0.01), steel()
            )
            _ = model.add_shell(
                NodeId(p),
                NodeId(p + n + 2),
                NodeId(p + n + 1),
                _m(0.01),
                steel(),
            )
    var modes = solve_modes(model, 1)
    var d = 200e9 * 1e-6 / (12 * (1 - 0.09))
    var expected = 2 * pi * pi * sqrt(d / (7850 * 0.01)) / (2 * pi)
    var got = modes.frequencies[0].to(PER_SECOND)
    assert_true(abs(got / expected - 1) < 0.01, String(got, " ", expected))


def test_shell_refusals() raises:
    var bad = steel()
    bad.elastic_modulus = bad.elastic_modulus.scaled(-1)
    var o = Vec3d(0, 0, 0)
    var x = Vec3d(1, 0, 0)
    var y = Vec3d(0, 1, 0)
    with assert_raises(contains="positive"):
        _ = ShellElement(o, x, y, _m(0.1), bad)
    with assert_raises(contains="thickness"):
        _ = ShellElement(o, x, y, _m(0), steel())
    with assert_raises(contains="thickness"):
        _ = ShellElement(o, x, y, _m(nan[DType.float64]()), steel())
    with assert_raises(contains="thickness"):
        _ = ShellElement(o, x, y, _m(inf[DType.float64]()), steel())
    with assert_raises(contains="finite"):
        _ = ShellElement(
            o, x, Vec3d(0, inf[DType.float64](), 0), _m(0.1), steel()
        )
    with assert_raises(contains="one line"):
        _ = ShellElement(o, x, Vec3d(2, 0, 0), _m(0.1), steel())
    with assert_raises(contains="one line"):
        _ = ShellElement(o, o, o, _m(0.1), steel())
    var element = ShellElement(o, x, y, _m(0.1), steel())
    with assert_raises(contains="eighteen"):
        _ = element.resultants(List[Float64](length=12, fill=0))
    var model = StructuralModel()
    var a = model.add_node(o)
    var b = model.add_node(x)
    var c = model.add_node(y)
    var lc = model.add_load_case("c")
    var s = model.add_shell(a, b, c, _m(0.1), steel())
    with assert_raises(contains="node id"):
        _ = model.add_shell(NodeId(3), b, c, _m(0.1), steel())
    with assert_raises(contains="node id"):
        _ = model.add_shell(a, NodeId(3), c, _m(0.1), steel())
    with assert_raises(contains="node id"):
        _ = model.add_shell(a, b, NodeId(-1), _m(0.1), steel())
    with assert_raises(contains="shell id"):
        _ = model.shell_element(ShellId(1))
    with assert_raises(contains="shell id"):
        model.add_pressure(lc, ShellId(-1), Pressure64(1))
    with assert_raises(contains="load case id"):
        model.add_pressure(LoadCaseId(1), s, Pressure64(1))
    with assert_raises(contains="finite"):
        model.add_pressure(lc, s, Pressure64(inf[DType.float64]()))
    assert_equal(model.shell_element(s).area, 0.5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
