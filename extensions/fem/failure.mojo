# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The failure load of bone by the criterion of Pistoia and others (2002).

A linear model of a bone, such as a radius from high-resolution CT, gives
the strain of each element under a load. Pistoia and others found that a
radius fails near the load at which 2 percent of its bone tissue passes
an effective strain of 7000 microstrain. The model is linear, so that load
is the solved load times a factor:

    factor = critical strain / the strain that the critical volume passes

- `effective_strains(problem, result)` gives `sqrt(2 U / E)` of each
  element, with `U` its strain energy density. Under a uniaxial stress, it
  is the strain along the stress.
- `pistoia_failure(problem, result, material, critical, fraction)` gives
  the factor for the elements of one material, such as bone without the
  platens that press it.

The factor scales the whole solution: the forces, the reactions and the
prescribed displacements. So a model pressed by a prescribed displacement
fails near the factor times its reaction force.
"""

from extensions.fem.ids import MaterialId, require_id
from extensions.fem.mesh import signed_volume
from extensions.fem.static import StaticProblem, StaticResult
from std.math import isfinite, sqrt
from units.si import CUBIC_METER, PASCAL, Volume64
from extensions.numerics.order import descending_order


def effective_strains(
    problem: StaticProblem, result: StaticResult
) raises -> List[Float64]:
    """Return the effective strain of each element.

    Args:
        problem: The problem that was solved.
        result: Its static result.

    Returns:
        `sqrt(sigma . epsilon / E)` of each element, with engineering
        shears: the root of twice the strain energy density over Young's
        modulus.

    Raises:
        Error: If the result is not for this problem.
    """
    var count = problem.mesh.element_count()
    if len(result.strains) != 6 * count or len(result.stresses) != 6 * count:
        raise Error("The result is not for this problem")
    var out = List[Float64]()
    for e in range(count):  # pragma: no branch
        var young = problem.materials[problem.mesh.materials[e]].young.to(
            PASCAL
        )
        var work = 0.0
        for k in range(6):  # pragma: no branch
            work += result.stresses[6 * e + k] * result.strains[6 * e + k]
        out.append(sqrt(max(work, 0.0) / young))
    return out^


struct PistoiaFailure(Copyable, Movable):
    """The failure factor of a material by the criterion of Pistoia."""

    var factor: Float64
    """The factor on the solved load at failure."""
    var threshold: Float64
    """The effective strain that the critical volume passes under the
    solved load."""
    var volume: Volume64
    """The volume of the elements of the material."""
    var elements: Int
    """The elements of the material."""

    def __init__(
        out self,
        factor: Float64,
        threshold: Float64,
        volume: Volume64,
        elements: Int,
    ):
        """Create a result.

        Args:
            factor: The failure factor.
            threshold: The effective strain at the critical volume.
            volume: The volume of the material.
            elements: The elements of the material.
        """
        self.factor = factor
        self.threshold = threshold
        self.volume = volume
        self.elements = elements


def pistoia_failure(
    problem: StaticProblem,
    result: StaticResult,
    material: MaterialId,
    critical: Float64,
    fraction: Float64,
) raises -> PistoiaFailure:
    """Return the factor on the solved load at which a material fails.

    The elements of the material are taken from the largest effective
    strain down, until their volume reaches the fraction of the material's
    volume. The strain of the last of them is the threshold. Pistoia and
    others take a critical strain of 0.007 and a fraction of 0.02 for the
    distal radius.

    Args:
        problem: The problem that was solved.
        result: Its static result.
        material: The material of the bone.
        critical: The critical effective strain, positive and finite.
        fraction: The critical share of the volume, between 0 and 1.

    Returns:
        The factor, the threshold, and the volume and the elements of the
        material.

    Raises:
        Error: If the result is not for this problem, the material names
            none of the problem or has no element, the strain or the share
            is out of range, or the material has no strain there.
    """
    var strains = effective_strains(problem, result)
    require_id(
        material.is_valid(), material.value, len(problem.materials), "material"
    )
    if not (critical > 0) or not isfinite(critical):
        raise Error("A critical strain must be positive and finite")
    if not (fraction > 0 and fraction < 1):
        raise Error("A critical share of the volume is between 0 and 1")
    ref mesh = problem.mesh
    var nodes = mesh.nodes_per_element()
    var picked = List[Int]()
    var volumes = List[Float64]()
    var total = 0.0
    for e in range(mesh.element_count()):  # pragma: no branch
        if mesh.materials[e] != material.value:
            continue
        var at = nodes * e
        var v = abs(
            signed_volume(
                mesh.nodes[mesh.corners[at]],
                mesh.nodes[mesh.corners[at + 1]],
                mesh.nodes[mesh.corners[at + 2]],
                mesh.nodes[mesh.corners[at + 3]],
            )
        )
        picked.append(e)
        volumes.append(v)
        total += v
    if len(picked) == 0:
        raise Error("The material has no element")
    var picked_strains = List[Float64]()
    for e in picked:  # pragma: no branch
        picked_strains.append(strains[e])
    var order = descending_order(picked_strains)
    var goal = fraction * total
    var reached = 0.0
    var threshold = 0.0
    for i in order:  # pragma: no branch
        reached += volumes[i]
        threshold = strains[picked[i]]
        if reached >= goal:
            break
    if not (threshold > 0):
        raise Error("The material has no strain at the critical volume")
    return PistoiaFailure(
        critical / threshold,
        threshold,
        Volume64(total, CUBIC_METER),
        len(picked),
    )
