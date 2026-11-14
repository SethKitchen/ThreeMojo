# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Backbone dihedral angles and Ramachandran plots."""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.dihedral import (
    BackboneAngles,
    backbone_angles,
    dihedral,
    plot_pixel,
    ramachandran_color,
    ramachandran_image,
)
from extensions.molecule.ids import (
    COIL,
    HELIX,
    ModelId,
    ResidueId,
    STRAND,
    SecondaryKind,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.structure import Structure
from extensions.sdf.vector import v3
from render.framebuffer import Color
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle64, DEGREE64, Length64


def _degrees(angle: Angle64) -> Float64:
    return angle.to(DEGREE64)


def test_the_sign_of_a_torsion() raises:
    var a = v3(1, 0, 0)
    var b = v3(0, 0, 0)
    var c = v3(0, 0, 1)
    # Cis is 0 and trans is 180 degrees.
    assert_almost_equal(_degrees(dihedral(a, b, c, v3(1, 0, 1))), 0.0)
    assert_almost_equal(abs(_degrees(dihedral(a, b, c, v3(-1, 0, 1)))), 180.0)
    # Seen along b to c, the far bond turns clockwise: positive.
    assert_almost_equal(_degrees(dihedral(a, b, c, v3(0, 1, 1))), 90.0)
    assert_almost_equal(_degrees(dihedral(a, b, c, v3(0, -1, 1))), -90.0)
    # The angle does not depend on the bond lengths.
    assert_almost_equal(
        _degrees(dihedral(a * 3, b, c * 0.5, v3(2, 2, 0.5))), 45.0
    )
    with assert_raises(contains="in a line"):
        _ = dihedral(v3(0, 0, -1), b, c, v3(1, 0, 1))
    with assert_raises(contains="in a line"):
        _ = dihedral(a, b, c, v3(0, 0, 2))


def _kinds(spec: List[Tuple[SecondaryKind, Int]]) -> List[SecondaryKind]:
    var out = List[SecondaryKind]()
    for part in spec:
        for _ in range(part[1]):
            out.append(part[0])
    return out^


def test_an_ideal_peptide_has_its_torsions() raises:
    var spec: List[Tuple[SecondaryKind, Int]] = [
        (COIL, 2),
        (HELIX, 6),
        (STRAND, 5),
        (COIL, 2),
    ]
    var kinds = _kinds(spec)
    var peptide = build_peptide("MAEELLKTYKVEVKG", kinds)
    var angles = backbone_angles(peptide, ModelId(0))
    assert_equal(len(angles), 15)
    assert_false(angles[0].has_phi)
    assert_true(angles[0].has_psi)
    assert_false(angles[14].has_psi)
    assert_false(angles[14].has_omega)
    assert_true(angles[14].has_phi)
    for k in range(15):
        assert_equal(angles[k].residue.value, k)
        var phi: Float64 = -75
        var psi: Float64 = 145
        if kinds[k] == HELIX:
            phi = -57
            psi = -47
        elif kinds[k] == STRAND:
            phi = -139
            psi = 135
        if k > 0:
            assert_almost_equal(_degrees(angles[k].phi), phi, atol=1e-6)
        if k < 14:
            assert_almost_equal(_degrees(angles[k].psi), psi, atol=1e-6)
            assert_almost_equal(
                abs(_degrees(angles[k].omega)), 180.0, atol=1e-6
            )


def test_breaks_and_missing_atoms() raises:
    var kinds = List[SecondaryKind]()
    for _ in range(12):
        kinds.append(HELIX)
    var s = build_peptide("AAAAAAAAAAAA", kinds)
    # Residue 2 has no C, residue 4 no N and residue 6 no CA.
    s.atoms[s.find_atom(ResidueId(2), "C").value].name = "CX"
    s.atoms[s.find_atom(ResidueId(4), "N").value].name = "NX"
    s.atoms[s.find_atom(ResidueId(6), "CA").value].name = "CAX"
    # Residues 9 to 11 move 10 angstroms away: the chain breaks.
    var shift = v3(10, 0, 0) * Length64(1.0, ANGSTROM).value
    for r in range(9, 12):
        ref residue = s.residues[r]
        for a in range(
            residue.first_atom, residue.first_atom + residue.atom_count
        ):
            s.atoms[a].position = s.atoms[a].position + shift
    var angles = backbone_angles(s, ModelId(0))
    # Residues 2, 4 and 6 are left out.
    assert_equal(len(angles), 9)
    var ids: List[Int] = [0, 1, 3, 5, 7, 8, 9, 10, 11]
    for k in range(9):
        assert_equal(angles[k].residue.value, ids[k])
    # Residue 3 has no phi, as the C before it is gone, and no psi, as
    # the N after it is gone.
    assert_false(angles[2].has_phi)
    assert_false(angles[2].has_psi)
    # Residue 5 has a psi but no omega: residue 6 has no CA.
    assert_true(angles[3].has_psi)
    assert_false(angles[3].has_omega)
    # Residue 8 ends one piece, and residue 9 starts the next.
    assert_false(angles[5].has_psi)
    assert_false(angles[6].has_phi)
    assert_true(angles[6].has_psi)
    assert_almost_equal(_degrees(angles[6].psi), -47.0, atol=1e-6)
    with assert_raises(contains="model"):
        _ = backbone_angles(s, ModelId(1))


def test_the_plot() raises:
    var spec: List[Tuple[SecondaryKind, Int]] = [
        (HELIX, 3),
        (STRAND, 3),
        (COIL, 3),
    ]
    var kinds = _kinds(spec)
    var s = build_peptide("AAAVVVGGG", kinds)
    var angles = backbone_angles(s, ModelId(0))
    var image = ramachandran_image(s, angles, 360)
    assert_equal(image.width, 360)
    # A pixel a degree: a helix dot at (-57, -47) is at column 123 and
    # row 359 - 133.
    assert_true(image.get_pixel(123, 359 - 133) == Color(214, 48, 82))
    assert_true(image.get_pixel(41, 359 - 315) == Color(214, 150, 0))
    assert_true(image.get_pixel(105, 359 - 325) == Color(80, 80, 88))
    assert_true(ramachandran_color(s, ResidueId(1)) == Color(214, 48, 82))
    # The zero lines and the frame.
    assert_true(image.get_pixel(180, 300) == Color(200, 200, 205))
    assert_true(image.get_pixel(300, 359 - 180) == Color(200, 200, 205))
    assert_true(image.get_pixel(0, 100) == Color(60, 60, 66))
    assert_true(image.get_pixel(20, 20) == Color(255, 255, 255))
    # Dots at the four corners are cut at the edges.
    var corners = List[BackboneAngles]()
    var turns: List[Tuple[Float64, Float64]] = [
        (-180.0, 180.0),
        (180.0, -180.0),
        (-180.0, -180.0),
        (180.0, 180.0),
    ]
    for t in turns:
        corners.append(
            BackboneAngles(
                ResidueId(0),
                Angle64(t[0], DEGREE64),
                Angle64(t[1], DEGREE64),
                Angle64(0.0),
                True,
                True,
                False,
            )
        )
    # A residue without a psi has no dot.
    corners.append(
        BackboneAngles(
            ResidueId(0),
            Angle64(0.0),
            Angle64(0.0),
            Angle64(0.0),
            True,
            False,
            False,
        )
    )
    var cut = ramachandran_image(s, corners, 64)
    assert_true(cut.get_pixel(1, 1) == Color(214, 48, 82))
    assert_true(cut.get_pixel(62, 62) == Color(214, 48, 82))
    assert_true(cut.get_pixel(32, 31) == Color(200, 200, 205))
    # No angles give the axes alone.
    var empty = ramachandran_image(s, List[BackboneAngles](), 64)
    assert_true(empty.get_pixel(1, 1) == Color(255, 255, 255))
    assert_true(empty.get_pixel(32, 10) == Color(200, 200, 205))
    assert_equal(plot_pixel(Angle64(-200.0, DEGREE64), 64), 0)
    assert_equal(plot_pixel(Angle64(200.0, DEGREE64), 64), 63)
    with assert_raises(contains="64 to 2048"):
        _ = ramachandran_image(s, angles, 63)
    with assert_raises(contains="64 to 2048"):
        _ = ramachandran_image(s, angles, 2049)
    corners[0].residue = ResidueId(99)
    with assert_raises(contains="residue"):
        _ = ramachandran_image(s, corners, 64)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
