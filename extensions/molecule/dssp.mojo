# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Assign helices and strands from the backbone, after Kabsch and Sander.

Many files carry no secondary structure records, such as the output of a
structure prediction. `assign_secondary` finds the backbone hydrogen
bonds and marks the helices and strands that they make, as DSSP does.

The energy of a bond from the N-H of one residue to the C=O of another is
DSSP's electrostatic model, in kcal/mol:

    E = 0.084 * 332 * (1/r(O,N) + 1/r(C,H) - 1/r(O,H) - 1/r(C,N))

with distances in angstroms. A bond exists when `E` is below -0.5. The H
of residue `i` is 1 angstrom from its N, along the direction from the O
to the C of residue `i - 1`. The first residue of a chain and a proline
have no H.

A 4-turn at `i` is a bond from the C=O of `i` to the N-H of `i + 4`. Two
4-turns in a row, at `i - 1` and `i`, make residues `i` to `i + 3` a
helix. A bridge pairs two residues three or more apart: antiparallel
when they bond to each other, or when `i - 1` bonds to `j + 1` and
`j - 1` to `i + 1`; parallel when `i - 1` bonds to `j` and `j` to `i + 1`,
or `j - 1` to `i` and `i` to `j + 1`. Two bridges of one kind in a row
make a ladder, and a residue of a ladder is a strand. A helix wins over
a strand.

