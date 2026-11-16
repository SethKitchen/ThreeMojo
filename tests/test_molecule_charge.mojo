# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Formal charges of a protein, their potential and the surface colors."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from extensions.chemistry.quantities import ANGSTROM, MolarEnergy64
from extensions.molecule.charge import (
    Charges,
    coulomb_potential,
    formal_charges,
)
from extensions.molecule.coloring import color_surface_potential
from extensions.molecule.dssp import KILOCALORIE_PER_MOLE
from extensions.molecule.ids import ALL_LOCATIONS, ModelId
from extensions.molecule.structure import Structure, parse_pdb_structure
from extensions.sdf.vector import V3, v3
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER

comptime CHARGED = (
    "ATOM      1  N   LYS A   1       0.000   0.000   0.000  1.00 10.00        "
    "   N\nATOM      2  CA  LYS A   1       1.500   0.000   0.000  1.00 10.00  "
    "         C\nATOM      3  NZ  LYS A   1       3.000   2.000   0.000  1.00"
    " 10.00           N\nATOM      4  N   ASP A   2       5.000   0.000   0.000"
    "  1.00 10.00           N\nATOM      5  CA  ASP A   2       6.000   0.000  "
    " 0.000  1.00 10.00           C\nATOM      6  OD1 ASP A   2       6.000  "
    " 1.000   0.000  1.00 10.00           O\nATOM      7  OD2 ASP A   2      "
    " 6.000  -1.000   0.000  1.00 10.00           O\nATOM      8  O   ASP A   2"
    "       7.000   0.000   0.000  1.00 10.00           O\nATOM      9  OXT ASP"
    " A   2       7.500   1.000   0.000  1.00 10.00           O\nHETATM   10 ZN"
    "    ZN A 101      10.000   0.000   0.000  1.00 10.00          ZN\nHETATM  "
    " 11  O   HOH A 102      12.000   0.000   0.000  1.00 10.00          "
    " O\nATOM     12  N   ARG B   1       0.000  10.000   0.000  1.00 10.00    "
    "       N\nATOM     13  NH1 ARG B   1       1.000  11.000   0.000  1.00"
    " 10.00           N\nATOM     14  NH2 ARG B   1       1.000   9.000   0.000"
    "  1.00 10.00           N\nATOM     15  N   GLU B   2       4.000  10.000  "
    " 0.000  1.00 10.00           N\nATOM     16  OE1 GLU B   2       5.000 "
    " 11.000   0.000  1.00 10.00           O\nATOM     17  OE2 GLU B   2      "
    " 5.000   9.000   0.000  1.00 10.00           O\nATOM     18  O   GLU B   2"
    "       6.000  10.000   0.000  1.00 10.00           O\nATOM     19  N   HIS"
    " B   3       8.000  10.000   0.000  1.00 10.00           N\nATOM     20  O"
    "   HIS B   3       9.000  10.000   0.000  1.00 10.00           O\nHETATM  "
    " 21 NA    NA C   1      20.000   0.000   0.000  1.00 10.00         "
    " NA\nHETATM   22 CL    CL C   2      22.000   0.000   0.000  1.00 10.00   "
    "       CL\nHETATM   23  K     K C   3      24.000   0.000   0.000  1.00"
    " 10.00           K\nHETATM   24 MG    MG C   4      26.000   0.000   0.000"
    "  1.00 10.00          MG\nEND\n"
)


def _a() -> Float64:
    return Length64(1.0, ANGSTROM).to(METER)


