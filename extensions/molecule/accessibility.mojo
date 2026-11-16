# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The solvent accessibility of each residue, absolute and relative.

`accessible_areas` gives the accessible area of each atom.
`residue_accessibility` adds the areas of each residue, and divides the
sum by the largest area that the residue can have. The result is the
relative solvent accessibility (RSA), from about 0 for a buried residue
to about 1 for a residue in the open. A residue with an RSA below a
cutoff, such as 0.2 or 0.25, is often called buried.

The largest areas are the theoretical values of Tien and others (2013),
for a residue in an extended chain of three, in square angstroms. They
are for the twenty standard amino acids:

| Residue | Area | Residue | Area | Residue | Area | Residue | Area |
|---|---|---|---|---|---|---|---|
| ALA | 129 | GLN | 225 | LEU | 201 | SER | 155 |
| ARG | 274 | GLU | 223 | LYS | 236 | THR | 172 |
| ASN | 195 | GLY | 104 | MET | 224 | TRP | 285 |
| ASP | 193 | HIS | 224 | PHE | 240 | TYR | 263 |
| CYS | 167 | ILE | 197 | PRO | 159 | VAL | 174 |

Another residue, such as a water or a ligand, gets its area but no RSA.
"""

from extensions.molecule.ids import ModelId, ResidueId
from extensions.molecule.structure import SQUARE_ANGSTROM, Structure
from std.math import isfinite
from units.si import Area64, SQUARE_METER


def max_accessible_area(name: String) raises -> Area64:
    """Return the largest accessible area of a standard amino acid.

    Args:
        name: The three-letter residue name, such as `ALA`.

    Returns:
        The theoretical value of Tien and others (2013).

    Raises:
        Error: If the name is not one of the twenty standard amino acids.
    """
    var names: List[String] = [
        "ALA",
        "ARG",
        "ASN",
        "ASP",
        "CYS",
        "GLN",
        "GLU",
        "GLY",
        "HIS",
        "ILE",
        "LEU",
        "LYS",
        "MET",
        "PHE",
        "PRO",
        "SER",
        "THR",
        "TRP",
        "TYR",
        "VAL",
    ]
    var areas: List[Float64] = [
        129,
        274,
        195,
        193,
        167,
        225,
        223,
        104,
        224,
        197,
        201,
        236,
        224,
        240,
        159,
        155,
        172,
        285,
        263,
        174,
    ]
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return Area64(areas[k], SQUARE_ANGSTROM)
    raise Error("'" + name + "' is not a standard amino acid")


def _is_standard(name: String) -> Bool:
    """Return whether a residue has a largest area."""
    try:
        _ = max_accessible_area(name)
        return True
    except:
        return False


@fieldwise_init
struct ResidueAccess(Copyable, Movable):
    """The accessible area of one residue."""

    var residue: ResidueId
    """The residue."""
    var area: Area64
    """The sum of the accessible areas of its atoms."""
    var relative: Float64
    """The area over the largest area of the residue, or zero when the
    residue has no largest area."""
    var has_relative: Bool
    """Whether the residue is a standard amino acid with an RSA."""

    def buried(self, cutoff: Float64) raises -> Bool:
        """Return whether the RSA is below a cutoff.

        Args:
            cutoff: The cutoff, such as 0.25. Positive and finite.

        Returns:
            Whether the residue is buried.

        Raises:
            Error: If the cutoff is not positive and finite, or the
                residue has no RSA.
        """
        if not (cutoff > 0) or not isfinite(cutoff):
            raise Error("A burial cutoff must be positive and finite")
        if not self.has_relative:
            raise Error("The residue is not a standard amino acid")
        return self.relative < cutoff


def residue_accessibility(
    structure: Structure, model: ModelId, areas: List[Area64]
) raises -> List[ResidueAccess]:
    """Return the accessible area and the RSA of each residue of a model.

    Args:
        structure: The structure.
        model: The model.
        areas: The area of each atom of the model, such as
            `accessible_areas` gives.

    Returns:
        One entry for each residue of the model, in order.

    Raises:
        Error: If the model id names no model, or the areas do not fit
            the atoms of the model.
    """
    var span = structure.model_atoms(model)
    if len(areas) != span[1]:
        raise Error("The areas must have one value for each atom of the model")
    ref m = structure.models[model.value]
    var out = List[ResidueAccess]()
    for c in range(
        m.first_chain, m.first_chain + m.chain_count
    ):  # pragma: no branch
        ref chain = structure.chains[c]
        for r in range(  # pragma: no branch
            chain.first_residue, chain.first_residue + chain.residue_count
        ):
            ref residue = structure.residues[r]
            var total = 0.0
            for a in range(
                residue.first_atom, residue.first_atom + residue.atom_count
            ):
                total += areas[a - span[0]].to(SQUARE_METER)
            var relative = 0.0
            var standard = _is_standard(residue.name)
            if standard:
                relative = total / max_accessible_area(residue.name).to(
                    SQUARE_METER
                )
            out.append(
                ResidueAccess(
                    ResidueId(r),
                    Area64(total, SQUARE_METER),
                    relative,
                    standard,
                )
            )
    return out^
