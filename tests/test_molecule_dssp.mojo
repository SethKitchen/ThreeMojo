# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Secondary structure assigned from backbone hydrogen bonds."""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.dssp import (
    assign_secondary,
    bond_energy,
    secondary_from_bonds,
)
from extensions.molecule.ids import (
    COIL,
    ChainId,
    HELIX,
    ModelId,
    ResidueId,
    STRAND,
    SecondaryKind,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.structure import Chain, Model, Structure
from extensions.sdf.vector import v3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64


def _kinds(spec: List[Tuple[SecondaryKind, Int]]) -> List[SecondaryKind]:
    var out = List[SecondaryKind]()
    for part in spec:
        for _ in range(part[1]):
            out.append(part[0])
    return out^


def _code(s: Structure) -> String:
    var out = String("")
    for r in s.residues:
        if r.secondary == HELIX:
            out += "H"
        elif r.secondary == STRAND:
            out += "E"
        else:
            out += "-"
    return out^


def test_bond_energy() raises:
    # A straight N-H...O=C bond with N to O at 2.9 angstroms.
    var n = v3(0, 0, 0)
    var h = v3(1, 0, 0)
    var o = v3(2.9, 0, 0)
    var c = v3(4.13, 0, 0)
    var expected = 0.084 * 332 * (1 / 2.9 + 1 / 3.13 - 1 / 1.9 - 1 / 4.13)
    assert_almost_equal(bond_energy(n, h, c, o), expected)
    assert_true(bond_energy(n, h, c, o) < -0.5)
    # Atoms that overlap give DSSP's floor.
    assert_equal(bond_energy(n, h, c, v3(0.2, 0, 0)), -9.9)


def test_helices_from_coordinates() raises:
    var helix = build_peptide("AAAAAAAAAAAAAA", _kinds([(HELIX, 14)]))
    # Clear the builder's marks; DSSP finds them again.
    for index in range(len(helix.residues)):
        helix.residues[index].secondary = STRAND
    assign_secondary(helix, ModelId(0))
    assert_equal(_code(helix), "-HHHHHHHHHHHH-")
    var flanked = build_peptide(
        "GSGAAAAAAAAAAAAGSG", _kinds([(COIL, 3), (HELIX, 12), (COIL, 3)])
    )
    assign_secondary(flanked, ModelId(0))
    assert_equal(_code(flanked), "---HHHHHHHHHHHH---")
    # A lone strand has no partner, so no strand.
    var strand = build_peptide("VVVVVVVV", _kinds([(STRAND, 8)]))
    assign_secondary(strand, ModelId(0))
    assert_equal(_code(strand), "--------")


def _matrix(count: Int, pairs: List[Tuple[Int, Int]]) -> List[Bool]:
    """A bond matrix with the C=O of `pair[0]` bonded to the N-H of
    `pair[1]` for each pair."""
    var out = List[Bool](length=count * count, fill=False)
    for pair in pairs:
        out[pair[0] * count + pair[1]] = True
    return out^


def _letters(kinds: List[Int]) -> String:
    var out = String("")
    for k in kinds:
        if k == HELIX.value:
            out += "H"
        elif k == STRAND.value:
            out += "E"
        else:
            out += "-"
    return out^


def test_ladders_from_bonds() raises:
    # Antiparallel: 2 and 9 bond to each other, and 3 and 8 do too.
    var anti = _matrix(12, [(2, 9), (9, 2), (3, 8), (8, 3)])
    assert_equal(_letters(secondary_from_bonds(anti, 12)), "--EE----EE--")
    # Antiparallel by the outer pair: 1 to 10 and 8 to 3 make the bridge
    # of 2 and 9; the bond pair 3, 8 makes the next.
    var outer = _matrix(12, [(1, 10), (8, 3), (3, 8), (8, 3)])
    assert_equal(_letters(secondary_from_bonds(outer, 12)), "--EE----EE--")
    # Parallel: 1 to 7 and 7 to 3 bridge 2 and 7; 2 to 8 and 8 to 4
    # bridge 3 and 8.
    var parallel = _matrix(12, [(1, 7), (7, 3), (2, 8), (8, 4)])
    assert_equal(_letters(secondary_from_bonds(parallel, 12)), "--EE---EE---")
    # Parallel by the other pair: 6 to 2 and 2 to 8 bridge 2 and 7.
    var other = _matrix(12, [(6, 2), (2, 8), (7, 3), (3, 9)])
    assert_equal(_letters(secondary_from_bonds(other, 12)), "--EE---EE---")
    # One bridge alone is not a strand.
    var lone = _matrix(12, [(2, 9), (9, 2)])
    assert_equal(_letters(secondary_from_bonds(lone, 12)), "------------")
    # Half a pair is no bridge.
    var half = _matrix(12, [(2, 9), (3, 8), (8, 3), (1, 7), (2, 8)])
    assert_equal(_letters(secondary_from_bonds(half, 12)), "------------")
    with assert_raises(contains="must be square"):
        _ = secondary_from_bonds(List[Bool](length=5, fill=False), 2)


def test_helix_wins_over_strand() raises:
    # 4-turns at 0, 1 and 2 make 1 to 5 a helix; a ladder of 2, 3 with
    # 9, 8 overlaps it.
    var bonds = _matrix(
        12, [(0, 4), (1, 5), (2, 6), (2, 9), (9, 2), (3, 8), (8, 3)]
    )
    assert_equal(_letters(secondary_from_bonds(bonds, 12)), "-HHHHH--EE--")
    assert_equal(len(secondary_from_bonds(List[Bool](), 0)), 0)


def test_backbone_gaps() raises:
    # A helix with a proline in it, a residue with no O, a residue with no
    # N, and a second chain far away.
    var s = build_peptide("AAAAAPAAAAAAA", _kinds([(HELIX, 13)]))
    var far = build_peptide("AAAAAAAAAAAA", _kinds([(HELIX, 12)]))
    var offset = len(s.atoms)
    var residues = len(s.residues)
    for atom in far.atoms:
        var moved = atom.copy()
        moved.position = moved.position + v3(5e-9, 0, 0)
        moved.residue.value += residues
        s.atoms.append(moved^)
    for residue in far.residues:
        var moved = residue.copy()
        moved.first_atom += offset
        moved.chain = ChainId(1)
        s.residues.append(moved^)
    s.chains.append(Chain("B", "B", ModelId(0), residues, len(far.residues)))
    s.models[0].chain_count = 2
    # Residue 3 loses its O, and residue 9 its N.
    s.atoms[s.find_atom(ResidueId(3), "O").value].name = "OXT"
    s.atoms[s.find_atom(ResidueId(9), "N").value].name = "NX"
    assign_secondary(s, ModelId(0))
    var code = _code(s)
    assert_equal(String(code[byte=3:4]), "-")
    assert_equal(String(code[byte=9:10]), "-")
    assert_equal(String(code[byte=13:]), "-HHHHHHHHHH-")
    with assert_raises(contains="model id"):
        assign_secondary(s, ModelId(4))
    # A model with no chains, and a chain with no residues.
    var empty = Structure("EMPTY")
    empty.models.append(Model(1, 0, 0))
    empty.models.append(Model(2, 0, 1))
    empty.chains.append(Chain("A", "A", ModelId(1), 0, 0))
    assign_secondary(empty, ModelId(0))
    assign_secondary(empty, ModelId(1))
    assert_equal(len(empty.residues), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