This is DSSP's core. It does not report 3-10 or pi helices, turns, bends,
isolated bridges or beta bulges.
"""

from extensions.molecule.ids import (
    COIL,
    HELIX,
    ModelId,
    ResidueId,
    STRAND,
    SecondaryKind,
)
from extensions.molecule.structure import Structure
from extensions.chemistry.quantities import ANGSTROM
from extensions.sdf.vector import V3, distance, length, v3
from units.si import Length64

# A bond exists below this energy, in kcal/mol.
comptime BOND_ENERGY = -0.5
# Two residues whose CA atoms are farther apart than this, in angstroms,
# cannot bond.
comptime CA_REACH = 9.0
# A C to N distance above this, in angstroms, breaks the chain.
comptime PEPTIDE_REACH = 2.5


def bond_energy(n: V3, h: V3, c: V3, o: V3) -> Float64:
    """Return the energy of a bond from N-H to C=O, in kcal/mol.

    Args:
        n: The donor's N, in angstroms.
        h: The donor's H, in angstroms.
        c: The acceptor's C, in angstroms.
        o: The acceptor's O, in angstroms.

    Returns:
        DSSP's electrostatic energy. Atoms closer than 0.5 angstroms give
        -9.9, DSSP's floor.
    """
    var on = distance(o, n)
    var ch = distance(c, h)
    var oh = distance(o, h)
    var cn = distance(c, n)
    if min4(on, ch, oh, cn) < 0.5:
        return -9.9
    return 0.084 * 332.0 * (1.0 / on + 1.0 / ch - 1.0 / oh - 1.0 / cn)


def min4(a: Float64, b: Float64, c: Float64, d: Float64) -> Float64:
    """Return the least of four values.

    Args:
        a: The first.
        b: The second.
        c: The third.
        d: The fourth.

    Returns:
        The least.
    """
    return min(min(a, b), min(c, d))


def secondary_from_bonds(bonds: List[Bool], count: Int) raises -> List[Int]:
    """Return the helices and strands that a bond matrix makes.

    Args:
        bonds: `bonds[i * count + j]` is whether the C=O of residue `i`
            bonds to the N-H of residue `j`.
        count: The number of residues.

    Returns:
        One kind per residue: 0 coil, 1 helix and 2 strand, the values of
        `COIL`, `HELIX` and `STRAND`.

    Raises:
        Error: If the matrix is not `count` by `count`.
    """
    if len(bonds) != count * count:
        raise Error("A bond matrix must be square")
    var kind = List[Int](length=count, fill=0)
    var turn = List[Bool](length=count, fill=False)
    for i in range(count - 4):
        turn[i] = bonds[i * count + i + 4]
    for i in range(1, count - 4):
        if turn[i - 1] and turn[i]:
            for k in range(i, i + 4):  # pragma: no branch
                kind[k] = HELIX.value
    # 1 for an antiparallel bridge and 2 for a parallel one, per pair.
    var bridge = List[Int](length=count * count, fill=0)
    for i in range(1, count - 1):
        for j in range(i + 3, count - 1):
            var anti = (bonds[i * count + j] and bonds[j * count + i]) or (
                bonds[(i - 1) * count + j + 1]
                and bonds[(j - 1) * count + i + 1]
            )
            var parallel = (
                bonds[(i - 1) * count + j] and bonds[j * count + i + 1]
            ) or (bonds[(j - 1) * count + i] and bonds[i * count + j + 1])
            if anti:
                bridge[i * count + j] = 1
            elif parallel:
                bridge[i * count + j] = 2
    for i in range(1, count - 1):
        for j in range(i + 3, count - 1):
            var type = bridge[i * count + j]
            if type == 0:
                continue
            # The next bridge of a ladder runs to j - 1 when antiparallel,
            # and to j + 1 when parallel.
            var next_j = j - 1 if type == 1 else j + 1
            var follows = (
                i + 1 < count - 1
                and next_j < count
                and bridge[(i + 1) * count + next_j] == type
            )
            if follows:
                for k in [i, i + 1, j, next_j]:
                    if kind[k] != HELIX.value:
                        kind[k] = STRAND.value
    return kind^


def _backbone(
    structure: Structure, residue: Int, name: String
) raises -> Tuple[Bool, V3]:
    """Return whether a residue has an atom, and its place in angstroms."""
    var atom = structure.find_atom(ResidueId(residue), name)
    if atom.value < 0:
        return (False, v3(0, 0, 0))
    var scale = 1.0 / Length64(1.0, ANGSTROM).value
    return (True, structure.atoms[atom.value].position * scale)


def assign_secondary(mut structure: Structure, model: ModelId) raises:
    """Replace the secondary structure of a model's residues with DSSP's.

    Residues without all of N, CA, C and O are coil and take no part.

    Args:
        structure: The structure. Its residues of the model change.
        model: The model.

    Raises:
        Error: If the model id names no model.
    """
    structure.require_model(model)
    ref m = structure.models[model.value]
    var picked = List[Int]()
    var places = List[V3]()
    var chains = List[Int]()
    for c in range(m.first_chain, m.first_chain + m.chain_count):
        ref chain = structure.chains[c]
        for r in range(
            chain.first_residue, chain.first_residue + chain.residue_count
        ):
            structure.residues[r].secondary = COIL
            var whole = True
            var atoms = List[V3]()
            for name in ["N", "CA", "C", "O"]:
                var found = _backbone(structure, r, name)
                whole = whole and found[0]
                atoms.append(found[1])
            if not whole:
                continue
            picked.append(r)
            places.extend(atoms^)
            chains.append(c)
    var count = len(picked)
    # The H of each residue, where it has one.
    var hydrogen = List[V3]()
    var has_h = List[Bool]()
    for k in range(count):
        var linked = (
            k > 0
            and chains[k - 1] == chains[k]
            and distance(places[4 * (k - 1) + 2], places[4 * k]) < PEPTIDE_REACH
        )
        var donor = linked and structure.residues[picked[k]].name != "PRO"
        var h = v3(0, 0, 0)
        if donor:
            var back = places[4 * (k - 1) + 2] - places[4 * (k - 1) + 3]
            h = places[4 * k] + back * (1.0 / length(back))
        hydrogen.append(h)
        has_h.append(donor)
    var bonds = List[Bool](length=count * count, fill=False)
    for i in range(count):
        # The outer loop runs only when there is a residue.
        for j in range(count):  # pragma: no branch
            if i == j or not has_h[j]:
                continue
            if distance(places[4 * i + 1], places[4 * j + 1]) > CA_REACH:
                continue
            var energy = bond_energy(
                places[4 * j], hydrogen[j], places[4 * i + 2], places[4 * i + 3]
            )
            bonds[i * count + j] = energy < BOND_ENERGY
    var kinds = secondary_from_bonds(bonds, count)
    for k in range(count):
        structure.residues[picked[k]].secondary = SecondaryKind(kinds[k])
