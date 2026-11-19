# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Large deformation of soft tissue, by the compressible Neo-Hookean solid.

Soft tissues such as the wall of an artery, the liver and the brain
stretch by tens of percent. Linear elasticity holds for small strains
only. `solve_neo_hookean` solves a `StaticProblem` of four-node
tetrahedra with the compressible Neo-Hookean solid, whose stored energy
is:

    W = mu / 2 (I1 - 3) - mu ln J + lambda / 2 (ln J)^2

`I1` is the trace of `F^T F`, `F` is the deformation gradient, `J` is its
determinant, and `mu` and `lambda` are the Lame constants of each
material. At small strains it is the linear elastic solid of the same
material.

1. The loads and the prescribed displacements grow in `steps` equal
   steps.
2. Each step solves for equilibrium by Newton's method. The first
   Piola-Kirchhoff stress is `P = mu F + (lambda ln J - mu) F^-T`. The
   tangent is exact, and the conjugate gradient solves it on the free
   degrees of freedom.
3. A step stops when the residual of the free degrees of freedom falls to
   `tolerance` times its first value in the step.

The Cauchy stress of an element is
`sigma = mu / J (F F^T - I) + lambda ln J / J I`.
"""

from extensions.fem.elasticity import shape_gradients, von_mises
from extensions.fem.ids import LINEAR
from extensions.fem.mesh import signed_volume
from extensions.fem.static import StaticProblem
from extensions.numerics.iterative import conjugate_gradient
from extensions.numerics.matrix3x3 import Matrix3x3, adjugate3, determinant3
from extensions.numerics.sparse import SparseBuilder
from extensions.sdf.vector import V3, dot
from std.math import log, sqrt
from units.si import PASCAL, Pressure64


struct HyperelasticResult(Movable):
    """The displacements, stresses and reactions of a large deformation."""

    var displacements: List[Float64]
    """Three per node, in meters."""
    var stresses: List[Float64]
    """The Cauchy stress, six per element, in Voigt order, in pascals."""
    var von_mises: List[Pressure64]
    """The von Mises stress of each element's Cauchy stress."""
    var jacobians: List[Float64]
    """`J`, the volume of each element over its volume at rest."""
    var reactions: List[Float64]
    """Three per node, in newtons. Zero where nothing is prescribed."""
    var newton_steps: Int
    """How many Newton steps ran, over every load step."""
    var converged: Bool
    """Whether each load step reached its tolerance."""

    def __init__(out self, nodes: Int, elements: Int):
        """Create a result of zeros.

        Args:
            nodes: The node count.
            elements: The element count.
        """
        self.displacements = List[Float64](length=3 * nodes, fill=0)
        self.stresses = List[Float64](length=6 * elements, fill=0)
        self.von_mises = List[Pressure64](
            length=elements, fill=Pressure64(0, PASCAL)
        )
        self.jacobians = List[Float64](length=elements, fill=1)
        self.reactions = List[Float64](length=3 * nodes, fill=0)
        self.newton_steps = 0
        self.converged = True


struct _State(Movable):
    """The internal forces, the tangent and the stresses at a displacement."""

    var forces: List[Float64]
    var tangent: SparseBuilder
    var stresses: List[Float64]
    var jacobians: List[Float64]

    def __init__(out self, dofs: Int, elements: Int) raises:
        self.forces = List[Float64](length=dofs, fill=0)
        self.tangent = SparseBuilder(dofs)
        self.stresses = List[Float64](length=6 * elements, fill=0)
        self.jacobians = List[Float64](length=elements, fill=1)


