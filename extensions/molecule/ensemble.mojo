# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The fluctuation of each atom over the models of an ensemble.

An NMR structure is an ensemble of models, and a simulation gives a
series of snapshots. Where the models agree, the structure is well
defined. Where they spread, a loop or an end moves. The root mean square
fluctuation (RMSF) of an atom measures that spread:

    RMSF = sqrt(mean over the models of |x_k - mean(x)|^2)

`ensemble_fluctuation` compares one atom of each residue, such as CA,
over every model. With `FIT_TO_REFERENCE`, each model is first
superposed on the reference model by those atoms, with Horn's method.
With `AS_GIVEN`, the coordinates are compared as they are. Atoms pair by
chain label, residue number, insertion code and name, as
`matched_atoms` pairs them. An atom counts only when every model has
it.

`fluctuation_b_factors` writes each RMSF into the reference model as an
isotropic B-factor, `B = 8 pi^2 RMSF^2 / 3`, for every atom of the
residue. `color_surface` with `COLOR_BY_B_FACTOR` then shows the mobile
parts of the ensemble.
"""

from extensions.molecule.ids import (
    AtomId,
    EnsembleFit,
    FIT_TO_REFERENCE,
    ModelId,
    require_ensemble_fit,
)
from extensions.molecule.structure import Structure
from extensions.molecule.superpose import matched_atoms, rmsd, superpose
from extensions.sdf.vector import V3, dot, v3
from std.collections import Dict
from std.math import pi, sqrt
from units.si import Area64, Length64, METER, SQUARE_METER


struct Fluctuation(Copyable, Movable):
    """The RMSF of each compared atom, and the deviation of each model."""

    var atoms: List[AtomId]
    """The compared atoms of the reference model, one per row."""
    var rmsf: List[Float64]
    """The RMSF of each row, in meters."""
    var deviations: List[Float64]
    """The RMSD of each model from the reference over the compared
    atoms, after the fit, in meters. The reference's is zero."""

    def __init__(out self):
        """Create an empty result."""
        self.atoms = List[AtomId]()
        self.rmsf = List[Float64]()
        self.deviations = List[Float64]()

    def count(self) -> Int:
        """Return the number of compared atoms.

        Returns:
            The rows.
        """
        return len(self.atoms)

    def fluctuation(self, row: Int) raises -> Length64:
        """Return the RMSF of one row.

        Args:
            row: The row, from zero.

        Returns:
            The RMSF.

        Raises:
            Error: If the row is outside the result.
        """
        if row < 0 or row >= self.count():
            raise Error("A fluctuation row is outside the result")
        return Length64(self.rmsf[row], METER)

    def deviation(self, model: ModelId) raises -> Length64:
        """Return the RMSD of one model from the reference.

        Args:
            model: The model.

        Returns:
            The RMSD over the compared atoms, after the fit.

        Raises:
            Error: If the model id names no model of the result.
        """
        if model.value < 0 or model.value >= len(self.deviations):
            raise Error("A model id is outside the result")
        return Length64(self.deviations[model.value], METER)


def ensemble_fluctuation(
    structure: Structure,
    name: String,
    reference: ModelId,
    fit: EnsembleFit,
) raises -> Fluctuation:
    """Return the RMSF of one atom of each residue over every model.

    Args:
        structure: A structure of two or more models.
        name: The atom name to compare, such as `CA`.
        reference: The model that the others are fitted on.
        fit: `FIT_TO_REFERENCE` or `AS_GIVEN`.

    Returns:
        One row for each atom of the reference model with the name that
        every model shares, in the reference's order.

    Raises:
        Error: If the fit is not valid, the reference names no model, the
            structure has fewer than two models, or fewer than three atoms
            are shared when the models are fitted, or none otherwise.
    """
    require_ensemble_fit(fit)
    structure.require_model(reference)
    var models = len(structure.models)
    if models < 2:
        raise Error("An ensemble needs two or more models")
    # The atoms of each model that pair with each reference atom.
    var maps = List[Dict[Int, Int]]()
    for k in range(models):  # pragma: no branch
        var found = Dict[Int, Int]()
        for pair in matched_atoms(
            structure, reference, structure, ModelId(k), name
        ):
            found[pair[0]] = pair[1]
        maps.append(found^)
    var out = Fluctuation()
    for pair in matched_atoms(structure, reference, structure, reference, name):
        var shared = True
        for k in range(models):  # pragma: no branch
            if pair[0] not in maps[k]:
                shared = False
        if shared:
            out.atoms.append(AtomId(pair[0]))
    var n = out.count()
    var fitted = fit == FIT_TO_REFERENCE
    if n == 0 or (fitted and n < 3):
        raise Error(
            "An ensemble needs three shared atoms to fit, and one to compare"
        )
    var fixed = List[V3]()
    for atom in out.atoms:  # pragma: no branch
        fixed.append(structure.atoms[atom.value].position)
    var placed = List[List[V3]]()
    for k in range(models):  # pragma: no branch
        var moving = List[V3]()
        for atom in out.atoms:  # pragma: no branch
            moving.append(structure.atoms[maps[k][atom.value]].position)
        if fitted and k != reference.value:
            var move = superpose(fixed, moving)
            for i in range(n):  # pragma: no branch
                moving[i] = move.apply(moving[i])
        out.deviations.append(rmsd(fixed, moving).to(METER))
        placed.append(moving^)
    for i in range(n):  # pragma: no branch
        var mean = v3(0, 0, 0)
        for k in range(models):  # pragma: no branch
            mean = mean + placed[k][i]
        mean = mean * (1.0 / Float64(models))
        var total = 0.0
        for k in range(models):  # pragma: no branch
            var d = placed[k][i] - mean
            total += dot(d, d)
        out.rmsf.append(sqrt(total / Float64(models)))
    return out^


def fluctuation_b_factors(
    mut structure: Structure, fluctuation: Fluctuation
) raises:
    """Write each RMSF into its residue as an isotropic B-factor.

    Each atom of a compared residue gets `B = 8 pi^2 RMSF^2 / 3`. The
    other atoms and the other models keep their B-factors.

    Args:
        structure: The structure of the result.
        fluctuation: The result of `ensemble_fluctuation`.

    Raises:
        Error: If an atom of the result is not in the structure.
    """
    for row in range(fluctuation.count()):
        var atom = fluctuation.atoms[row]
        structure.require_atom(atom)
        var residue = structure.atoms[atom.value].residue.value
        var first = structure.residues[residue].first_atom
        var end = first + structure.residues[residue].atom_count
        var rmsf = fluctuation.rmsf[row]
        var b = Area64(8.0 * pi * pi * rmsf * rmsf / 3.0, SQUARE_METER)
        # The residue holds the compared atom.
        for a in range(first, end):  # pragma: no branch
            structure.atoms[a].b_factor = b
