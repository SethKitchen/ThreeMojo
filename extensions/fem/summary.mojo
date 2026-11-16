# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The stress of each material of a solved model, in a few numbers.

A model of several materials, such as bone with cortical and trabecular
labels, is reported material by material. `stress_summary` gives, for
each material of a mesh:

- the number of elements and their volume,
- the peak von Mises stress of an element,
- the mean von Mises stress, with each element weighted by its volume,
- the volume of the elements at or above a stress, such as a yield
  stress.

The peak of a single element depends on the mesh, most near a corner or
a stair step of a voxel mesh. The mean and the volume above a stress
change less with the mesh.

`strain_energy` gives the work stored in the deformed model,
`U = u K u / 2`, from the assembled stiffness, so it is exact for both
element orders. A model pressed by a prescribed displacement `d` has the
apparent stiffness `2 U / d^2`, a common measure of a whole bone.
"""

from extensions.fem.ids import MaterialId
from extensions.fem.mesh import TetMesh, signed_volume
from extensions.fem.static import StaticProblem, StaticResult, assemble
from std.math import isfinite, max
from units.si import CUBIC_METER, Energy64, JOULE, PASCAL, Pressure64, Volume64


@fieldwise_init
struct MaterialStress(Copyable, Movable):
    """The stress summary of one material."""

    var material: MaterialId
    """The material."""
    var elements: Int
    """The number of its elements."""
    var volume: Volume64
    """The volume of its elements."""
    var peak: Pressure64
    """The largest von Mises stress of one of its elements."""
    var mean: Pressure64
    """The mean von Mises stress, weighted by element volume."""
    var over: Volume64
    """The volume of its elements at or above the threshold."""


def stress_summary(
    mesh: TetMesh, result: StaticResult, threshold: Pressure64
) raises -> List[MaterialStress]:
    """Return the stress summary of each material of a mesh.

    Args:
        mesh: The mesh that was solved.
        result: Its static result.
        threshold: The stress for the volume above it. Zero or more,
            and finite.

    Returns:
        One summary for each material that has elements, in the order of
        the material indexes.

    Raises:
        Error: If the result is not for this mesh, or the threshold is
            negative or not finite.
    """
    var count = mesh.element_count()
    if len(result.von_mises) != count:
        raise Error("The result is not for this mesh")
    var limit = threshold.to(PASCAL)
    if not (limit >= 0) or not isfinite(limit):
        raise Error("A stress threshold must be zero or more, and finite")
    var materials = 0
    for m in mesh.materials:
        materials = max(materials, m + 1)
    var elements = List[Int](length=materials, fill=0)
    var volume = List[Float64](length=materials, fill=0)
    var peak = List[Float64](length=materials, fill=0)
    var weighted = List[Float64](length=materials, fill=0)
    var over = List[Float64](length=materials, fill=0)
    var nodes = mesh.nodes_per_element()
    for e in range(count):
        var at = nodes * e
        var v = abs(
            signed_volume(
                mesh.nodes[mesh.corners[at]],
                mesh.nodes[mesh.corners[at + 1]],
                mesh.nodes[mesh.corners[at + 2]],
                mesh.nodes[mesh.corners[at + 3]],
            )
        )
        var m = mesh.materials[e]
        var stress = result.von_mises[e].to(PASCAL)
        elements[m] += 1
        volume[m] += v
        peak[m] = max(peak[m], stress)
        weighted[m] += stress * v
        if stress >= limit:
            over[m] += v
    var out = List[MaterialStress]()
    for m in range(materials):
        if elements[m] == 0:
            continue
        out.append(
            MaterialStress(
                MaterialId(m),
                elements[m],
                Volume64(volume[m], CUBIC_METER),
                Pressure64(peak[m], PASCAL),
                Pressure64(weighted[m] / volume[m], PASCAL),
                Volume64(over[m], CUBIC_METER),
            )
        )
    return out^


def strain_energy(
    problem: StaticProblem, result: StaticResult
) raises -> Energy64:
    """Return the strain energy `u K u / 2` of a solved model.

    Args:
        problem: The problem that was solved.
        result: Its static result.

    Returns:
        The energy stored in the deformation.

    Raises:
        Error: If the result is not for this problem.
    """
    var size = 3 * problem.mesh.node_count()
    if len(result.displacements) != size:
        raise Error("The result is not for this problem")
    var stiffness = assemble(problem)
    var force = stiffness.multiply(result.displacements)
    var work = 0.0
    for k in range(size):  # pragma: no branch
        work += result.displacements[k] * force[k]
    return Energy64(0.5 * work, JOULE)
