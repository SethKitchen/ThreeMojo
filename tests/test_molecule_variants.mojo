# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Missense variants read and placed on an ideal helix."""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.accessibility import residue_accessibility
from extensions.molecule.ids import (
    ChainId,
    HELIX,
    ModelId,
    ResidueId,
    SecondaryKind,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.structure import (
    Chain,
    Model,
    SQUARE_ANGSTROM,
    Structure,
)
from extensions.molecule.surface import accessible_areas
from extensions.molecule.variants import (
    Variant,
    VariantSite,
    parse_variant,
    variant_sites,
)
from extensions.sdf.vector import distance
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Area64, Length64, METER


def _helix() raises -> Structure:
    """A helix of 16 residues, each atom with a B-factor of ten times its
    residue number."""
    var kinds = List[SecondaryKind]()
    for _ in range(16):
        kinds.append(HELIX)
    var s = build_peptide("MKDERLAVHGFYSWTK", kinds)
    for a in range(len(s.atoms)):
        var r = s.atoms[a].residue.value
        s.atoms[a].b_factor = Area64(10.0 * Float64(r + 1), SQUARE_ANGSTROM)
    return s^


def test_parse() raises:
    var forms: List[String] = ["R175H", "p.R175H", "p.Arg175His", "p.arg175HIS"]
    for f in forms:
        var v = parse_variant(f)
        assert_equal(v.wild, "R")
        assert_equal(v.position, 175)
        assert_equal(v.mutant, "H")
        assert_equal(v.name(), "R175H")
    var shapes: List[String] = ["R175", "175H", "", "p."]
    for f in shapes:
        with assert_raises(contains="a number and an amino acid"):
            _ = parse_variant(f)
    var broken: List[String] = ["R1A5H", "R1.5H"]
    for f in broken:
        with assert_raises(contains="digits only"):
            _ = parse_variant(f)
    var codes: List[String] = ["X12A", "R12X", "r12h", "R12*"]
    for f in codes:
        with assert_raises(contains="standard"):
            _ = parse_variant(f)
    with assert_raises(contains="not one of twenty"):
        _ = parse_variant("Arg12Xyz")
    with assert_raises(contains="1 or more"):
        _ = parse_variant("R0H")
    with assert_raises(contains="changes its amino acid"):
        _ = parse_variant("R12R")


def _contacts(s: Structure, residue: Int, reach: Float64) -> List[Int]:
    """The other residues with an atom within reach, by a search of every
    pair of atoms."""
    var out = List[Int]()
    for r in range(len(s.residues)):
        if r == residue:
            continue
        var touch = False
        ref a = s.residues[residue]
        ref b = s.residues[r]
        for i in range(a.first_atom, a.first_atom + a.atom_count):
            for j in range(b.first_atom, b.first_atom + b.atom_count):
                if distance(s.atoms[i].position, s.atoms[j].position) <= reach:
                    touch = True
        if touch:
            out.append(r)
    return out^


def test_sites() raises:
    var s = _helix()
    var variants = List[Variant]()
    for name in ["K2E", "D3N", "H9Y", "G10W", "R5W"]:
        variants.append(parse_variant(name))
    var reach = Length64(4.5, ANGSTROM)
    var sites = variant_sites(s, ModelId(0), ChainId(0), variants, reach)
    assert_equal(len(sites), 5)
    var charges: List[Int] = [-2, 1, 0, 0, -1]
    var hydropathy: List[Float64] = [0.4, 0.0, 1.9, -0.5, 3.6]
    var scores: List[Int] = [1, 1, 2, -2, -3]
    var numbers: List[Int] = [2, 3, 9, 10, 5]
    var areas = accessible_areas(s, ModelId(0), Length64(1.4, ANGSTROM), 480)
    var access = residue_accessibility(s, ModelId(0), areas)
    for n in range(5):
        ref site = sites[n]
        var r = numbers[n] - 1
        assert_equal(site.residue.value, r)
        assert_equal(site.charge_change, charges[n])
        assert_almost_equal(site.hydropathy_change, hydropathy[n])
        assert_equal(site.blosum, scores[n])
        assert_true(site.secondary == HELIX)
        assert_almost_equal(
            site.b_factor.to(SQUARE_ANGSTROM), 10.0 * Float64(numbers[n])
        )
        assert_equal(site.relative_accessibility, access[r].relative)
        var want = _contacts(s, r, reach.to(METER))
        assert_equal(len(site.contacts), len(want))
        for c in range(len(want)):
            assert_equal(site.contacts[c].value, want[c])
        # The neighbors along the chain touch through the peptide bond.
        assert_true(want[0] <= r - 1)
    assert_equal(
        len(variant_sites(s, ModelId(0), ChainId(0), List[Variant](), reach)),
        0,
    )


def test_refusals() raises:
    var s = _helix()
    var reach = Length64(4.5, ANGSTROM)
    var wrong = List[Variant]()
    wrong.append(parse_variant("A3N"))
    with assert_raises(contains="the residue there is ASP"):
        _ = variant_sites(s, ModelId(0), ChainId(0), wrong, reach)
    var far = List[Variant]()
    far.append(parse_variant("K99E"))
    with assert_raises(contains="no residue of that number"):
        _ = variant_sites(s, ModelId(0), ChainId(0), far, reach)
    var reaches: List[Float64] = [0.0, inf[DType.float64]()]
    for d in reaches:
        with assert_raises(contains="reach"):
            _ = variant_sites(
                s, ModelId(0), ChainId(0), far, Length64(d, METER)
            )
    with assert_raises(contains="chain"):
        _ = variant_sites(s, ModelId(0), ChainId(3), far, reach)
    with assert_raises(contains="model"):
        _ = variant_sites(s, ModelId(2), ChainId(0), far, reach)
    # A second model whose chain holds the same residues.
    var two = s.copy()
    two.models.append(Model(2, 1, 1))
    two.chains.append(Chain("B", "B", ModelId(1), 0, 16))
    with assert_raises(contains="not in the model"):
        _ = variant_sites(two, ModelId(0), ChainId(1), far, reach)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
