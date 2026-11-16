# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The RMSD between every two models of an ensemble, and their clusters.

An NMR ensemble or a series of simulation snapshots holds many models.
`model_distances` gives the RMSD of every pair of models, over one atom
of each residue, such as CA. With `FIT_TO_REFERENCE`, the second model
of each pair is first superposed on the first, with Horn's method, so
only the change of shape counts. With `AS_GIVEN`, the coordinates are
compared as they are. Atoms pair as `shared_positions` pairs them, and
an atom counts only when every model has it.

`ModelDistances.medoid` is the model with the least sum of RMSDs to the
others: the most central model, which studies report as the
representative of an ensemble. Of two sums equal to rounding, the lower
model counts.

`cluster_models` groups the models by the method of Daura and others
(1999), the `gromos` method of GROMACS. Two models are neighbors when
their RMSD is at most a cutoff, and each model is its own neighbor. The
model with the most neighbors is the center of the first cluster, and
the cluster holds it and its neighbors. Those models leave the pool, and
the next cluster forms from the rest. Of two models with as many
neighbors, the lower one counts.
"""

from extensions.molecule.ensemble import shared_positions
from extensions.molecule.ids import (
    EnsembleFit,
    FIT_TO_REFERENCE,
    ModelId,
    require_ensemble_fit,
)
from extensions.molecule.structure import Structure
from extensions.molecule.superpose import rmsd, superpose
from std.math import isfinite
from units.si import Length64, METER

# RMSDs equal to the cutoff count as within it, and sums equal to each
# other count as equal, to this relative rounding.
comptime ROUNDING = 1.0e-9


struct ModelDistances(Copyable, Movable):
    """The RMSD between every two models of an ensemble."""

    var models: Int
    """The number of models."""
    var atoms: Int
    """The number of compared atoms in each model."""
    var values: List[Float64]
    """The RMSDs, `models` by `models`, row by row, in meters."""

    def __init__(out self, models: Int, atoms: Int):
        """Create a table of zeros.

        Args:
            models: The number of models.
            atoms: The number of compared atoms.
        """
        self.models = models
        self.atoms = atoms
        self.values = List[Float64](length=models * models, fill=0)

    def distance(self, first: ModelId, second: ModelId) raises -> Length64:
        """Return the RMSD between two models.

        Args:
            first: One model.
            second: The other model.

        Returns:
            The RMSD. It is 0 for a model and itself.

        Raises:
            Error: If a model id names no model of the table.
        """
        for model in [first, second]:  # pragma: no branch
            if model.value < 0 or model.value >= self.models:
                raise Error("A model id is outside the table")
        return Length64(
            self.values[first.value * self.models + second.value], METER
        )

    def medoid(self) -> ModelId:
        """Return the model with the least sum of RMSDs to the others.

        Returns:
            The model. Of two whose sums are equal to rounding, the
            lower.
        """
        var best = 0
        var least = 0.0
        for a in range(self.models):  # pragma: no branch
            var total = 0.0
            for b in range(self.models):  # pragma: no branch
                total += self.values[a * self.models + b]
            if a == 0 or total < least * (1.0 - ROUNDING):
                best = a
                least = total
        return ModelId(best)


def model_distances(
    structure: Structure, name: String, fit: EnsembleFit
) raises -> ModelDistances:
    """Return the RMSD between every two models, over one atom per residue.

    Args:
        structure: A structure of two or more models.
        name: The atom name to compare, such as `CA`.
        fit: `FIT_TO_REFERENCE` to superpose each pair first, or
            `AS_GIVEN`.

    Returns:
        The table. The compared atoms are those of the first model that
        every model shares.

    Raises:
        Error: If the fit is not valid, the structure has fewer than two
            models, or fewer than three atoms are shared when the models
            are fitted, or none otherwise.
    """
    require_ensemble_fit(fit)
    var models = len(structure.models)
    if models < 2:
        raise Error("An ensemble needs two or more models")
    var shared = shared_positions(structure, name, ModelId(0))
    var positions = shared[1].copy()
    var n = len(shared[0])
    var fitted = fit == FIT_TO_REFERENCE
    if n == 0 or (fitted and n < 3):
        raise Error(
            "An ensemble needs three shared atoms to fit, and one to compare"
        )
    var out = ModelDistances(models, n)
    for a in range(models):  # pragma: no branch
        for b in range(a + 1, models):
            var moving = positions[b].copy()
            if fitted:
                var move = superpose(positions[a], moving)
                for i in range(n):  # pragma: no branch
                    moving[i] = move.apply(moving[i])
            var d = rmsd(positions[a], moving).to(METER)
            out.values[a * models + b] = d
            out.values[b * models + a] = d
    return out^


def cluster_models(
    distances: ModelDistances, cutoff: Length64
) raises -> List[List[ModelId]]:
    """Return the clusters of the models, by the method of Daura and others.

    Args:
        distances: The table of `model_distances`.
        cutoff: The largest RMSD of two neighbors. At least 0 and finite.

    Returns:
        The clusters, largest first. The first model of each cluster is
        its center, and the others follow in their order.

    Raises:
        Error: If the cutoff is negative or not finite.
    """
    var reach = cutoff.to(METER)
    if not isfinite(reach) or reach < 0:
        raise Error("A cluster cutoff must be at least 0 and finite")
    reach *= 1.0 + ROUNDING
    var m = distances.models
    var left = List[Bool](length=m, fill=True)
    var remaining = m
    var out = List[List[ModelId]]()
    while remaining > 0:
        var center = -1
        var most = 0
        for a in range(m):  # pragma: no branch
            if not left[a]:
                continue
            var count = 0
            for b in range(m):  # pragma: no branch
                if left[b] and distances.values[a * m + b] <= reach:
                    count += 1
            if count > most:
                center = a
                most = count
        var cluster = List[ModelId]()
        cluster.append(ModelId(center))
        left[center] = False
        for b in range(m):  # pragma: no branch
            if left[b] and distances.values[center * m + b] <= reach:
                cluster.append(ModelId(b))
                left[b] = False
        remaining -= len(cluster)
        out.append(cluster^)
    return out^