def _state(
    problem: StaticProblem,
    gradients: List[V3],
    volumes: List[Float64],
    u: List[Float64],
) raises -> _State:
    """Return the internal forces, the tangent and the stresses."""
    ref mesh = problem.mesh
    var out = _State(len(u), mesh.element_count())
    for e in range(mesh.element_count()):  # pragma: no branch
        var constants = problem.materials[mesh.materials[e]].lame()
        var lam = constants[0]
        var mu = constants[1]
        var f: List[Float64] = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
        for a in range(4):  # pragma: no branch
            var node = mesh.corners[4 * e + a]
            ref g = gradients[4 * e + a]
            for i in range(3):  # pragma: no branch
                var d = u[3 * node + i]
                f[3 * i] += d * g.x
                f[3 * i + 1] += d * g.y
                f[3 * i + 2] += d * g.z
        var m = Matrix3x3(0)
        for k in range(9):  # pragma: no branch
            m[k] = f[k]
        var j = determinant3(m)
        if not (j > 0):
            raise Error("An element turned inside out; take more load steps")
        var inv = adjugate3(m) / j
        var lnj = log(j)
        var v0 = volumes[e]
        # The spatial gradient of each shape function: F^-T times its
        # gradient at rest.
        var h = List[Float64](length=12, fill=0)
        for a in range(4):  # pragma: no branch
            ref g = gradients[4 * e + a]
            for i in range(3):  # pragma: no branch
                h[3 * a + i] = (
                    g.x * inv[i] + g.y * inv[3 + i] + g.z * inv[6 + i]
                )
        for a in range(4):  # pragma: no branch
            var row = mesh.corners[4 * e + a]
            ref ga = gradients[4 * e + a]
            for i in range(3):  # pragma: no branch
                var fg = (
                    f[3 * i] * ga.x + f[3 * i + 1] * ga.y + f[3 * i + 2] * ga.z
                )
                out.forces[3 * row + i] += v0 * (
                    mu * fg + (lam * lnj - mu) * h[3 * a + i]
                )
            for b in range(4):  # pragma: no branch
                var col = mesh.corners[4 * e + b]
                var gg = dot(ga, gradients[4 * e + b])
                for i in range(3):  # pragma: no branch
                    for k in range(3):  # pragma: no branch
                        var value = (
                            lam * h[3 * a + i] * h[3 * b + k]
                            + (mu - lam * lnj) * h[3 * a + k] * h[3 * b + i]
                        )
                        if i == k:
                            value += mu * gg
                        out.tangent.add(3 * row + i, 3 * col + k, v0 * value)
        # sigma = mu / J (F F^T - I) + lambda ln J / J I.
        var bb = List[Float64](length=9, fill=0)
        for i in range(3):  # pragma: no branch
            for k in range(3):  # pragma: no branch
                bb[3 * i + k] = (
                    f[3 * i] * f[3 * k]
                    + f[3 * i + 1] * f[3 * k + 1]
                    + f[3 * i + 2] * f[3 * k + 2]
                )
        var bulk = lam * lnj / j
        var shear = mu / j
        out.stresses[6 * e] = shear * (bb[0] - 1.0) + bulk
        out.stresses[6 * e + 1] = shear * (bb[4] - 1.0) + bulk
        out.stresses[6 * e + 2] = shear * (bb[8] - 1.0) + bulk
        out.stresses[6 * e + 3] = shear * bb[5]
        out.stresses[6 * e + 4] = shear * bb[2]
        out.stresses[6 * e + 5] = shear * bb[1]
        out.jacobians[e] = j
    return out^


