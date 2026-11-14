# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The interface between two chains: the area that they bury.

Two chains that bind cover part of each other's surface. The buried
surface area is

    ASA(A alone) + ASA(B alone) - ASA(A with B)

over the atoms of the two chains. Other chains of the model do not
count. An atom that loses accessible area when the other chain is there
is at the interface. `chain_interface` gives the buried area of each
atom, of each residue and in all.

Each area comes from `accessible_areas`, with the same points on each
sphere alone and with the other chain. A point that the other chain
covers is buried, so no atom can gain area: each buried area is zero or
more.
"""

from extensions.molecule.ids import ChainId, ModelId, ResidueId
from extensions.molecule.structure import Chain, Model, Residue, Structure
from extensions.molecule.surface import accessible_areas
from units.si import Area64, Length64, SQUARE_METER


struct ChainInterface(Movable):
    """The area that two chains bury, by atom and by residue."""

    var atoms: List[Int]
    """The atoms of both chains, as indexes into `structure.atoms`."""
    var atom_buried: List[Float64]
    """The buried area of each atom of `atoms`, in square meters."""
    var residues: List[ResidueId]
    """The residues of both chains that bury area, in order."""
    var residue_buried: List[Float64]
    """The buried area of each residue of `residues`, in square meters."""

    def __init__(out self):
        """Create an empty interface."""
        self.atoms = List[Int]()
        self.atom_buried = List[Float64]()
        self.residues = List[ResidueId]()
        self.residue_buried = List[Float64]()

    def total(self) -> Area64:
        """Return the buried surface area of the two chains.

        Returns:
            The sum over every atom of both chains.
        """
        var sum = 0.0
        for value in self.atom_buried:
            sum += value
        return Area64(sum, SQUARE_METER)

    def buried(self, row: Int) raises -> Area64:
        """Return the buried area of one interface residue.

        Args:
            row: The row of `residues`, from zero.

        Returns:
            The area that the residue buries.

        Raises:
            Error: If the row is outside the interface.
        """
        if row < 0 or row >= len(self.residues):
            raise Error("An interface row is outside the interface")
        return Area64(self.residue_buried[row], SQUARE_METER)


def _subset(
    structure: Structure, chains: List[Int]
) -> Tuple[Structure, List[Int]]:
    """Return a structure of one model that holds only some chains, and
    the original index of each of its atoms."""
    var out = Structure(structure.name)
    var origin = List[Int]()
    out.models.append(Model(1, 0, len(chains)))
    for c in chains:  # pragma: no branch
        ref chain = structure.chains[c]
        var chain_id = len(out.chains)
        out.chains.append(
            Chain(
                chain.label,
                chain.author,
                ModelId(0),
                len(out.residues),
                chain.residue_count,
            )
        )
        for r in range(
            chain.first_residue, chain.first_residue + chain.residue_count
        ):
            ref residue = structure.residues[r]
            var copy = residue.copy()
            copy.chain = ChainId(chain_id)
            copy.first_atom = len(out.atoms)
            var residue_id = ResidueId(len(out.residues))
            out.residues.append(copy^)
            for a in range(
                residue.first_atom, residue.first_atom + residue.atom_count
            ):
                var atom = structure.atoms[a].copy()
                atom.residue = residue_id
                out.atoms.append(atom^)
                origin.append(a)
    return (out^, origin^)


def chain_interface(
    structure: Structure,
    model: ModelId,
    first: ChainId,
    second: ChainId,
    probe: Length64,
    points: Int,
) raises -> ChainInterface:
    """Return the area that two chains of a model bury in each other.

    Args:
        structure: The structure.
        model: The model of both chains.
        first: The first chain.
        second: The second chain. Not the first.
        probe: The probe radius, such as 1.4 angstroms.
        points: The points on each sphere, from 1 to 10000.

    Returns:
        The buried area of each atom of both chains, and of each residue
        that buries area.

    Raises:
        Error: If a chain is not in the model, the two chains are one, a
            chain has no atoms, or the probe or the points are out of
            range.
    """
    structure.require_model(model)
    structure.require_chain(first)
    structure.require_chain(second)
    if first.value == second.value:
        raise Error("An interface needs two different chains")
    ref m = structure.models[model.value]
    var low = m.first_chain
    var high = m.first_chain + m.chain_count
    if (
        first.value < low
        or first.value >= high
        or second.value < low
        or second.value >= high
    ):
        raise Error("Both chains of an interface must be in the model")
    var one: List[Int] = [first.value]
    var other: List[Int] = [second.value]
    var pair: List[Int] = [first.value, second.value]
    var alone_a = _subset(structure, one)
    var alone_b = _subset(structure, other)
    var both = _subset(structure, pair)
    if len(alone_a[1]) == 0 or len(alone_b[1]) == 0:
        raise Error("Both chains of an interface need atoms")
    var areas_a = accessible_areas(alone_a[0], ModelId(0), probe, points)
    var areas_b = accessible_areas(alone_b[0], ModelId(0), probe, points)
    var areas = accessible_areas(both[0], ModelId(0), probe, points)
    var alone = List[Float64]()
    for area in areas_a:  # pragma: no branch
        alone.append(area.to(SQUARE_METER))
    for area in areas_b:  # pragma: no branch
        alone.append(area.to(SQUARE_METER))
    var out = ChainInterface()
    var last = -1
    for k in range(len(areas)):  # pragma: no branch
        var atom = both[1][k]
        # A point that the other chain covers was open alone, so the
        # difference is zero or more.
        var buried = alone[k] - areas[k].to(SQUARE_METER)
        out.atoms.append(atom)
        out.atom_buried.append(buried)
        if buried <= 0:
            continue
        var residue = structure.atoms[atom].residue.value
        if residue != last:
            out.residues.append(ResidueId(residue))
            out.residue_buried.append(0)
            last = residue
        out.residue_buried[len(out.residue_buried) - 1] += buried
    return out^
