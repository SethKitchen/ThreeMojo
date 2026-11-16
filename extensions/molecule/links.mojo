# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Disulfide bonds and salt bridges between the side chains of a model.

Two kinds of link hold a fold together beside the backbone:

- A disulfide bond joins the SG atoms of two cysteines, about 2.05
  angstroms apart. `disulfide_bonds` lists each pair of cysteines whose
  SG atoms are at most a cutoff apart, such as 2.5 angstroms.
- A salt bridge joins an acidic and a basic side chain. `salt_bridges`
  lists each aspartate or glutamate with a carboxylate oxygen (OD1, OD2,
  OE1 or OE2) at most a cutoff, such as 4.0 angstroms, from a nitrogen
  of a lysine (NZ) or an arginine (NE, NH1 or NH2). This is the rule of
  Barlow and Thornton. A histidine is left out, as its charge depends on
  the pH.

Each pair of residues is listed once, with the least distance of its
atoms, in the order of the first residue and then the second. A model's
atoms are compared only with atoms of the same model.
"""

from extensions.molecule.ids import ModelId, ResidueId
from extensions.molecule.structure import Structure
from extensions.sdf.vector import distance
from std.math import isfinite
from units.si import Length64, METER


@fieldwise_init
struct ResiduePair(Copyable, Movable):
    """Two residues that a side-chain link joins."""

    var first: ResidueId
    """The first residue: the lower cysteine, or the acidic residue."""
    var second: ResidueId
    """The second residue: the higher cysteine, or the basic residue."""
    var distance: Length64
    """The least distance between their linking atoms."""


def _atoms(
    structure: Structure,
    model: ModelId,
    residues: List[String],
    names: List[String],
) raises -> List[Int]:
    """Return the atoms of a model with one of some names, in residues
    with one of some names."""
    var span = structure.model_atoms(model)
    var out = List[Int]()
    for a in range(span[0], span[0] + span[1]):  # pragma: no branch
        ref atom = structure.atoms[a]
        var residue = structure.residues[atom.residue.value].name
        if atom.name in names and residue in residues:
            out.append(a)
    return out^


def _pairs(
    structure: Structure,
    first: List[Int],
    second: List[Int],
    cutoff: Length64,
    distinct: Bool,
) raises -> List[ResiduePair]:
    """Return each pair of residues with atoms of the two lists in reach."""
    var reach = cutoff.to(METER)
    if not (reach > 0) or not isfinite(reach):
        raise Error("A link cutoff must be positive and finite")
    var out = List[ResiduePair]()
    for a in first:
        for b in second:
            var ra = structure.atoms[a].residue.value
            var rb = structure.atoms[b].residue.value
            # A cysteine pairs with a higher one only, and never itself.
            if distinct and ra >= rb:
                continue
            var d = distance(
                structure.atoms[a].position, structure.atoms[b].position
            )
            if d > reach:
                continue
            var found = -1
            for k in range(len(out)):
                if out[k].first.value == ra and out[k].second.value == rb:
                    found = k
            if found < 0:
                out.append(
                    ResiduePair(
                        ResidueId(ra), ResidueId(rb), Length64(d, METER)
                    )
                )
            elif d < out[found].distance.to(METER):
                out[found].distance = Length64(d, METER)
    # Order by the first residue, then the second.
    var span = len(structure.residues)
    for i in range(1, len(out)):
        var j = i
        while j > 0 and _key(out[j - 1], span) > _key(out[j], span):
            var swap = out[j - 1].copy()
            out[j - 1] = out[j].copy()
            out[j] = swap^
            j -= 1
    return out^


def _key(pair: ResiduePair, span: Int) -> Int:
    """Return a key that orders pairs by first residue, then second."""
    return pair.first.value * span + pair.second.value


def disulfide_bonds(
    structure: Structure, model: ModelId, cutoff: Length64
) raises -> List[ResiduePair]:
    """Return each pair of cysteines whose SG atoms are within a cutoff.

    Args:
        structure: The structure.
        model: The model.
        cutoff: The largest SG to SG distance, such as 2.5 angstroms.
            Positive and finite.

    Returns:
        The pairs, the lower residue first.

    Raises:
        Error: If the model id names no model, or the cutoff is not
            positive and finite.
    """
    var cysteines: List[String] = ["CYS"]
    var sulfur: List[String] = ["SG"]
    var atoms = _atoms(structure, model, cysteines, sulfur)
    return _pairs(structure, atoms, atoms, cutoff, True)


def salt_bridges(
    structure: Structure, model: ModelId, cutoff: Length64
) raises -> List[ResiduePair]:
    """Return each acidic and basic residue pair within a cutoff.

    Args:
        structure: The structure.
        model: The model.
        cutoff: The largest oxygen to nitrogen distance, such as 4.0
            angstroms. Positive and finite.

    Returns:
        The pairs, the aspartate or glutamate first and the lysine or
        arginine second.

    Raises:
        Error: If the model id names no model, or the cutoff is not
            positive and finite.
    """
    var acids: List[String] = ["ASP", "GLU"]
    var oxygens: List[String] = ["OD1", "OD2", "OE1", "OE2"]
    var bases: List[String] = ["LYS", "ARG"]
    var nitrogens: List[String] = ["NZ", "NE", "NH1", "NH2"]
    return _pairs(
        structure,
        _atoms(structure, model, acids, oxygens),
        _atoms(structure, model, bases, nitrogens),
        cutoff,
        False,
    )
