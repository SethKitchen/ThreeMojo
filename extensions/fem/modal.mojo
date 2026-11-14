# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Natural frequencies and mode shapes of a tetrahedral mesh.

A solid vibrates freely in its modes. Mode `i` has the angular frequency
`omega_i`, where `K phi = omega^2 M phi`. `K` is the stiffness of the
static problem and `M` is the consistent mass:

    M[3a + i, 3b + j] = delta_ij * integral of rho N_a N_b

The integral is exact. For a four-node element it is
`rho V (1 + delta_ab) / 20`. For a ten-node element it is `rho V c / 420`,
where `c` is 6 on the diagonal of a corner, 1 between two corners, -4
between a corner and an edge that holds it, -6 between a corner and
another edge, 32 on the diagonal of an edge, 16 between two edges that
share a corner and 8 between opposite edges.

`natural_modes` removes the prescribed degrees of freedom, so the
supports of the problem hold during the vibration, and solves for the
lowest modes by the subspace iteration of the numerics extension. A
Sturm check makes sure that no lower mode was missed.
"""

from extensions.fem.ids import LINEAR
from extensions.fem.mesh import TetMesh, edge_pairs, signed_volume
from extensions.fem.static import StaticProblem, assemble
from extensions.numerics.eigen import lowest_modes
from extensions.numerics.sparse import CsrMatrix, SparseBuilder
from std.math import isfinite, max, min, pi, sqrt
from units.si import Density64, Frequency64, KILOGRAM_PER_CUBIC_METER


def mass_coefficients(nodes: Int) raises -> List[Float64]:
    """Return the consistent mass of an element of unit mass, per node pair.

    Args:
        nodes: 4 for a linear element, or 10 for a quadratic one.

    Returns:
        `nodes * nodes` numbers, row by row. Entry `(a, b)` is the
        integral of `N_a N_b` over the element, over its volume. The
        entries sum to one.

    Raises:
        Error: If `nodes` is not 4 or 10.
    """
    if nodes != 4 and nodes != 10:
        raise Error("An element has 4 or 10 nodes")
    var out = List[Float64](length=nodes * nodes, fill=0)
    var pairs = edge_pairs()
    for a in range(nodes):  # pragma: no branch
        for b in range(nodes):  # pragma: no branch
            var c: Float64
            if nodes == 4:
                c = 42.0 if a == b else 21.0
            elif a < 4 and b < 4:
                c = 6.0 if a == b else 1.0
            elif a >= 4 and b >= 4:
                var e = a - 4
                var f = b - 4
                var shared = (
                    pairs[2 * e] == pairs[2 * f]
                    or pairs[2 * e] == pairs[2 * f + 1]
                    or pairs[2 * e + 1] == pairs[2 * f]
                    or pairs[2 * e + 1] == pairs[2 * f + 1]
                )
                if a == b:
                    c = 32.0
                elif shared:
                    c = 16.0
                else:
                    c = 8.0
            else:
                var corner = min(a, b)
                var e = max(a, b) - 4
                var holds = pairs[2 * e] == corner or pairs[2 * e + 1] == corner
                c = -4.0 if holds else -6.0
            out[a * nodes + b] = c / 420.0
    return out^


def assemble_mass(
    mesh: TetMesh, densities: List[Density64]
) raises -> CsrMatrix:
    """Return the global consistent mass of every degree of freedom.

    Args:
        mesh: The mesh.
        densities: The density of each material, by material id.

    Returns:
        The symmetric mass, in kilograms, with three rows for each node.

    Raises:
        Error: If an element names a material without a density, or a
            density is not positive and finite.
    """
    for density in densities:  # pragma: no branch
        var rho = density.to(KILOGRAM_PER_CUBIC_METER)
        if not (rho > 0) or not isfinite(rho):
            raise Error("A density must be positive and finite")
    var count = mesh.nodes_per_element()
    var unit = mass_coefficients(count)
    var builder = SparseBuilder(3 * mesh.node_count())
    for e in range(mesh.element_count()):  # pragma: no branch
        var material = mesh.materials[e]
        if material >= len(densities):
            raise Error("An element names a material without a density")
        var at = count * e
        var volume = abs(
            signed_volume(
                mesh.nodes[mesh.corners[at]],
                mesh.nodes[mesh.corners[at + 1]],
                mesh.nodes[mesh.corners[at + 2]],
                mesh.nodes[mesh.corners[at + 3]],
            )
        )
        var mass = densities[material].to(KILOGRAM_PER_CUBIC_METER) * volume
        for a in range(count):  # pragma: no branch
            var row = mesh.corners[at + a]
            for b in range(count):  # pragma: no branch
                var col = mesh.corners[at + b]
                var value = mass * unit[a * count + b]
                for i in range(3):  # pragma: no branch
                    builder.add(3 * row + i, 3 * col + i, value)
    return builder.build()


struct ModalResult(Movable):
    """The lowest natural frequencies of a mesh, and its mode shapes."""

    var frequencies: List[Frequency64]
    """The natural frequencies, ascending, in cycles per second."""
    var shapes: List[List[Float64]]
    """One shape per mode: three numbers per node, zero where a degree of
    freedom is prescribed. Each shape has `phi^T M phi = 1`."""
    var iterations: Int
    """How many subspace iterations ran."""

    def __init__(out self):
        """Create a result without modes."""
        self.frequencies = List[Frequency64]()
        self.shapes = List[List[Float64]]()
        self.iterations = 0


def _reduce(
    matrix: CsrMatrix, free_index: List[Int], free: Int
) raises -> CsrMatrix:
    """Return the rows and columns of the free degrees of freedom."""
    var builder = SparseBuilder(free)
    for row in range(matrix.size):  # pragma: no branch
        var r = free_index[row]
        if r < 0:
            continue
        for at in range(
            matrix.row_start[row], matrix.row_start[row + 1]
        ):  # pragma: no branch
            var c = free_index[matrix.columns[at]]
            if c >= 0:
                builder.add(r, c, matrix.values[at])
    return builder.build()


def natural_modes(
    problem: StaticProblem,
    densities: List[Density64],
    count: Int,
    tolerance: Float64,
    max_iterations: Int,
) raises -> ModalResult:
    """Return the lowest natural frequencies and mode shapes of a problem.

    The prescribed degrees of freedom hold still. The loads of the
    problem do not matter.

    Args:
        problem: The mesh, materials and supports.
        densities: The density of each material, by material id.
        count: How many modes. From one to the free degrees of freedom.
        tolerance: The relative change of each eigenvalue at which the
            iteration stops, such as 1e-10.
        max_iterations: The iteration budget. One or more.

    Returns:
        The frequencies and the mass-normalized shapes.

    Raises:
        Error: If no degree of freedom is free, the densities do not fit
            the materials, an argument is out of range, the supports leave
            the mesh free to move, or the iteration does not converge.
    """
    ref mesh = problem.mesh
    var dofs = 3 * mesh.node_count()
    var free_index = List[Int](length=dofs, fill=-1)
    var free = 0
    for dof in range(dofs):  # pragma: no branch
        if not problem.prescribed[dof]:
            free_index[dof] = free
            free += 1
    if free == 0:
        raise Error("A modal analysis needs a free degree of freedom")
    var k = _reduce(assemble(problem), free_index, free)
    var m = _reduce(assemble_mass(mesh, densities), free_index, free)
    var modes = lowest_modes(k, m, count, tolerance, max_iterations)
    var out = ModalResult()
    out.iterations = modes.iterations
    for i in range(len(modes.values)):  # pragma: no branch
        out.frequencies.append(Frequency64(sqrt(modes.values[i]) / (2 * pi)))
        var shape = List[Float64](length=dofs, fill=0)
        for dof in range(dofs):  # pragma: no branch
            if free_index[dof] >= 0:
                shape[dof] = modes.vectors[i][free_index[dof]]
        out.shapes.append(shape^)
    return out^
