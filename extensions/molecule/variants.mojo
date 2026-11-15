# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Protein variants of a disease, placed on a structure.

A missense variant changes one amino acid, such as `R175H` of the tumor
suppressor p53: arginine 175 becomes histidine. Disease research asks
where such a site is in the folded protein. `parse_variant` reads a
variant as `R175H`, `p.R175H` or `p.Arg175His`. `variant_sites` finds each
site in a chain, by its author number, and checks that the residue there
is the variant's wild type. It then gives each site:

| Field | Meaning |
|---|---|
| `relative_accessibility` | The RSA, by `residue_accessibility`, with a probe of 1.4 angstroms and 480 points on each sphere |
| `secondary` | The secondary structure of the residue |
| `b_factor` | The mean B-factor of its atoms, the pLDDT of a predicted model |
| `contacts` | The other residues of the model with an atom within `reach` of one of its atoms |
| `charge_change` | The formal charge at pH 7 of the new amino acid less that of the old: +1 for R and K, -1 for D and E |
| `hydropathy_change` | The Kyte-Doolittle hydropathy of the new amino acid less that of the old |
| `blosum` | The BLOSUM62 score of the change: below 0 for a change that is rare in related proteins |

A buried site, in a helix or a strand, whose change is rare or alters the
charge, often unfolds a protein. These are measures for research. They
are not a prediction of disease.
"""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.accessibility import residue_accessibility
from extensions.molecule.coloring import kyte_doolittle
from extensions.molecule.ids import ChainId, ModelId, ResidueId, SecondaryKind
from extensions.molecule.peptide import three_letter
from extensions.molecule.sequence import blosum62, one_letter
from extensions.molecule.structure import Structure
from extensions.molecule.surface import accessible_areas
from extensions.sdf.vector import distance
from std.math import isfinite
from units.si import Area64, Length64, METER, SQUARE_METER

comptime SPHERE_POINTS = 480


struct Variant(Copyable, Movable):
    """A change of one amino acid at a residue number."""

    var wild: String
    """The one-letter code of the amino acid of the reference."""
    var position: Int
    """The residue number, 1 or more."""
    var mutant: String
    """The one-letter code of the new amino acid."""

    def __init__(out self, wild: String, position: Int, mutant: String) raises:
        """Create a variant.

        Args:
            wild: The one-letter code of the old amino acid.
            position: The residue number, 1 or more.
            mutant: The one-letter code of the new amino acid.

        Raises:
            Error: If a code is not one of the twenty amino acids, the two
                are the same, or the position is below 1.
        """
        _ = three_letter(wild)
        _ = three_letter(mutant)
        if wild == mutant:
            raise Error("A variant changes its amino acid")
        if position < 1:
            raise Error("A variant's residue number is 1 or more")
        self.wild = wild
        self.position = position
        self.mutant = mutant

    def name(self) -> String:
        """Return the short name of the variant.

        Returns:
            The name, such as `R175H`.
        """
        return self.wild + String(self.position) + self.mutant


def _code(text: String) raises -> String:
    """Return the one-letter code of a one-letter or three-letter
    amino acid, as `R` or `Arg`."""
    if text.byte_length() == 1:
        return text
    # Only a residue name of three letters has a code.
    var code = one_letter(text.upper())
    if code == "":
        raise Error("A variant names an amino acid that is not one of twenty")
    return code


def parse_variant(text: String) raises -> Variant:
    """Read a missense variant.

    Args:
        text: The variant, as `R175H`, `p.R175H` or `p.Arg175His`.

    Returns:
        The variant.

    Raises:
        Error: If the text is not an amino acid, a number and an amino
            acid, or `Variant` refuses them.
    """
    var body = text
    if text.startswith("p."):
        body = String(text[byte=2:])
    var bytes = body.as_bytes()
    # The number starts at the first digit and ends at the last.
    var first = -1
    var last = -1
    for at in range(len(bytes)):
        if bytes[at] >= 48 and bytes[at] <= 57:
            if first < 0:
                first = at
            last = at
    if first < 1 or last >= len(bytes) - 1:
        raise Error("A variant is an amino acid, a number and an amino acid")
    var digits = String(body[byte = first : last + 1])
    for d in digits.as_bytes():  # pragma: no branch
        if d < 48 or d > 57:
            raise Error("A variant's residue number holds digits only")
    return Variant(
        _code(String(body[byte=0:first])),
        Int(atol(digits)),
        _code(String(body[byte = last + 1 :])),
    )


def _charge(code: String) -> Int:
    """Return the formal charge of an amino acid at pH 7."""
    if code == "R" or code == "K":
        return 1
    if code == "D" or code == "E":
        return -1
    return 0


struct VariantSite(Copyable, Movable):
    """A variant at its residue of a structure."""

    var variant: Variant
    """The variant."""
    var residue: ResidueId
    """The residue of the variant."""
    var relative_accessibility: Float64
    """The RSA of the residue."""
    var secondary: SecondaryKind
    """The secondary structure of the residue."""
    var b_factor: Area64
    """The mean B-factor of the residue's atoms."""
    var contacts: List[ResidueId]
    """The other residues with an atom within the reach."""
    var charge_change: Int
    """The new formal charge less the old, at pH 7."""
    var hydropathy_change: Float64
    """The new Kyte-Doolittle hydropathy less the old."""
    var blosum: Int
    """The BLOSUM62 score of the change."""

    def __init__(
        out self,
        var variant: Variant,
        residue: ResidueId,
        relative_accessibility: Float64,
        secondary: SecondaryKind,
        b_factor: Area64,
        var contacts: List[ResidueId],
    ) raises:
        """Create a site, with the changes of its variant.

        Args:
            variant: The variant.
            residue: Its residue.
            relative_accessibility: The RSA of the residue.
            secondary: The secondary structure of the residue.
            b_factor: The mean B-factor of the residue's atoms.
            contacts: The residues in contact.

        Raises:
            Error: If a code of the variant is not an amino acid.
        """
        var old = kyte_doolittle(three_letter(variant.wild))[1]
        var new = kyte_doolittle(three_letter(variant.mutant))[1]
        self.charge_change = _charge(variant.mutant) - _charge(variant.wild)
        self.hydropathy_change = new - old
        self.blosum = blosum62(variant.wild, variant.mutant)
        self.variant = variant^
        self.residue = residue
        self.relative_accessibility = relative_accessibility
        self.secondary = secondary
        self.b_factor = b_factor
        self.contacts = contacts^


