# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The peptide builder, ribbons, accessible areas and surfaces."""

from core.buffer_geometry import COLOR, NORMAL, POSITION
from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.ids import (
    ATOM_RECORD,
    BY_CHAIN,
    BY_STRUCTURE,
    COIL,
    ChainId,
    HELIX,
    ModelId,
    ResidueId,
    RibbonColoring,
    STRAND,
    SecondaryKind,
)
from extensions.molecule.peptide import (
    build_peptide,
    place_atom,
    three_letter,
)
from extensions.molecule.ribbon import ribbon_geometry
from extensions.molecule.structure import (
    Atom,
    Chain,
    Model,
    Residue,
    SQUARE_ANGSTROM,
    Structure,
)
from extensions.molecule.surface import (
    accessible_areas,
    molecular_surface,
    sphere_points,
    vdw_radius,
)
from extensions.sdf.vector import V3, distance, dot, length, normalize, v3
from render.srgb import srgb_to_linear
from std.math import acos, inf, max, min, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Area64, Length64, METER


def _a() -> Float64:
    return Length64(1.0, ANGSTROM).value


def _kinds(spec: List[Tuple[SecondaryKind, Int]]) -> List[SecondaryKind]:
    var out = List[SecondaryKind]()
    for part in spec:
        for _ in range(part[1]):
            out.append(part[0])
    return out^


def _atom(s: Structure, residue: Int, name: String) raises -> V3:
    return s.atoms[s.find_atom(ResidueId(residue), name).value].position


def test_three_letter_codes() raises:
    assert_equal(three_letter("A"), "ALA")
    assert_equal(three_letter("W"), "TRP")
    with assert_raises(contains="not a standard amino acid"):
        _ = three_letter("B")
    with assert_raises(contains="not a standard amino acid"):
        _ = three_letter("AC")


def test_place_atom_keeps_bond_angle_and_torsion() raises:
    var a = v3(0, 1, 0)
    var b = v3(0, 0, 0)
    var c = v3(1, 0, 0)
    var d = place_atom(a, b, c, 1.5, pi * 2 / 3, pi / 2)
    assert_almost_equal(distance(c, d), 1.5)
    var u = normalize(b - c)
    var w = normalize(d - c)
    assert_almost_equal(acos(dot(u, w)), pi * 2 / 3)
    # A torsion of a quarter turn puts the new atom out of the plane.
    assert_almost_equal(abs(d.z), 1.5 * sqrt(3.0) / 2, atol=1e-12)


def test_helix_geometry() raises:
    var s = build_peptide("AAAAAAAAGG", _kinds([(HELIX, 10)]))
    assert_equal(len(s.residues), 10)
    # Five atoms for alanine, four for glycine.
    assert_equal(len(s.atoms), 8 * 5 + 2 * 4)
    assert_equal(s.residues[0].name, "ALA")
    assert_equal(s.residues[9].name, "GLY")
    assert_true(s.residues[4].secondary == HELIX)
    var a = _a()
    assert_almost_equal(
        distance(_atom(s, 0, "N"), _atom(s, 0, "CA")) / a, 1.458
    )
    assert_almost_equal(distance(_atom(s, 2, "C"), _atom(s, 3, "N")) / a, 1.329)
    assert_almost_equal(distance(_atom(s, 2, "C"), _atom(s, 2, "O")) / a, 1.231)
    assert_almost_equal(
        distance(_atom(s, 2, "CA"), _atom(s, 2, "CB")) / a, 1.527, atol=1e-3
    )
    # A trans peptide puts consecutive CA atoms 3.8 angstroms apart.
    assert_almost_equal(
        distance(_atom(s, 3, "CA"), _atom(s, 4, "CA")) / a, 3.80, atol=0.01
    )
    # The helix's hydrogen bond: O of residue i to N of residue i + 4.
    var bond = distance(_atom(s, 2, "O"), _atom(s, 6, "N")) / a
    assert_true(bond > 2.8 and bond < 3.3)


def test_strand_is_extended() raises:
    var s = build_peptide("VVVVV", _kinds([(STRAND, 5)]))
    var a = _a()
    var span = distance(_atom(s, 1, "CA"), _atom(s, 3, "CA")) / a
    assert_true(span > 6.4)
    var coil = build_peptide("PPPPP", _kinds([(COIL, 5)]))
    assert_true(coil.residues[2].secondary == COIL)


