# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Formal charges of a protein, and their Coulomb potential.

`formal_charges` places the charges of the groups that carry one at
pH 7:

| Group | Atoms | Charge |
|---|---|---|
| Arginine | NH1 and NH2 | +0.5 each |
| Lysine | NZ | +1 |
| Aspartate | OD1 and OD2 | -0.5 each |
| Glutamate | OE1 and OE2 | -0.5 each |
| The N terminus of a chain | N of its first amino acid | +1 |
| The C terminus of a chain | OXT and O of its last amino acid | -0.5 each, or -1 on O without OXT |
| Ions of two charges | ZN, MG, CA, MN, FE, CU, NI, CO and CD residues | +2 |
| Ions of one charge | NA and K residues | +1 |
| Chloride | CL residues | -1 |

Histidine is neutral, as it mostly is at pH 7. A residue without an atom
of the table gives nothing for that atom.

`coulomb_potential` gives the potential of the charges at a point, with
the distance-dependent dielectric `4 r`, `r` in angstroms, as UCSF
Chimera's Coulombic coloring does:

    phi = 332.0636 * sum(q / (4 r^2))  kcal/(mol e)

It is the molar energy of one elementary charge at the point. A charge
closer than 0.5 angstroms counts at 0.5 angstroms. This is a quick
picture of where a protein is positive or negative. It is not a solution
of the Poisson-Boltzmann equation.
"""

from extensions.chemistry.quantities import ANGSTROM, MolarEnergy64
from extensions.molecule.dssp import KILOCALORIE_PER_MOLE
from extensions.molecule.ids import ModelId, ResidueId
from extensions.molecule.sequence import one_letter
from extensions.molecule.structure import Structure
from extensions.sdf.vector import V3, distance
from std.math import max
from units.si import Length64, METER

# Coulomb's constant in kcal angstrom / (mol e^2).
comptime COULOMB = 332.0636
# The least distance of a charge, in angstroms.
comptime NEAREST = 0.5


struct Charges(Copyable, Movable):
    """Point charges, in elementary charges at positions in meters."""

    var points: List[V3]
    """The position of each charge, in meters."""
    var charges: List[Float64]
    """Each charge, in elementary charges."""
    var atoms: List[Int]
    """The atom of each charge, in `structure.atoms`."""

    def __init__(out self):
        """Create an empty set."""
        self.points = List[V3]()
        self.charges = List[Float64]()
        self.atoms = List[Int]()

    def total(self) -> Float64:
        """Return the net charge.

        Returns:
            The sum of the charges, in elementary charges.
        """
        var sum = 0.0
        for q in self.charges:
            sum += q
        return sum


def _add(
    mut out: Charges,
    structure: Structure,
    residue: Int,
    name: String,
    charge: Float64,
) raises:
    """Add a charge on a named atom of a residue, when it has one."""
    var atom = structure.find_atom(ResidueId(residue), name).value
    if atom >= 0:
        out.points.append(structure.atoms[atom].position)
        out.charges.append(charge)
        out.atoms.append(atom)


def formal_charges(structure: Structure, model: ModelId) raises -> Charges:
    """Return the formal charges of the groups of a model at pH 7.

    Args:
        structure: The structure.
        model: The model.

    Returns:
        The charges, chain by chain and residue by residue.

    Raises:
        Error: If the model id names no model.
    """
    structure.require_model(model)
    ref m = structure.models[model.value]
    var twice: List[String] = [
        "ZN",
        "MG",
        "CA",
        "MN",
        "FE",
        "CU",
        "NI",
        "CO",
        "CD",
    ]
    var out = Charges()
    # A model holds a chain, and a chain a residue.
    for c in range(  # pragma: no branch
        m.first_chain, m.first_chain + m.chain_count
    ):
        ref chain = structure.chains[c]
        var start = chain.first_residue
        var end = start + chain.residue_count
        var first = -1
        var last = -1
        for r in range(start, end):  # pragma: no branch
            if one_letter(structure.residues[r].name) != "":
                if first < 0:
                    first = r
                last = r
        for r in range(start, end):  # pragma: no branch
            var name = structure.residues[r].name
            if r == first:
                _add(out, structure, r, "N", 1.0)
            if name == "ARG":
                _add(out, structure, r, "NH1", 0.5)
                _add(out, structure, r, "NH2", 0.5)
            elif name == "LYS":
                _add(out, structure, r, "NZ", 1.0)
            elif name == "ASP":
                _add(out, structure, r, "OD1", -0.5)
                _add(out, structure, r, "OD2", -0.5)
            elif name == "GLU":
                _add(out, structure, r, "OE1", -0.5)
                _add(out, structure, r, "OE2", -0.5)
            elif name == "NA" or name == "K":
                _add(out, structure, r, name, 1.0)
            elif name == "CL":
                _add(out, structure, r, "CL", -1.0)
            elif name in twice:
                _add(out, structure, r, name, 2.0)
            if r == last:
                if structure.find_atom(ResidueId(r), "OXT").value >= 0:
                    _add(out, structure, r, "OXT", -0.5)
                    _add(out, structure, r, "O", -0.5)
                else:
                    _add(out, structure, r, "O", -1.0)
    return out^


def coulomb_potential(charges: Charges, point: V3) -> MolarEnergy64:
    """Return the Coulomb potential of charges at a point.

    Args:
        charges: The charges, from `formal_charges`.
        point: The point, in meters.

    Returns:
        The molar energy of one elementary charge at the point, with the
        dielectric `4 r`.
    """
    var a = Length64(1.0, ANGSTROM).to(METER)
    var sum = 0.0
    for k in range(len(charges.charges)):
        var r = max(distance(charges.points[k], point) / a, NEAREST)
        sum += charges.charges[k] / (4.0 * r * r)
    return MolarEnergy64(COULOMB * sum, KILOCALORIE_PER_MOLE)
