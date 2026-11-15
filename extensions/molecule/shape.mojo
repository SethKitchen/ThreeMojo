# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The size and the shape of a model: its mass center, radius of gyration
and principal axes.

Each atom weighs its element's standard atomic weight. The mass center
is the weighted mean of the atom positions. The gyration tensor is the
weighted mean of `(r - c)(r - c)^T`. Its eigenvectors are the principal
axes, and the square roots of its eigenvalues are the principal extents:
the root mean square distance of the mass from the center along each
axis. The radius of gyration is the root of the sum of the three.

A globular protein has three similar extents. A helix or a fiber has one
large extent and two small ones.
"""

from extensions.chemistry.elements import element_from_symbol
from extensions.chemistry.quantities import GRAM_PER_MOLE, MolarMass64
from extensions.molecule.ids import ModelId
from extensions.molecule.structure import Structure
from extensions.numerics.spread import PointSpread
from extensions.sdf.vector import V3, v3
from std.math import max, sqrt
from units.si import Length64, METER


struct MolecularShape(Copyable, Movable):
    """The mass, mass center, radius of gyration and principal axes."""

    var mass: MolarMass64
    """The sum of the atomic weights of the model's atoms."""
    var center: V3
    """The mass center, in meters."""
    var radius_of_gyration: Length64
    """The root mean square distance of the mass from its center."""
    var axes: List[V3]
    """The three principal axes, unit and square, the longest first."""
    var extents: List[Length64]
    """The root mean square distance of the mass along each axis."""

    def __init__(out self):
        """Create an empty shape."""
        self.mass = MolarMass64(0, GRAM_PER_MOLE)
        self.center = v3(0, 0, 0)
        self.radius_of_gyration = Length64(0, METER)
        self.axes = List[V3]()
        self.extents = List[Length64]()


def molecular_shape(
    structure: Structure, model: ModelId
) raises -> MolecularShape:
    """Return the size and shape of a model.

    Args:
        structure: The structure.
        model: The model.

    Returns:
        Its mass, mass center, radius of gyration and principal axes.

    Raises:
        Error: If the model id names no model, or an atom's element has no
            standard atomic weight.
    """
    var span = structure.model_atoms(model)
    var spread = PointSpread()
    for index in range(span[0], span[0] + span[1]):  # pragma: no branch
        ref atom = structure.atoms[index]
        var weight: Float64
        try:
            weight = (
                element_from_symbol(atom.element)
                .atomic_weight()
                .to(GRAM_PER_MOLE)
            )
        except:
            raise Error(
                "The element '" + atom.element + "' has no standard weight"
            )
        spread.add(atom.position.x, atom.position.y, atom.position.z, weight)
    var pairs = spread.principal()
    var out = MolecularShape()
    out.mass = MolarMass64(spread.weight, GRAM_PER_MOLE)
    out.center = v3(spread.mean[0], spread.mean[1], spread.mean[2])
    var sum = 0.0
    for k in range(3):  # pragma: no branch
        var value = max(pairs.values[k], 0.0)
        sum += value
        out.extents.append(Length64(sqrt(value), METER))
        out.axes.append(
            v3(
                pairs.vectors.get(0, k),
                pairs.vectors.get(1, k),
                pairs.vectors.get(2, k),
            )
        )
    out.radius_of_gyration = Length64(sqrt(sum), METER)
    return out^