def test_formal_charges() raises:
    var s = parse_pdb_structure(String(CHARGED), ALL_LOCATIONS)
    var q = formal_charges(s, ModelId(0))
    var names = List[String]()
    for k in range(len(q.atoms)):
        ref atom = s.atoms[q.atoms[k]]
        names.append(atom.name + ":" + String(q.charges[k]))
    # Chain A: the N terminus, lysine, aspartate and its C terminus with
    # OXT, and zinc. The water at the chain's end is not its terminus.
    # Chain B: the N terminus, arginine, glutamate and the last O without
    # OXT; histidine is neutral. Chain C: four ions.
    var expected: List[String] = [
        "N:1.0",
        "NZ:1.0",
        "OD1:-0.5",
        "OD2:-0.5",
        "OXT:-0.5",
        "O:-0.5",
        "ZN:2.0",
        "N:1.0",
        "NH1:0.5",
        "NH2:0.5",
        "OE1:-0.5",
        "OE2:-0.5",
        "O:-1.0",
        "NA:1.0",
        "CL:-1.0",
        "K:1.0",
        "MG:2.0",
    ]
    assert_equal(len(names), len(expected))
    for k in range(len(expected)):
        assert_equal(names[k], expected[k])
    # Chain A nets +2, chain B 0 and chain C +3.
    assert_almost_equal(q.total(), 5.0)
    # An arginine without NH2 keeps only its NH1 charge.
    for a in range(len(s.atoms)):
        if s.atoms[a].name == "NH2":
            s.atoms[a].name = "NX"
    assert_almost_equal(formal_charges(s, ModelId(0)).total(), 4.5)
    assert_equal(Charges().total(), 0.0)


def test_coulomb_potential() raises:
    var one = Charges()
    one.points.append(v3(0, 0, 0))
    one.charges.append(1.0)
    one.atoms.append(0)
    # 332.0636 / (4 r^2) at r = 5 angstroms.
    var phi = coulomb_potential(one, v3(5 * _a(), 0, 0))
    assert_almost_equal(phi.to(KILOCALORIE_PER_MOLE), 332.0636 / 100.0)
    # A charge at the point counts at 0.5 angstroms.
    var close = coulomb_potential(one, v3(0, 0, 0))
    assert_almost_equal(close.to(KILOCALORIE_PER_MOLE), 332.0636)
    # Two opposite charges cancel halfway between them.
    one.points.append(v3(4 * _a(), 0, 0))
    one.charges.append(-1.0)
    one.atoms.append(1)
    var middle = coulomb_potential(one, v3(2 * _a(), 0, 0))
    assert_almost_equal(middle.to(KILOCALORIE_PER_MOLE), 0.0, atol=1e-12)
    assert_equal(coulomb_potential(Charges(), v3(0, 0, 0)).value, 0.0)


def test_surface_colors() raises:
    var s = parse_pdb_structure(String(CHARGED), ALL_LOCATIONS)
    var a = Float32(_a())
    # Near the lysine NZ, near the chloride, and far from every charge.
    var values: List[Float32] = [
        3 * a,
        3.5 * a,
        0,
        22 * a,
        1.5 * a,
        0,
        500 * a,
        500 * a,
        0,
    ]
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(values^, 3))
    color_surface_potential(
        geometry, s, ModelId(0), MolarEnergy64(10, KILOCALORIE_PER_MOLE)
    )
    ref colors = geometry.attribute_view(COLOR)
    assert_equal(colors.count(), 3)
    # Positive is blue and negative red; far away is white.
    assert_true(colors.component(0, 2) > colors.component(0, 0))
    assert_true(colors.component(1, 0) > colors.component(1, 2))
    assert_almost_equal(
        Float64(colors.component(2, 0)),
        Float64(colors.component(2, 2)),
        atol=1e-3,
    )
    # A geometry without vertices gets no colors.
    var empty = BufferGeometry()
    empty.set_attribute(POSITION, BufferAttribute(List[Float32](), 3))
    color_surface_potential(
        empty, s, ModelId(0), MolarEnergy64(10, KILOCALORIE_PER_MOLE)
    )
    assert_equal(empty.attribute_view(COLOR).count(), 0)
    for bad in [0.0, -1.0, inf[DType.float64]()]:
        with assert_raises(contains="limit"):
            color_surface_potential(
                geometry,
                s,
                ModelId(0),
                MolarEnergy64(bad, KILOCALORIE_PER_MOLE),
            )
    with assert_raises(contains="model"):
        _ = formal_charges(s, ModelId(4))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