def test_peptide_refusals() raises:
    with assert_raises(contains="at least one residue"):
        _ = build_peptide("", List[SecondaryKind]())
    with assert_raises(contains="one secondary structure"):
        _ = build_peptide("AA", _kinds([(HELIX, 1)]))
    with assert_raises(contains="not a standard amino acid"):
        _ = build_peptide("AXA", _kinds([(HELIX, 3)]))
    with assert_raises(contains="secondary structure must be"):
        _ = build_peptide("AA", [HELIX, SecondaryKind(7)])


def _ribbon_counts(residues: Int, samples: Int, sides: Int) -> Tuple[Int, Int]:
    var rings = (residues - 1) * samples + 1
    return (rings * sides, (rings - 1) * sides * 2)


def test_ribbon_counts_and_colors() raises:
    var s = build_peptide(
        "AAAAAGGVVVVGG",
        _kinds([(HELIX, 5), (COIL, 2), (STRAND, 4), (COIL, 2)]),
    )
    var mesh = ribbon_geometry(s, ModelId(0), BY_STRUCTURE, 4, 8)
    var counts = _ribbon_counts(13, 4, 8)
    assert_equal(mesh.vertex_count(), counts[0])
    assert_equal(mesh.triangle_count(), counts[1])
    ref colors = mesh.attribute_view(String(COLOR)).data
    # The first ring is helix red.
    assert_almost_equal(colors[0], srgb_to_linear(0.89), atol=1e-6)
    ref normals = mesh.attribute_view(String(NORMAL)).data
    var worst = 0.0
    for v in range(len(normals) // 3):
        var n = v3(
            Float64(normals[3 * v]),
            Float64(normals[3 * v + 1]),
            Float64(normals[3 * v + 2]),
        )
        worst = max(worst, abs(length(n) - 1.0))
    assert_true(worst < 1e-5)
    var chained = ribbon_geometry(s, ModelId(0), BY_CHAIN, 2, 4)
    ref chain_colors = chained.attribute_view(String(COLOR)).data
    assert_almost_equal(chain_colors[0], srgb_to_linear(0.27), atol=1e-6)


def test_strand_arrows() raises:
    # A strand at the end of a chain ends in an arrow, and a strand
    # followed by a strand is a flat band.
    var s = build_peptide("VVVV", _kinds([(STRAND, 4)]))
    var mesh = ribbon_geometry(s, ModelId(0), BY_STRUCTURE, 2, 4)
    var counts = _ribbon_counts(4, 2, 4)
    assert_equal(mesh.vertex_count(), counts[0])
    ref p = mesh.attribute_view(String(POSITION)).data
    # The last ring is the point of the arrow: 0.05 angstroms wide.
    var last = counts[0] - 4
    var a = v3(
        Float64(p[3 * last]), Float64(p[3 * last + 1]), Float64(p[3 * last + 2])
    )
    var b = v3(
        Float64(p[3 * last + 6]),
        Float64(p[3 * last + 7]),
        Float64(p[3 * last + 8]),
    )
    assert_almost_equal(distance(a, b) / _a(), 0.1, atol=1e-3)


def _trace(
    cas: List[V3], has_o: List[Bool], kinds: List[SecondaryKind]
) raises -> Structure:
    """A chain of CA atoms, with O atoms one angstrom up where asked."""
    var s = Structure("TRACE")
    s.models.append(Model(1, 0, 1))
    s.chains.append(Chain("A", "A", ModelId(0), 0, len(cas)))
    var a = _a()
    for r in range(len(cas)):
        var first = len(s.atoms)
        var count = 1
        s.atoms.append(
            Atom(
                "CA",
                "C",
                first + 1,
                ATOM_RECORD,
                ".",
                cas[r] * a,
                1.0,
                Area64(0.0, SQUARE_ANGSTROM),
                ResidueId(r),
            )
        )
        if has_o[r]:
            s.atoms.append(
                Atom(
                    "O",
                    "O",
                    first + 2,
                    ATOM_RECORD,
                    ".",
                    (cas[r] + v3(0, 1, 0)) * a,
                    1.0,
                    Area64(0.0, SQUARE_ANGSTROM),
                    ResidueId(r),
                )
            )
            count = 2
        s.residues.append(
            Residue(
                "ALA", r + 1, r + 1, "?", ChainId(0), first, count, kinds[r]
            )
        )
    return s^


def test_ribbon_breaks_and_sides() raises:
    # A gap of 8 angstroms breaks the chain into pieces of three and one.
    var cas: List[V3] = [
        v3(0, 0, 0),
        v3(3.8, 0, 0),
        v3(7.6, 0, 0),
        v3(15.6, 0, 0),
    ]
    var s = _trace(cas, [True, True, True, True], _kinds([(COIL, 4)]))
    var mesh = ribbon_geometry(s, ModelId(0), BY_STRUCTURE, 2, 4)
    assert_equal(mesh.vertex_count(), _ribbon_counts(3, 2, 4)[0])
    # A trace along z with no O atoms finds its own sides.
    var along_z: List[V3] = [v3(0, 0, 0), v3(0, 0, 3.8), v3(0, 0, 7.6)]
    var bare = _trace(along_z, [False, False, False], _kinds([(HELIX, 3)]))
    var straight = ribbon_geometry(bare, ModelId(0), BY_STRUCTURE, 2, 4)
    assert_equal(straight.vertex_count(), _ribbon_counts(3, 2, 4)[0])
    # A trace along x whose first residue has no O finds a side too.
    var along_x: List[V3] = [v3(0, 0, 0), v3(3.8, 0, 0), v3(7.6, 0, 0)]
    var first_bare = _trace(along_x, [False, True, True], _kinds([(COIL, 3)]))
    var started = ribbon_geometry(first_bare, ModelId(0), BY_STRUCTURE, 2, 4)
    assert_equal(started.vertex_count(), _ribbon_counts(3, 2, 4)[0])
    # O atoms that alternate sides are flipped onto one side; an O that is
    # missing takes the side of the residue before.
    var zigzag: List[V3] = [v3(0, 0, 0), v3(3.8, 0, 0), v3(7.6, 0, 0)]
    var flips = _trace(zigzag, [True, False, True], _kinds([(STRAND, 3)]))
    flips.atoms[3].position = (v3(7.6, -1, 0)) * _a()
    var flat = ribbon_geometry(flips, ModelId(0), BY_STRUCTURE, 2, 4)
    assert_equal(flat.vertex_count(), _ribbon_counts(3, 2, 4)[0])


def test_ribbon_refusals() raises:
    var s = build_peptide("AAA", _kinds([(HELIX, 3)]))
    with assert_raises(contains="ribbon coloring"):
        _ = ribbon_geometry(s, ModelId(0), RibbonColoring(3), 4, 8)
    with assert_raises(contains="2 to 16 samples"):
        _ = ribbon_geometry(s, ModelId(0), BY_STRUCTURE, 1, 8)
    with assert_raises(contains="2 to 16 samples"):
        _ = ribbon_geometry(s, ModelId(0), BY_STRUCTURE, 17, 8)
    with assert_raises(contains="4 to 32 sides"):
        _ = ribbon_geometry(s, ModelId(0), BY_STRUCTURE, 4, 3)
    with assert_raises(contains="4 to 32 sides"):
        _ = ribbon_geometry(s, ModelId(0), BY_STRUCTURE, 4, 33)
    with assert_raises(contains="model id"):
        _ = ribbon_geometry(s, ModelId(1), BY_STRUCTURE, 4, 8)
    var one = build_peptide("A", _kinds([(HELIX, 1)]))
    with assert_raises(contains="two residues with CA"):
        _ = ribbon_geometry(one, ModelId(0), BY_STRUCTURE, 4, 8)
    # A residue with no CA, a chain with no residues, a model with none.
    var holes = _trace(
        [v3(0, 0, 0), v3(3.8, 0, 0)], [True, True], _kinds([(COIL, 2)])
    )
    holes.atoms[0].name = "N"
    holes.chains.append(Chain("B", "B", ModelId(0), 2, 0))
    holes.models[0].chain_count = 2
    holes.models.append(Model(2, 2, 0))
    with assert_raises(contains="two residues with CA"):
        _ = ribbon_geometry(holes, ModelId(0), BY_STRUCTURE, 4, 8)
    with assert_raises(contains="two residues with CA"):
        _ = ribbon_geometry(holes, ModelId(1), BY_STRUCTURE, 4, 8)


def test_radii_and_sphere_points() raises:
    assert_almost_equal(vdw_radius("c").to(ANGSTROM), 1.7)
    assert_almost_equal(vdw_radius("Se").to(ANGSTROM), 1.9)
    assert_almost_equal(vdw_radius("FE").to(ANGSTROM), 1.8)
    var points = sphere_points(50)
    assert_equal(len(points), 50)
    var center = v3(0, 0, 0)
    for p in points:
        assert_almost_equal(length(p), 1.0, atol=1e-12)
        center = center + p
    assert_true(length(center) < 1e-9 * 50 + 0.05)
    with assert_raises(contains="1 to 10000 points"):
        _ = sphere_points(0)
    with assert_raises(contains="1 to 10000 points"):
        _ = sphere_points(10001)


def _atoms(elements: List[String], places: List[V3]) raises -> Structure:
    var s = Structure("ATOMS")
    s.models.append(Model(1, 0, 1))
    s.chains.append(Chain("A", "A", ModelId(0), 0, 1))
    s.residues.append(
        Residue("LIG", 1, 1, "?", ChainId(0), 0, len(elements), COIL)
    )
    for index in range(len(elements)):
        s.atoms.append(
            Atom(
                "X" + String(index),
                elements[index],
                index + 1,
                ATOM_RECORD,
                ".",
                places[index] * _a(),
                1.0,
                Area64(0.0, SQUARE_ANGSTROM),
                ResidueId(0),
            )
        )
    return s^


def test_accessible_area_of_one_and_two_atoms() raises:
    var probe = Length64(1.4, ANGSTROM)
    var lone = _atoms(["C"], [v3(0, 0, 0)])
    var area = accessible_areas(lone, ModelId(0), probe, 100)[0]
    var r = 3.1 * _a()
    assert_almost_equal(area.value, 4 * pi * r * r, atol=1e-30)
    # Two carbons 3 angstroms apart with no probe: each loses a cap of
    # height 0.2 angstroms, 2 pi R h of area.
    var pair = _atoms(["C", "C", "O"], [v3(0, 0, 0), v3(3, 0, 0), v3(40, 0, 0)])
    var areas = accessible_areas(pair, ModelId(0), Length64(0, METER), 2000)
    var R = 1.7
    var exact = (4 * pi * R * R - 2 * pi * R * 0.2) * _a() * _a()
    assert_true(abs(areas[0].value - exact) < 0.01 * exact)
    assert_true(abs(areas[1].value - exact) < 0.01 * exact)
    # Two carbons 3.5 angstroms apart share cells but do not touch.
    var apart = _atoms(["C", "C"], [v3(0, 0, 0), v3(3.5, 0, 0)])
    var whole = accessible_areas(apart, ModelId(0), Length64(0, METER), 50)
    assert_almost_equal(
        whole[0].value, 4 * pi * R * R * _a() * _a(), atol=1e-30
    )
    # The far oxygen is alone.
    var oxygen = 4 * pi * 1.52 * 1.52 * _a() * _a()
    assert_almost_equal(areas[2].value, oxygen, atol=1e-30)
    with assert_raises(contains="probe radius"):
        _ = accessible_areas(lone, ModelId(0), Length64(-1, METER), 10)
    with assert_raises(contains="probe radius"):
        _ = accessible_areas(
            lone, ModelId(0), Length64(inf[DType.float64](), METER), 10
        )


def test_surface_of_one_atom() raises:
    var lone = _atoms(["C", "XX"], [v3(0, 0, 0), v3(2.5, 0, 0)])
    var mesh = molecular_surface(
        lone, ModelId(0), Length64(0, METER), Length64(0.3, ANGSTROM)
    )
    assert_true(mesh.triangle_count() > 0)
    ref p = mesh.attribute_view(String(POSITION)).data
    ref c = mesh.attribute_view(String(COLOR)).data
    var carbon = srgb_to_linear(Float32(144) / 255)
    var gray = srgb_to_linear(Float32(200) / 255)
    var saw_carbon = False
    var saw_gray = False
    var worst = 0.0
    for v in range(len(p) // 3):
        var at = v3(
            Float64(p[3 * v]), Float64(p[3 * v + 1]), Float64(p[3 * v + 2])
        )
        var to_carbon = distance(at, v3(0, 0, 0)) / _a() - 1.7
        var to_other = distance(at, v3(2.5, 0, 0) * _a()) / _a() - 1.8
        worst = max(worst, min(abs(to_carbon), abs(to_other)))
        if abs(c[3 * v] - carbon) < 1e-6:
            saw_carbon = True
        if abs(c[3 * v] - gray) < 1e-6:
            saw_gray = True
    # Each vertex lies on one of the two spheres.
    assert_true(worst < 0.06)
    assert_true(saw_carbon)
    # An element with no CPK color is gray.
    assert_true(saw_gray)
    with assert_raises(contains="spacing must be positive"):
        _ = molecular_surface(
            lone, ModelId(0), Length64(0, METER), Length64(0, METER)
        )
    with assert_raises(contains="spacing must be positive"):
        _ = molecular_surface(
            lone,
            ModelId(0),
            Length64(0, METER),
            Length64(inf[DType.float64](), METER),
        )
    with assert_raises(contains="at most 2^24 points"):
        _ = molecular_surface(
            lone, ModelId(0), Length64(0, METER), Length64(0.001, ANGSTROM)
        )
    with assert_raises(contains="probe radius"):
        _ = molecular_surface(
            lone, ModelId(0), Length64(-1, METER), Length64(0.3, ANGSTROM)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