def solve_neo_hookean(
    problem: StaticProblem,
    steps: Int,
    tolerance: Float64,
    newton_limit: Int,
    cg_tolerance: Float64,
    cg_limit: Int,
) raises -> HyperelasticResult:
    """Solve a problem of four-node tetrahedra as a Neo-Hookean solid.

    Args:
        problem: The problem, with its loads and prescribed displacements
            at their full size. It has no thermal load.
        steps: The load steps, from 1 to 1000.
        tolerance: The residual at which a step stops, over its first
            residual. Positive and below 1.
        newton_limit: The most Newton steps in a load step, one or more.
        cg_tolerance: The relative residual of each linear solve.
        cg_limit: The conjugate gradient budget of each linear solve.

    Returns:
        The displacements, the Cauchy stresses and the reactions. Check
        `converged`: a load step that ran out of Newton steps returns its
        last state.

    Raises:
        Error: If the mesh is not of four-node tetrahedra, the problem
            has a thermal load, a count or a tolerance is out of range, an
            element turns inside out, or a linear solve refuses its
            system.
    """
    ref mesh = problem.mesh
    if mesh.order != LINEAR:
        raise Error("A Neo-Hookean solve takes four-node tetrahedra")
    for strain in problem.thermal:  # pragma: no branch
        if strain != 0:
            raise Error("A Neo-Hookean solve takes no thermal load")
    if steps < 1 or steps > 1000:
        raise Error("A Neo-Hookean solve takes 1 to 1000 load steps")
    if not (tolerance > 0) or not (tolerance < 1):
        raise Error("A Newton tolerance is above 0 and below 1")
    if newton_limit < 1:
        raise Error("A load step needs one Newton step or more")
    var gradients = List[V3]()
    var volumes = List[Float64]()
    for e in range(mesh.element_count()):  # pragma: no branch
        var p = List[V3]()
        for a in range(4):  # pragma: no branch
            p.append(mesh.nodes[mesh.corners[4 * e + a]])
        for g in shape_gradients(p[0], p[1], p[2], p[3]):  # pragma: no branch
            gradients.append(g)
        volumes.append(signed_volume(p[0], p[1], p[2], p[3]))
    var dofs = 3 * mesh.node_count()
    var free_index = List[Int](length=dofs, fill=-1)
    var free = 0
    for dof in range(dofs):  # pragma: no branch
        if not problem.prescribed[dof]:
            free_index[dof] = free
            free += 1
    var result = HyperelasticResult(mesh.node_count(), mesh.element_count())
    var u = List[Float64](length=dofs, fill=0)
    var state = _state(problem, gradients, volumes, u)
    var scale = 0.0
    for step in range(1, steps + 1):  # pragma: no branch
        scale = Float64(step) / Float64(steps)
        for dof in range(dofs):  # pragma: no branch
            if problem.prescribed[dof]:
                u[dof] = scale * problem.values[dof]
        var first = 0.0
        var done = False
        for newton in range(newton_limit):  # pragma: no branch
            state = _state(problem, gradients, volumes, u)
            var residual = List[Float64](length=free, fill=0)
            var norm = 0.0
            for dof in range(dofs):  # pragma: no branch
                var r = free_index[dof]
                if r >= 0:
                    residual[r] = (
                        scale * problem.forces[dof] - state.forces[dof]
                    )
                    norm += residual[r] * residual[r]
            norm = sqrt(norm)
            if newton == 0:
                first = norm
            elif norm <= tolerance * first:
                done = True
                break
            if free == 0:
                done = True
                break
            result.newton_steps += 1
            var k = state.tangent.build()
            var reduced = SparseBuilder(free)
            for row in range(dofs):  # pragma: no branch
                var r = free_index[row]
                if r < 0:
                    continue
                for at in range(
                    k.row_start[row], k.row_start[row + 1]
                ):  # pragma: no branch
                    var c = free_index[k.columns[at]]
                    if c >= 0:
                        reduced.add(r, c, k.values[at])
            var solved = conjugate_gradient(
                reduced.build(), residual, cg_tolerance, cg_limit
            )
            for dof in range(dofs):  # pragma: no branch
                if free_index[dof] >= 0:
                    u[dof] += solved.x[free_index[dof]]
        if not done:
            result.converged = False
            break
    # The state of the last displacements, with the loads of the last
    # step.
    state = _state(problem, gradients, volumes, u)
    for dof in range(dofs):  # pragma: no branch
        if problem.prescribed[dof]:
            result.reactions[dof] = (
                state.forces[dof] - scale * problem.forces[dof]
            )
    result.displacements = u^
    for e in range(mesh.element_count()):  # pragma: no branch
        var sigma = List[Float64]()
        for part in range(6):  # pragma: no branch
            sigma.append(state.stresses[6 * e + part])
            result.stresses[6 * e + part] = state.stresses[6 * e + part]
        result.von_mises[e] = von_mises(sigma)
        result.jacobians[e] = state.jacobians[e]
    return result^
