# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The confidence of a predicted structure, from its pLDDT.

A structure predicted by AlphaFold or a similar model gives each residue
a predicted local distance difference test (pLDDT) from 0 to 100. The
file holds it in the B-factor column of every atom of the residue. The
AlphaFold Protein Structure Database colors it in four bands:

| Band | pLDDT | Color |
|---|---|---|
| Very high | above 90 | dark blue, `#0053D6` |
| Confident | above 70, to 90 | light blue, `#65CBF3` |
| Low | above 50, to 70 | yellow, `#FFDB13` |
| Very low | 50 and below | orange, `#FF7D45` |

A value on the edge of two bands, such as 90, is in the lower band, to a
rounding of 1e-9. A region of very low pLDDT is often disordered. Do not read its shape as
a structure.

`confidence_color` gives the color of a pLDDT. `COLOR_BY_CONFIDENCE`
colors a surface with it, and `BY_CONFIDENCE` a ribbon.
`confidence_summary` gives the mean pLDDT of a model and the number of
residues in each band, from the B-factor of each CA atom.
"""

from extensions.molecule.ids import ModelId, ResidueId
from extensions.molecule.structure import SQUARE_ANGSTROM, Structure
from extensions.sdf.vector import V3, v3
from std.math import isfinite

# A pLDDT read back from square meters can be off by a rounding: 90 reads
# as 90.00000000000001. A band's edge holds to this much.
comptime EDGE = 1.0e-9


def _band(plddt: Float64) -> Int:
    """Return the band of a pLDDT: 0 for very high, to 3 for very low."""
    if plddt > 90 + EDGE:
        return 0
    if plddt > 70 + EDGE:
        return 1
    if plddt > 50 + EDGE:
        return 2
    return 3


def confidence_color(plddt: Float64) -> V3:
    """Return the sRGB color of a pLDDT, in the bands of the database.

    Args:
        plddt: The pLDDT, from 0 to 100.

    Returns:
        The color of its band, each part from 0 to 1.
    """
    var band = _band(plddt)
    if band == 0:
        return v3(0.0, 83.0 / 255.0, 214.0 / 255.0)
    if band == 1:
        return v3(101.0 / 255.0, 203.0 / 255.0, 243.0 / 255.0)
    if band == 2:
        return v3(1.0, 219.0 / 255.0, 19.0 / 255.0)
    return v3(1.0, 125.0 / 255.0, 69.0 / 255.0)


@fieldwise_init
struct ConfidenceSummary(Copyable, Movable):
    """The pLDDT of the residues of a model."""

    var residues: Int
    """The residues with a CA atom."""
    var mean: Float64
    """The mean pLDDT of those residues."""
    var very_high: Int
    """The residues above 90."""
    var confident: Int
    """The residues above 70, to 90."""
    var low: Int
    """The residues above 50, to 70."""
    var very_low: Int
    """The residues at 50 and below."""


def confidence_summary(
    structure: Structure, model: ModelId
) raises -> ConfidenceSummary:
    """Return the mean pLDDT of a model and its residues in each band.

    The pLDDT of a residue is the B-factor of its CA atom, read in square
    angstroms as the file gives it.

    Args:
        structure: A predicted structure.
        model: The model.

    Returns:
        The summary.

    Raises:
        Error: If the model id names no model, the model has no CA atom,
            or a pLDDT is not from 0 to 100.
    """
    structure.require_model(model)
    ref m = structure.models[model.value]
    var out = ConfidenceSummary(0, 0.0, 0, 0, 0, 0)
    var total = 0.0
    # A model holds a chain, and a chain a residue.
    for c in range(
        m.first_chain, m.first_chain + m.chain_count
    ):  # pragma: no branch
        ref chain = structure.chains[c]
        var start = chain.first_residue
        for r in range(start, start + chain.residue_count):  # pragma: no branch
            var ca = structure.find_atom(ResidueId(r), "CA")
            if ca.value < 0:
                continue
            var plddt = structure.atoms[ca.value].b_factor.to(SQUARE_ANGSTROM)
            if not (plddt >= -EDGE) or not (plddt <= 100 + EDGE):
                raise Error("A pLDDT runs from 0 to 100")
            out.residues += 1
            total += plddt
            var band = _band(plddt)
            if band == 0:
                out.very_high += 1
            elif band == 1:
                out.confident += 1
            elif band == 2:
                out.low += 1
            else:
                out.very_low += 1
    if out.residues == 0:
        raise Error("The model has no CA atom")
    out.mean = total / Float64(out.residues)
    return out^
