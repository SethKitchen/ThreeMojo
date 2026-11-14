# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Static linear elasticity: supports, loads, a solve and the stresses.

A `StaticProblem` holds a mesh, its materials, the prescribed
displacements and the nodal forces. `solve_static` assembles the global
stiffness, removes the prescribed degrees of freedom and solves the
rest by preconditioned conjugate gradients. It returns the displacement
of each node, the strain and stress of each element, the von Mises
stress and the reaction at each prescribed degree of freedom.

The supports must stop the mesh from moving as a rigid body. A mesh
that can still move has a singular stiffness, and the solve refuses it.
"""

from extensions.fem.elasticity import (
    IsotropicMaterial,
    element_stiffness,
    element_strain,
    quadratic_gradients,
    quadratic_stiffness,
    shape_gradients,
    stress_of,
    von_mises,
)
from extensions.fem.ids import (
    DofAxis,
    ElementId,
    MaterialId,
    NodeId,
    require_dof_axis,
    require_id,
)
from extensions.fem.ids import LINEAR
from extensions.fem.mesh import TetMesh, boundary_faces, edge_pairs
from std.collections import Dict
from extensions.numerics.iterative import SolveStatus, conjugate_gradient
from extensions.numerics.sparse import CsrMatrix, SparseBuilder
from extensions.sdf.vector import V3, cross, length, v3
from std.math import isfinite, max, min
from units.si import Force64, Length64, METER, NEWTON, PASCAL, Pressure64


struct StaticProblem(Movable):
    """A mesh with its materials, supports and loads."""

    var mesh: TetMesh
    """The mesh."""
    var materials: List[IsotropicMaterial]
    """The materials that the elements name."""
    var prescribed: List[Bool]
    """Whether each degree of freedom has a prescribed displacement."""
    var values: List[Float64]
    """The prescribed displacement of each degree of freedom, in meters."""
    var forces: List[Float64]
    """The force on each degree of freedom, in newtons."""

    def __init__(
        out self, var mesh: TetMesh, var materials: List[IsotropicMaterial]
    ) raises:
        """Create a problem with no supports and no loads.

        Args:
            mesh: The mesh. It holds at least one element.
            materials: The materials. Each element's material id must
                name one.

        Raises:
            Error: If the mesh has no elements, or an element names a
                material that the list does not hold.
        """
        if mesh.element_count() == 0:
            raise Error("A problem needs a mesh with at least one element")
        for e in range(mesh.element_count()):  # pragma: no branch
            var id = MaterialId(mesh.materials[e])
            require_id(id.is_valid(), id.value, len(materials), "material")
        var dofs = 3 * mesh.node_count()
        self.mesh = mesh^
        self.materials = materials^
        self.prescribed = List[Bool](length=dofs, fill=False)
        self.values = List[Float64](length=dofs, fill=0)
        self.forces = List[Float64](length=dofs, fill=0)

    def fix(
        mut self, node: NodeId, axis: DofAxis, displacement: Length64
    ) raises:
        """Prescribe the displacement of one node along one axis.

        Args:
            node: The node.
            axis: The axis.
            displacement: The displacement. Zero holds the node still.

        Raises:
            Error: If the node or the axis is not valid, or the
                displacement is not finite.
        """
        self.mesh.require_node(node)
        require_dof_axis(axis)
        var meters = displacement.to(METER)
        if not isfinite(meters):
            raise Error("A prescribed displacement must be finite")
        var dof = 3 * node.value + axis.value
        self.prescribed[dof] = True
        self.values[dof] = meters

    def load(mut self, node: NodeId, axis: DofAxis, force: Force64) raises:
        """Add a force on one node along one axis.

        Args:
            node: The node.
            axis: The axis.
            force: The force. It adds to any force there already.

        Raises:
            Error: If the node or the axis is not valid, or the force is
                not finite.
        """
        self.mesh.require_node(node)
        require_dof_axis(axis)
        var newtons = force.to(NEWTON)
        if not isfinite(newtons):
            raise Error("A force must be finite")
        self.forces[3 * node.value + axis.value] += newtons

    def press_plane(
        mut self,
        axis: DofAxis,
        at: Length64,
        tolerance: Length64,
        stress: Pressure64,
    ) raises -> Int:
        """Load the outer faces on a plane with a uniform normal stress.

        The plane holds the points whose coordinate on `axis` is `at`. A
        face is on it when its three nodes are within `tolerance` of it.
        Each face of area `A` adds `stress * A / 3` along `axis`: to each of
        its corners in a linear mesh, and to each of its edge nodes in a
        quadratic one. These are the consistent loads of three-node and
        six-node triangles.

        Args:
            axis: The axis normal to the plane.
            at: The coordinate of the plane.
            tolerance: How far a node can be from the plane.
            stress: The stress. A positive stress pulls along `axis`.

        Returns:
            How many faces the plane holds.

        Raises:
            Error: If the axis is not valid, or the stress is not finite.
        """
        require_dof_axis(axis)
        var pascals = stress.to(PASCAL)
        if not isfinite(pascals):
            raise Error("A stress must be finite")
        var on_plane = List[Bool](length=self.mesh.node_count(), fill=False)
        for node in self.mesh.nodes_on_plane(axis, at, tolerance):
            on_plane[node.value] = True
        var faces = boundary_faces(self.mesh)
        var middles = _edge_nodes(self.mesh)
        var count = 0
        # A problem's mesh has an element, so it has outer faces.
        for face in range(len(faces) // 4):  # pragma: no branch
            var a = faces[4 * face]
            var b = faces[4 * face + 1]
            var c = faces[4 * face + 2]
            var corners = Int(on_plane[a]) + Int(on_plane[b]) + Int(on_plane[c])
            if corners < 3:
                continue
            ref nodes = self.mesh.nodes
            var area = (
                length(cross(nodes[b] - nodes[a], nodes[c] - nodes[a])) / 2
            )
            var share = pascals * area / 3.0
            var loaded: List[Int] = [a, b, c]
            if self.mesh.order != LINEAR:
                # A six-node triangle carries a uniform stress on its edge
                # nodes alone.
                var n = self.mesh.node_count()
                loaded = [
                    middles[min(a, b) * n + max(a, b)],
                    middles[min(b, c) * n + max(b, c)],
                    middles[min(a, c) * n + max(a, c)],
                ]
            for node in loaded:  # pragma: no branch
                self.forces[3 * node + axis.value] += share
            count += 1
        return count


def _edge_nodes(mesh: TetMesh) -> Dict[Int, Int]:
    """Return the edge node of each edge of a quadratic mesh, keyed by its
    two corners as `low * node_count + high`. A linear mesh has none."""
    var out = Dict[Int, Int]()
    if mesh.order == LINEAR:
        return out^
    var n = mesh.node_count()
    var pairs = edge_pairs()
    for e in range(mesh.element_count()):  # pragma: no branch
        for edge in range(6):
            var a = mesh.corners[10 * e + pairs[2 * edge]]
            var b = mesh.corners[10 * e + pairs[2 * edge + 1]]
            out[min(a, b) * n + max(a, b)] = mesh.corners[10 * e + 4 + edge]
    return out^


struct StaticResult(Movable):
    """The displacements, stresses and reactions of a solved problem."""

    var displacements: List[Float64]
    """Three per node, in meters."""
    var strains: List[Float64]
    """Six per element, in Voigt order with engineering shears."""
    var stresses: List[Float64]
    """Six per element, in Voigt order, in pascals."""
    var von_mises: List[Pressure64]
    """One per element."""
    var reactions: List[Float64]
    """Three per node, in newtons. Zero where nothing is prescribed."""
    var iterations: Int
    """How many conjugate gradient iterations ran."""
    var relative_residual: Float64
    """The final residual norm over the norm of the right-hand side."""
    var status: SolveStatus
    """`CONVERGED`, or `BUDGET_EXHAUSTED` when the budget ran out."""

    def __init__(out self, nodes: Int, elements: Int):
        """Create a result of zeros.

        Args:
            nodes: The node count.
            elements: The element count.
        """
        self.displacements = List[Float64](length=3 * nodes, fill=0)
        self.strains = List[Float64](length=6 * elements, fill=0)
        self.stresses = List[Float64](length=6 * elements, fill=0)
        self.von_mises = List[Pressure64](
            length=elements, fill=Pressure64(0, PASCAL)
        )
        self.reactions = List[Float64](length=3 * nodes, fill=0)
        self.iterations = 0
        self.relative_residual = 0
        self.status = SolveStatus(0)

    def displacement(self, node: NodeId) raises -> V3:
        """Return the displacement of one node.

        Args:
            node: The node.

        Returns:
            The displacement, in meters.

        Raises:
            Error: If the node id names no node.
        """
        require_id(
            node.is_valid(), node.value, len(self.displacements) // 3, "node"
        )
        var at = 3 * node.value
        return v3(
            self.displacements[at],
            self.displacements[at + 1],
            self.displacements[at + 2],
        )


def _corners(mesh: TetMesh, element: Int) -> List[V3]:
    """Return the four corners of an element."""
    var at = mesh.nodes_per_element() * element
    return [
        mesh.nodes[mesh.corners[at]],
        mesh.nodes[mesh.corners[at + 1]],
        mesh.nodes[mesh.corners[at + 2]],
        mesh.nodes[mesh.corners[at + 3]],
    ]


def assemble(problem: StaticProblem) raises -> CsrMatrix:
    """Return the global stiffness of every degree of freedom.

    Args:
        problem: The problem.

    Returns:
        The symmetric stiffness, in newtons per meter, with three rows for
        each node.

    Raises:
        Error: If the matrix is too large to store.
    """
    ref mesh = problem.mesh
    var builder = SparseBuilder(3 * mesh.node_count())
    var count = mesh.nodes_per_element()
    var size = 3 * count
    for e in range(mesh.element_count()):  # pragma: no branch
        var material = problem.materials[mesh.materials[e]]
        var k: List[Float64]
        if mesh.order == LINEAR:
            k = element_stiffness(_corners(mesh, e), material)
        else:
            k = quadratic_stiffness(_corners(mesh, e), material)
        for a in range(count):  # pragma: no branch
            var row_node = mesh.corners[count * e + a]
            for b in range(count):  # pragma: no branch
                var col_node = mesh.corners[count * e + b]
                for i in range(3):
                    for j in range(3):
                        builder.add(
                            3 * row_node + i,
                            3 * col_node + j,
                            k[(3 * a + i) * size + 3 * b + j],
                        )
    return builder.build()


def solve_static(
    problem: StaticProblem, tolerance: Float64, max_iterations: Int
) raises -> StaticResult:
    """Solve a static problem.

    Args:
        problem: The problem.
        tolerance: The relative residual at which the solve stops.
        max_iterations: The iteration budget.

    Returns:
        The displacements, strains, stresses and reactions. Check `status`:
        a solve that ran out of iterations returns its last iterate.

    Raises:
        Error: If the tolerance is not positive and finite, the budget is
            negative, or the supports leave the mesh free to move.
    """
    ref mesh = problem.mesh
    var dofs = 3 * mesh.node_count()
    var k = assemble(problem)
    var free_index = List[Int](length=dofs, fill=-1)
    var free = 0
    for dof in range(dofs):  # pragma: no branch
        if not problem.prescribed[dof]:
            free_index[dof] = free
            free += 1
    var u = List[Float64](length=dofs, fill=0)
    for dof in range(dofs):  # pragma: no branch
        if problem.prescribed[dof]:
            u[dof] = problem.values[dof]
    var result = StaticResult(mesh.node_count(), mesh.element_count())
    if free > 0:
        var reduced = SparseBuilder(free)
        var rhs = List[Float64](length=free, fill=0)
        for row in range(dofs):  # pragma: no branch
            var r = free_index[row]
            if r < 0:
                continue
            rhs[r] += problem.forces[row]
            for at in range(
                k.row_start[row], k.row_start[row + 1]
            ):  # pragma: no branch
                var col = k.columns[at]
                var c = free_index[col]
                if c < 0:
                    rhs[r] -= k.values[at] * u[col]
                else:
                    reduced.add(r, c, k.values[at])
        var solved = conjugate_gradient(
            reduced.build(), rhs, tolerance, max_iterations
        )
        for dof in range(dofs):  # pragma: no branch
            if free_index[dof] >= 0:
                u[dof] = solved.x[free_index[dof]]
        result.iterations = solved.iterations
        result.relative_residual = solved.relative_residual
        result.status = solved.status
    var internal = k.multiply(u)
    for dof in range(dofs):  # pragma: no branch
        if problem.prescribed[dof]:
            result.reactions[dof] = internal[dof] - problem.forces[dof]
    result.displacements = u^
    for e in range(mesh.element_count()):  # pragma: no branch
        var corners = _corners(mesh, e)
        var g = shape_gradients(corners[0], corners[1], corners[2], corners[3])
        var count = mesh.nodes_per_element()
        if mesh.order != LINEAR:
            # The strain at the centroid, where each volume coordinate is a
            # quarter.
            g = quadratic_gradients(g, [0.25, 0.25, 0.25, 0.25])
        var moves = List[V3]()
        for a in range(count):  # pragma: no branch
            var n = mesh.corners[count * e + a]
            moves.append(
                v3(
                    result.displacements[3 * n],
                    result.displacements[3 * n + 1],
                    result.displacements[3 * n + 2],
                )
            )
        var strain = element_strain(g, moves)
        var stress = stress_of(strain, problem.materials[mesh.materials[e]])
        for part in range(6):
            result.strains[6 * e + part] = strain[part]
            result.stresses[6 * e + part] = stress[part]
        result.von_mises[e] = von_mises(stress)
    return result^
