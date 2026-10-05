# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Linear static analysis of a structural model.

`StaticSolver` assembles the global stiffness, removes the fixed degrees
of freedom and factors the rest once, in skyline form after a reverse
Cuthill-McKee ordering. Each call to `solve` then gives one load case:
the displacements, the support reactions, the member end forces and the
shell resultants.

A structure that can move without strain is a mechanism. Its stiffness is
singular, and `StaticSolver` refuses it.
"""

from std.math import isfinite
from extensions.numerics.dense import DenseMatrix
from extensions.numerics.skyline import SkylineFactor, reverse_cuthill_mckee
from extensions.numerics.sparse import CsrMatrix, SparseBuilder
from extensions.structure.frame import (
    LocalAxes,
    frame_local_stiffness,
    frame_transformation,
    member_axes,
    uniform_load_vector,
)
from extensions.structure.ids import LoadCaseId, MemberId, NodeId, ShellId
from extensions.structure.kinds import Dof
from extensions.structure.model import StructuralModel
from extensions.structure.shell import ShellResultants
from generators.utils import Vec3d
from units.si import (
    Angle64,
    Force64,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    LineLoad64,
    METER,
    Moment64,
    SQUARE_METER,
)


@fieldwise_init
struct EndForces(ImplicitlyCopyable):
    """The force and moment that a node applies to a member end.

    The components are along the member's local axes. At the end node a
    positive axial force is tension. At the start node it is compression.
    """

    var axial: Force64
    var shear_y: Force64
    var shear_z: Force64
    var torque: Moment64
    var moment_y: Moment64
    var moment_z: Moment64


@fieldwise_init
struct MemberForces(ImplicitlyCopyable):
    """The end forces of a member and its local axes."""

    var axes: LocalAxes
    var start: EndForces
    var end: EndForces


def _end_forces(f: List[Float64], o: Int) -> EndForces:
    """Return six local end forces from a 12-vector at an offset."""
    return EndForces(
        Force64(f[o]),
        Force64(f[o + 1]),
        Force64(f[o + 2]),
        Moment64(f[o + 3]),
        Moment64(f[o + 4]),
        Moment64(f[o + 5]),
    )


struct StaticResult(Movable):
    """The response of a structure to one load case.

    The vectors have six entries per node, in the order of `Dof`, in
    meters, radians, newtons and newton meters.
    """

    var displacements: List[Float64]
    # The forces the supports apply. Zero at a free degree of freedom.
    var reactions: List[Float64]
    # The applied loads, with member and shell loads as nodal loads.
    var loads: List[Float64]
    var member_forces: List[MemberForces]
    var shell_resultants: List[ShellResultants]

    def __init__(
        out self,
        var displacements: List[Float64],
        var reactions: List[Float64],
        var loads: List[Float64],
        var member_forces: List[MemberForces],
        var shell_resultants: List[ShellResultants],
    ):
        """Hold a result. `StaticSolver.solve` makes these.

        Args:
            displacements: Six per node.
            reactions: Six per node.
            loads: Six per node.
            member_forces: One per member.
            shell_resultants: One per shell.
        """
        self.displacements = displacements^
        self.reactions = reactions^
        self.loads = loads^
        self.member_forces = member_forces^
        self.shell_resultants = shell_resultants^

    def _index(self, node: NodeId, dof: Dof) raises -> Int:
        """Return the entry of a node's degree of freedom."""
        if not node.is_valid() or 6 * node.value >= len(self.displacements):
            raise Error("A node id is out of range")
        return 6 * node.value + dof.value

    def translation(self, node: NodeId, dof: Dof) raises -> Length64:
        """Return a displacement along a global axis.

        Args:
            node: The node.
            dof: `UX`, `UY` or `UZ`.

        Returns:
            The displacement.

        Raises:
            Error: If the node id is out of range or the degree of freedom
                is not a translation.
        """
        if not dof.is_translation():
            raise Error("A translation needs UX, UY or UZ")
        return Length64(self.displacements[self._index(node, dof)])

    def rotation(self, node: NodeId, dof: Dof) raises -> Angle64:
        """Return a rotation about a global axis.

        Args:
            node: The node.
            dof: `RX`, `RY` or `RZ`.

        Returns:
            The right-handed rotation.

        Raises:
            Error: If the node id is out of range or the degree of freedom
                is not a rotation.
        """
        if not dof.is_rotation():
            raise Error("A rotation needs RX, RY or RZ")
        return Angle64(self.displacements[self._index(node, dof)])

    def reaction_force(self, node: NodeId, dof: Dof) raises -> Force64:
        """Return a support force along a global axis.

        Args:
            node: The node.
            dof: `UX`, `UY` or `UZ`.

        Returns:
            The force the support applies, or zero if it is free.

        Raises:
            Error: If the node id is out of range or the degree of freedom
                is not a translation.
        """
        if not dof.is_translation():
            raise Error("A reaction force needs UX, UY or UZ")
        return Force64(self.reactions[self._index(node, dof)])

    def reaction_moment(self, node: NodeId, dof: Dof) raises -> Moment64:
        """Return a support moment about a global axis.

        Args:
            node: The node.
            dof: `RX`, `RY` or `RZ`.

        Returns:
            The moment the support applies, or zero if it is free.

        Raises:
            Error: If the node id is out of range or the degree of freedom
                is not a rotation.
        """
        if not dof.is_rotation():
            raise Error("A reaction moment needs RX, RY or RZ")
        return Moment64(self.reactions[self._index(node, dof)])


