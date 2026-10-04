# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the modal analysis of `extensions.structure`.

The references are the Euler-Bernoulli beam frequencies of Blevins,
"Formulas for Natural Frequency and Mode Shape", 1979, table 8-1, and
Rayleigh's method for a beam with a tip mass.
"""

from std.math import pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_raises,
    assert_true,
)
from extensions.building.material import concrete, steel
from extensions.building.model import rectangle
from extensions.structure.ids import NodeId
from extensions.structure.kinds import RX, RY, UX, UY, UZ
from extensions.structure.modal import assemble_mass, solve_modes
from extensions.structure.model import StructuralModel
from generators.utils import Vec3d
from units.si import KILOGRAM, Length64, METER, Mass64, PER_SECOND


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _planar_beam(length: Float64, pieces: Int) raises -> StructuralModel:
    """A beam along x that moves only in the x-y plane."""
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


def _ei() -> Float64:
    # Bending in the x-y plane uses the weak axis of a 100 by 200 mm bar.
    return 200e9 * 0.2 * 0.1 * 0.1 * 0.1 / 12


def _mass_per_length() -> Float64:
    return 7850 * 0.02


def test_cantilever_frequency_converges() raises:
    """The first frequency of a cantilever.

    Reference: f = 1.8751² sqrt(E I / (m L⁴)) / (2π). The error must fall
    from two to four elements and be under 0.05% with eight.
    """
    var l = 10.0
    var expected = (
        1.8751**2 * sqrt(_ei() / (_mass_per_length() * l**4)) / (2 * pi)
    )
    var errors = List[Float64]()
    var meshes = [2, 4, 8]
    for i in range(3):
        var model = _planar_beam(l, meshes[i])
        model.fix(NodeId(0))
        var modes = solve_modes(model, 1)
        errors.append(abs(modes.frequencies[0].to(PER_SECOND) / expected - 1))
    assert_true(errors[1] < errors[0], String(errors[0], " ", errors[1]))
    assert_true(errors[2] < 5e-4, String(errors[2]))


def test_simply_supported_modes() raises:
    """The first three frequencies of a simply supported beam.

    Reference: f_n = (n π)² sqrt(E I / (m L⁴)) / (2π). Ten elements are
    within 0.3% for n = 1 to 3.
    """
    var l = 6.0
    var model = _planar_beam(l, 10)
    model.add_support(NodeId(0), [UX, UY])
    model.add_support(NodeId(10), [UY])
    var modes = solve_modes(model, 3)
    for n in range(1, 4):
        var k = Float64(n) * pi
        var expected = (
            k * k * sqrt(_ei() / (_mass_per_length() * l**4)) / (2 * pi)
        )
        var got = modes.frequencies[n - 1].to(PER_SECOND)
        assert_true(abs(got / expected - 1) < 3e-3, String(n, " ", got))
    # Each shape is mass-normalized: the midspan of the first is largest.
    var shape = modes.shapes[0].copy()
    assert_true(abs(shape[6 * 5 + 1]) > abs(shape[6 * 2 + 1]))


def test_tip_mass() raises:
    """A cantilever with a heavy tip mass M.

    Reference: Rayleigh's method, f = sqrt(3 E I / (L³ (M + 0.2357 m L)))
    / (2π), within 0.1% when M is much larger than m L.
    """
    var l = 2.0
    var model = _planar_beam(l, 4)
    model.fix(NodeId(0))
    model.add_mass(NodeId(4), Mass64(3e3, KILOGRAM))
    var modes = solve_modes(model, 1)
    var effective = 3e3 + 0.2357 * _mass_per_length() * l
    var expected = sqrt(3 * _ei() / (l**3 * effective)) / (2 * pi)
    var got = modes.frequencies[0].to(PER_SECOND)
    assert_true(abs(got / expected - 1) < 1e-3, String(got, " ", expected))


def test_mass_matrix_totals() raises:
    """A rigid translation carries every mass once.

    Reference: the member mass ρ A L, the shell mass ρ t A and the added
    masses sum to the total mass in each direction.
    """
    var model = StructuralModel()
    var a = model.add_node(Vec3d(0, 0, 0))
    var b = model.add_node(Vec3d(3, 0, 0))
    var c = model.add_node(Vec3d(0, 2, 1))
    _ = model.add_member(
        a, b, rectangle(_m(0.1), _m(0.2)), steel(), Vec3d(0, 0, 1)
    )
    var s = model.add_shell(a, b, c, _m(0.05), concrete())
    model.add_mass(c, Mass64(100))
    var m = assemble_mass(model)
    var area = model.shell_element(s).area
    var expected = 7850 * 0.02 * 3 + 2400 * 0.05 * area + 100
    for d in range(3):
        var u = List[Float64](length=18, fill=0)
        for n in range(3):
            u[6 * n + d] = 1
        var mu = m.multiply(u)
        var total = Float64(0)
        for i in range(18):
            total += u[i] * mu[i]
        assert_almost_equal(total, expected, atol=1e-9 * expected)


def test_modal_refusals() raises:
    var model = _planar_beam(2, 2)
    model.fix(NodeId(0))
    with assert_raises(contains="mode count"):
        _ = solve_modes(model, 0)
    with assert_raises(contains="mode count"):
        _ = solve_modes(StructuralModel(), 1)
    var loose = _planar_beam(2, 2)
    with assert_raises(contains="mechanism"):
        _ = solve_modes(loose, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
