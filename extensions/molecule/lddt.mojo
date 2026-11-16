# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The local distance difference test (lDDT) of a model.

lDDT scores how well a model keeps the local distances of a reference
structure, such as a predicted model against the experimental one. It
needs no superposition. Each pair of points closer than a cutoff of
15 angstroms in the reference is a pair to score. The pair scores a
quarter for each of the thresholds 0.5, 1, 2 and 4 angstroms that the
difference of its two distances is below. The lDDT of a point is the
mean score of its pairs, and the lDDT of the model the mean over all
pairs. This is the CA lDDT of AlphaFold's code. A point with no pair
within the cutoff scores 1, as there.

`lddt(reference, model, cutoff)` scores two lists of paired points.
`ca_lddt` pairs the CA atoms of two models by chain, residue number and
insertion code, as `matched_atoms` does. `lddt_b_factors` writes 100
times each residue's score into its B-factors, so that
`COLOR_BY_CONFIDENCE` and `BY_CONFIDENCE` show the true local accuracy
in the bands of pLDDT.
"""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.ids import AtomId, ModelId
from extensions.molecule.structure import SQUARE_ANGSTROM, Structure
from extensions.molecule.superpose import matched_atoms
from extensions.sdf.vector import V3, distance
from std.math import isfinite
from units.si import Area64, Length64, METER


struct LddtScores(Copyable, Movable):
    """The lDDT of each point and of the whole model."""

    var per_point: List[Float64]
    """The lDDT of each point, from 0 to 1."""
    var pairs: List[Int]
    """The pairs that each point has within the cutoff."""
    var total: Float64
    """The lDDT of the model: the mean score over all pairs."""
    var atoms: List[Tuple[Int, Int]]
    """For `ca_lddt`, the paired atoms of the reference and the model, one
    per point. Empty for `lddt`."""

    def __init__(out self):
        """Create an empty result."""
        self.per_point = List[Float64]()
        self.pairs = List[Int]()
        self.total = 1.0
        self.atoms = List[Tuple[Int, Int]]()


def lddt(
    reference: List[V3], model: List[V3], cutoff: Length64
) raises -> LddtScores:
    """Return the lDDT of paired points.

    Args:
        reference: The points of the reference, in meters.
        model: The paired points of the model, in meters, as many.
        cutoff: The largest distance of a pair in the reference, such as
            15 angstroms. Positive and finite.

    Returns:
        The scores.

    Raises:
        Error: If the lists are empty or differ in size, or the cutoff is
            not positive and finite.
    """
    var n = len(reference)
    if n == 0 or n != len(model):
        raise Error("An lDDT needs two lists of points of one size")
    var reach = cutoff.to(METER)
    if not (reach > 0) or not isfinite(reach):
        raise Error("An lDDT cutoff must be positive and finite")
    var a = Length64(1.0, ANGSTROM).to(METER)
    var limits: List[Float64] = [0.5 * a, a, 2 * a, 4 * a]
    var out = LddtScores()
    var sums = List[Float64](length=n, fill=0)
    var counts = List[Int](length=n, fill=0)
    var all_sum = 0.0
    var all_count = 0
    for i in range(n):  # pragma: no branch
        for j in range(i + 1, n):
            var d = distance(reference[i], reference[j])
            if not (d < reach):
                continue
            var change = abs(distance(model[i], model[j]) - d)
            var score = 0.0
            for limit in limits:  # pragma: no branch
                if change < limit:
                    score += 0.25
            sums[i] += score
            sums[j] += score
            counts[i] += 1
            counts[j] += 1
            all_sum += score
            all_count += 1
    for i in range(n):  # pragma: no branch
        out.pairs.append(counts[i])
        if counts[i] == 0:
            out.per_point.append(1.0)
        else:
            out.per_point.append(sums[i] / Float64(counts[i]))
    if all_count > 0:
        out.total = all_sum / Float64(all_count)
    return out^


def ca_lddt(
    reference: Structure,
    reference_model: ModelId,
    model: Structure,
    model_model: ModelId,
) raises -> LddtScores:
    """Return the CA lDDT of a model against a reference, at 15 angstroms.

    Args:
        reference: The reference structure, such as an experimental one.
        reference_model: Its model.
        model: The structure to score, such as a prediction.
        model_model: Its model.

    Returns:
        The scores, one point per pair of CA atoms, in the order of the
        reference, with the paired atoms in `atoms`.

    Raises:
        Error: If a model id names no model, or no CA atom pairs.
    """
    var pairs = matched_atoms(
        reference, reference_model, model, model_model, "CA"
    )
    if len(pairs) == 0:
        raise Error("The two models share no CA atom")
    var first = List[V3]()
    var second = List[V3]()
    for pair in pairs:  # pragma: no branch
        first.append(reference.atoms[pair[0]].position)
        second.append(model.atoms[pair[1]].position)
    var out = lddt(first, second, Length64(15.0, ANGSTROM))
    out.atoms = pairs^
    return out^


def lddt_b_factors(mut structure: Structure, scores: LddtScores) raises:
    """Write 100 times each point's lDDT into the B-factors of its residue.

    Every atom of the residue of the second atom of each pair gets the
    value, in square angstroms, as a predicted file holds its pLDDT.

    Args:
        structure: The model structure that `ca_lddt` scored.
        scores: The result of `ca_lddt`.

    Raises:
        Error: If the scores have no atom pairs, or an atom is not in the
            structure.
    """
    if len(scores.atoms) == 0:
        raise Error("The scores have no atom pairs; use ca_lddt")
    for p in range(len(scores.atoms)):  # pragma: no branch
        var atom = AtomId(scores.atoms[p][1])
        structure.require_atom(atom)
        var residue = structure.atoms[atom.value].residue.value
        var first = structure.residues[residue].first_atom
        var end = first + structure.residues[residue].atom_count
        for a in range(first, end):  # pragma: no branch
            structure.atoms[a].b_factor = Area64(
                100.0 * scores.per_point[p], SQUARE_ANGSTROM
            )