def _member_dofs(model: StructuralModel, m: Int) -> List[Int]:
    """Return the twelve global entries of a member."""
    var out = List[Int](capacity=12)
    var ends = [model.members[m].start.value, model.members[m].end.value]
    for e in range(2):  # pragma: no branch
        for d in range(6):  # pragma: no branch
            out.append(6 * ends[e] + d)
    return out^


def _shell_dofs(model: StructuralModel, s: Int) -> List[Int]:
    """Return the eighteen global entries of a shell."""
    var out = List[Int](capacity=18)
    ref shell = model.shells[s]
    var corners = [shell.a.value, shell.b.value, shell.c.value]
    for e in range(3):  # pragma: no branch
        for d in range(6):  # pragma: no branch
            out.append(6 * corners[e] + d)
    return out^


def _axes(model: StructuralModel, m: Int) raises -> LocalAxes:
    """Return a member's local axes."""
    ref member = model.members[m]
    return member_axes(
        model.nodes[member.start.value],
        model.nodes[member.end.value],
        member.reference,
    )


def _length(model: StructuralModel, m: Int) -> Length64:
    """Return a member's length."""
    ref member = model.members[m]
    return Length64(
        model.nodes[member.start.value].distance_to(
            model.nodes[member.end.value]
        )
    )


def _add_block(
    mut builder: SparseBuilder, dofs: List[Int], block: DenseMatrix
) raises:
    """Add a dense element matrix at its global entries."""
    for i in range(len(dofs)):  # pragma: no branch
        for j in range(len(dofs)):  # pragma: no branch
            builder.add(dofs[i], dofs[j], block.get(i, j))


def assemble_stiffness(model: StructuralModel) raises -> CsrMatrix:
    """Return the global stiffness of every member and shell.

    No support is applied, so the matrix is singular.

    Args:
        model: The model.

    Returns:
        The stiffness, six rows per node.

    Raises:
        Error: If a member or shell cannot form its matrix.
    """
    var builder = SparseBuilder(model.dof_count())
    for m in range(len(model.members)):
        ref member = model.members[m]
        var t = frame_transformation(_axes(model, m))
        var k = frame_local_stiffness(
            _length(model, m), member.section, member.material
        )
        _add_block(builder, _member_dofs(model, m), t.triple_product(k))
    for s in range(len(model.shells)):
        var element = model.shell_element(ShellId(s))
        _add_block(builder, _shell_dofs(model, s), element.stiffness())
    return builder.build()


