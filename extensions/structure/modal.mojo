# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Natural frequencies and mode shapes of a structural model.

The mass matrix adds the consistent mass of each member, the lumped mass
of each shell and the added point masses. `solve_modes` removes the fixed
degrees of freedom and solves K φ = ω² M φ for the lowest modes by
subspace iteration, with a Sturm check that no mode was missed.
"""

from std.math import pi, sqrt
from extensions.numerics.eigen import lowest_modes
from extensions.numerics.sparse import CsrMatrix, SparseBuilder
from extensions.structure.frame import (
    frame_local_mass,
    frame_transformation,
    member_axes,
)
from extensions.structure.ids import ShellId
from extensions.structure.model import StructuralModel
from extensions.structure.static import (
    assemble_stiffness,
    factor_stiffness,
    free_equations,
    reduce_matrix,
)
from units.si import Frequency64, Length64

# The relative change of each frequency squared at which to stop.
comptime _TOLERANCE = 1e-12
comptime _ITERATIONS = 400


def assemble_mass(model: StructuralModel) raises -> CsrMatrix:
    """Return the global mass of every member, shell and added mass.

    A member has its consistent mass. A shell puts ρ t A / 3 on each
    translation of each corner and that mass times t² / 12 on each
    rotation. An added mass acts on the three translations of its node.

    Args:
        model: The model.

    Returns:
        The mass, six rows per node, in kilograms and kilogram square
        meters.

    Raises:
        Error: If a member or shell cannot form its matrix.
    """
    var builder = SparseBuilder(model.dof_count())
    for m in range(len(model.members)):
        ref member = model.members[m]
        var a = model.nodes[member.start.value]
        var b = model.nodes[member.end.value]
        var t = frame_transformation(member_axes(a, b, member.reference))
        var local = frame_local_mass(
            Length64(a.distance_to(b)), member.section, member.material
        )
        var global_mass = t.triple_product(local)
        var ends = [member.start.value, member.end.value]
        for i in range(12):  # pragma: no branch
            for j in range(12):  # pragma: no branch
                builder.add(
                    6 * ends[i // 6] + i % 6,
                    6 * ends[j // 6] + j % 6,
                    global_mass.get(i, j),
                )
    for s in range(len(model.shells)):
        var element = model.shell_element(ShellId(s))
        var mass = element.lumped_mass()
        var inertia = mass * element.thickness * element.thickness / 12
        ref shell = model.shells[s]
        var corners = [shell.a.value, shell.b.value, shell.c.value]
        for c in range(3):  # pragma: no branch
            for d in range(3):  # pragma: no branch
                builder.add(6 * corners[c] + d, 6 * corners[c] + d, mass)
                builder.add(
                    6 * corners[c] + 3 + d, 6 * corners[c] + 3 + d, inertia
                )
    for n in range(len(model.nodes)):
        for d in range(3):  # pragma: no branch
            builder.add(6 * n + d, 6 * n + d, model.added_mass[n])
    return builder.build()


struct ModalResult(Movable):
    """The lowest natural frequencies and their mode shapes."""

    var frequencies: List[Frequency64]
    # One per frequency: six entries per node, in meters and radians, with
    # φᵀ M φ = 1 in kilograms.
    var shapes: List[List[Float64]]

    def __init__(
        out self,
        var frequencies: List[Frequency64],
        var shapes: List[List[Float64]],
    ):
        """Hold a result. `solve_modes` makes these.

        Args:
            frequencies: The frequencies, ascending, in hertz.
            shapes: One mass-normalized shape per frequency.
        """
        self.frequencies = frequencies^
        self.shapes = shapes^


def solve_modes(model: StructuralModel, count: Int) raises -> ModalResult:
    """Return the lowest natural frequencies and mode shapes.

    Args:
        model: The model. Every free degree of freedom needs mass, so a
            node with no member, no shell and no added mass is refused.
        count: How many modes. From one to the number of free degrees of
            freedom.

    Returns:
        The frequencies, ascending, and their shapes.

    Raises:
        Error: If the structure is a mechanism, the count is out of range,
            the mass is not positive definite, or the iteration does not
            converge.
    """
    var equation = free_equations(model)
    var size = 0
    for i in range(len(equation)):
        if equation[i] >= 0:
            size += 1
    var k = reduce_matrix(assemble_stiffness(model), equation, size)
    _ = factor_stiffness(k)
    var m = reduce_matrix(assemble_mass(model), equation, size)
    var modes = lowest_modes(k, m, count, _TOLERANCE, _ITERATIONS)
    var frequencies = List[Frequency64](capacity=count)
    var shapes = List[List[Float64]](capacity=count)
    for i in range(count):  # pragma: no branch
        frequencies.append(Frequency64(sqrt(modes.values[i]) / (2 * pi)))
        var shape = List[Float64](length=len(equation), fill=0)
        for j in range(len(equation)):  # pragma: no branch
            if equation[j] >= 0:
                shape[j] = modes.vectors[i][equation[j]]
        shapes.append(shape^)
    return ModalResult(frequencies^, shapes^)