def variant_sites(
    structure: Structure,
    model: ModelId,
    chain: ChainId,
    variants: List[Variant],
    reach: Length64,
) raises -> List[VariantSite]:
    """Place variants on a chain, and describe each site.

    Args:
        structure: The structure, such as a predicted model.
        model: The model.
        chain: The chain, which must be in the model.
        variants: The variants, by the author numbers of the chain.
        reach: The distance of a contact, such as 4.5 angstroms. Positive
            and finite.

    Returns:
        One site for each variant, in order.

    Raises:
        Error: If the model or the chain is not valid, the chain is not in
            the model, the reach is not positive and finite, a variant's
            number is not in the chain, or the residue there is not the
            variant's wild type.
    """
    structure.require_model(model)
    structure.require_chain(chain)
    ref c = structure.chains[chain.value]
    if c.model != model:
        raise Error("The chain is not in the model")
    var near = reach.to(METER)
    if not (near > 0) or not isfinite(near):
        raise Error("A contact reach must be positive and finite")
    var span = structure.model_atoms(model)
    var areas = accessible_areas(
        structure, model, Length64(1.4, ANGSTROM), SPHERE_POINTS
    )
    var access = residue_accessibility(structure, model, areas)
    var base = structure.chains[
        structure.models[model.value].first_chain
    ].first_residue
    var out = List[VariantSite]()
    for v in variants:
        var found = -1
        # A chain holds one residue or more.
        for r in range(  # pragma: no branch
            c.first_residue, c.first_residue + c.residue_count
        ):
            if structure.residues[r].auth_seq_id == v.position:
                found = r
                break
        if found < 0:
            raise Error(v.name() + ": the chain has no residue of that number")
        ref residue = structure.residues[found]
        var code = one_letter(residue.name)
        if code != v.wild:
            raise Error(v.name() + ": the residue there is " + residue.name)
        var b = 0.0
        var first = residue.first_atom
        var count = residue.atom_count
        # A residue of a structure holds one atom or more.
        for a in range(first, first + count):  # pragma: no branch
            b += structure.atoms[a].b_factor.to(SQUARE_METER)
        var contacts = List[ResidueId]()
        for a in range(span[0], span[0] + span[1]):  # pragma: no branch
            var other = structure.atoms[a].residue.value
            if other == found:
                continue
            if len(contacts) > 0 and contacts[len(contacts) - 1].value == other:
                continue
            for own in range(first, first + count):  # pragma: no branch
                if (
                    distance(
                        structure.atoms[a].position,
                        structure.atoms[own].position,
                    )
                    <= near
                ):
                    contacts.append(ResidueId(other))
                    break
        out.append(
            VariantSite(
                v.copy(),
                ResidueId(found),
                access[found - base].relative,
                residue.secondary,
                Area64(b / Float64(count), SQUARE_METER),
                contacts^,
            )
        )
    return out^