def member_loads(
    model: StructuralModel, load_case: LoadCaseId, member: MemberId
) raises -> List[Float64]:
    """Return the consistent nodal loads of a member's loads, locally.

    The line loads of the load case and, if the case has gravity, the member's
    weight are summed.

    Args:
        model: The model.
        load_case: The load case.
        member: The member.

    Returns:
        Twelve loads in the member's local axes.

    Raises:
        Error: If an id is out of range.
    """
    model.check_case(load_case)
    model.check_member(member)
    var w = Vec3d(0, 0, 0)
    for i in range(len(model.line_loads)):
        ref load = model.line_loads[i]
        if load.load_case == load_case and load.member == member:
            var axis = [Vec3d(1, 0, 0), Vec3d(0, 1, 0), Vec3d(0, 0, 1)]
            w = w + axis[load.dof.value] * load.value
    ref m = model.members[member.value]
    var weight = m.material.density.to(
        KILOGRAM_PER_CUBIC_METER
    ) * m.section.area().to(SQUARE_METER)
    for i in range(len(model.gravity)):
        if model.gravity[i].load_case == load_case:
            w = w + Vec3d(0, 0, -weight * model.gravity[i].acceleration)
    var local = _axes(model, member.value).to_local(w)
    return uniform_load_vector(
        _length(model, member.value),
        LineLoad64(local.x),
        LineLoad64(local.y),
        LineLoad64(local.z),
    )


def load_vector(
    model: StructuralModel, load_case: LoadCaseId
) raises -> List[Float64]:
    """Return the global load vector of a load case.

    Member loads become consistent nodal loads. A shell pressure and a
    shell weight put a third of their resultant at each corner.

    Args:
        model: The model.
        load_case: The load case.

    Returns:
        Six loads per node, in newtons and newton meters.

    Raises:
        Error: If the load case id is out of range.
    """
    model.check_case(load_case)
    var f = List[Float64](length=model.dof_count(), fill=0)
    for i in range(len(model.nodal_loads)):
        ref load = model.nodal_loads[i]
        if load.load_case == load_case:
            f[6 * load.node.value + load.dof.value] += load.value
    for m in range(len(model.members)):
        var local = member_loads(model, load_case, MemberId(m))
        var t = frame_transformation(_axes(model, m))
        var global_loads = t.transposed().multiply_vector(local)
        var dofs = _member_dofs(model, m)
        for i in range(12):  # pragma: no branch
            f[dofs[i]] += global_loads[i]
    var g = Float64(0)
    for i in range(len(model.gravity)):
        if model.gravity[i].load_case == load_case:
            g += model.gravity[i].acceleration
    for s in range(len(model.shells)):
        var element = model.shell_element(ShellId(s))
        var push = Float64(0)
        for i in range(len(model.pressures)):
            ref load = model.pressures[i]
            if load.load_case == load_case and load.shell.value == s:
                push += load.value
        # A third of -p A n and of -ρ t A g z at each corner.
        var force = element.axes.z * (-push * element.area / 3) + Vec3d(
            0, 0, -element.lumped_mass() * g
        )
        var dofs = _shell_dofs(model, s)
        for c in range(3):  # pragma: no branch
            f[dofs[6 * c]] += force.x
            f[dofs[6 * c + 1]] += force.y
            f[dofs[6 * c + 2]] += force.z
    return f^


def free_equations(model: StructuralModel) -> List[Int]:
    """Number the free degrees of freedom.

    Args:
        model: The model.

    Returns:
        For each degree of freedom, its equation number, or -1 if a
        support fixes it.
    """
    var equation = List[Int](capacity=model.dof_count())
    var count = 0
    for i in range(model.dof_count()):
        if model.fixed[i]:
            equation.append(-1)
        else:
            equation.append(count)
            count += 1
    return equation^


def reduce_matrix(
    a: CsrMatrix, equation: List[Int], size: Int
) raises -> CsrMatrix:
    """Return the rows and columns of the free degrees of freedom.

    Args:
        a: A global matrix, six rows per node.
        equation: The numbering from `free_equations`.
        size: The number of free degrees of freedom.

    Returns:
        The reduced matrix.

    Raises:
        Error: If the numbering does not fit the matrix.
    """
    if len(equation) != a.size:
        raise Error("The numbering must have one entry per matrix row")
    var builder = SparseBuilder(size)
    for i in range(a.size):
        var row = equation[i]
        if row < 0:
            continue
        for p in range(a.row_start[i], a.row_start[i + 1]):
            var col = equation[a.columns[p]]
            if col >= 0:
                builder.add(row, col, a.values[p])
    return builder.build()


def factor_stiffness(k: CsrMatrix) raises -> SkylineFactor:
    """Factor a reduced stiffness and refuse a mechanism.

    Args:
        k: The stiffness of the free degrees of freedom.

    Returns:
        The factor, in reverse Cuthill-McKee order.

    Raises:
        Error: If the stiffness is singular or not positive definite.
            Either way the structure can move without strain.
    """
    try:
        var factor = SkylineFactor(k, reverse_cuthill_mckee(k))
        if not factor.is_positive_definite():
            raise Error("not positive definite")
        return factor^
    except e:
        raise Error(
            "The structure is a mechanism: its stiffness is ",
            e,
            ". Add supports or members.",
        )


struct StaticSolver(Movable):
    """A model with its reduced stiffness factored once."""

    var model: StructuralModel
    var stiffness: CsrMatrix
    # For each degree of freedom, its equation, or -1 if it is fixed.
    var equation: List[Int]
    var free: List[Int]
    var factor: SkylineFactor

    def __init__(out self, var model: StructuralModel) raises:
        """Assemble and factor a model.

        Args:
            model: The model. The solver keeps it.

        Raises:
            Error: If a member or shell cannot form its matrix, or the
                structure is a mechanism.
        """
        var k = assemble_stiffness(model)
        var equation = free_equations(model)
        var free = List[Int]()
        for i in range(len(equation)):
            if equation[i] >= 0:
                free.append(i)
        var reduced = reduce_matrix(k, equation, len(free))
        self.factor = factor_stiffness(reduced)
        self.model = model^
        self.stiffness = k^
        self.equation = equation^
        self.free = free^

    def solve(self, load_case: LoadCaseId) raises -> StaticResult:
        """Solve one load case.

        Args:
            load_case: The load case.

        Returns:
            The displacements, reactions, member end forces and shell
            resultants.

        Raises:
            Error: If the load case id is out of range.
        """
        ref model = self.model
        var f = load_vector(model, load_case)
        var rhs = List[Float64](capacity=len(self.free))
        for i in range(len(self.free)):
            rhs.append(f[self.free[i]])
        var x = self.factor.solve(rhs)
        var u = List[Float64](length=model.dof_count(), fill=0)
        for i in range(len(self.free)):
            u[self.free[i]] = x[i]
        var ku = self.stiffness.multiply(u)
        var reactions = List[Float64](length=model.dof_count(), fill=0)
        for i in range(model.dof_count()):
            if self.equation[i] < 0:
                reactions[i] = ku[i] - f[i]
        var forces = List[MemberForces](capacity=len(model.members))
        for m in range(len(model.members)):
            ref member = model.members[m]
            var axes = _axes(model, m)
            var t = frame_transformation(axes)
            var k = frame_local_stiffness(
                _length(model, m), member.section, member.material
            )
            var dofs = _member_dofs(model, m)
            var ue = List[Float64](capacity=12)
            for i in range(12):  # pragma: no branch
                ue.append(u[dofs[i]])
            var end = k.multiply_vector(t.multiply_vector(ue))
            var equivalent = member_loads(model, load_case, MemberId(m))
            for i in range(12):  # pragma: no branch
                end[i] -= equivalent[i]
            forces.append(
                MemberForces(axes, _end_forces(end, 0), _end_forces(end, 6))
            )
        var resultants = List[ShellResultants](capacity=len(model.shells))
        for s in range(len(model.shells)):
            var dofs = _shell_dofs(model, s)
            var ue = List[Float64](capacity=18)
            for i in range(18):  # pragma: no branch
                ue.append(u[dofs[i]])
            resultants.append(model.shell_element(ShellId(s)).resultants(ue))
        return StaticResult(u^, reactions^, f^, forces^, resultants^)


def solve_static(
    model: StructuralModel, load_case: LoadCaseId
) raises -> StaticResult:
    """Solve one load case of a model.

    Use `StaticSolver` to solve several cases with one factorization.

    Args:
        model: The model.
        load_case: The load case.

    Returns:
        The displacements, reactions, member end forces and shell
        resultants.

    Raises:
        Error: If the structure is a mechanism, an element cannot form its
            matrix, or the load case id is out of range.
    """
    var solver = StaticSolver(model.copy())
    return solver.solve(load_case)
