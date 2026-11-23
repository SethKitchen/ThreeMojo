# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Linear buckling and second-order static analysis of frames.

An axial force changes the bending stiffness of a member. Tension adds
stiffness and compression removes it. The change is the geometric
stiffness Kg, which is linear in the axial force. The consistent matrix
of the cubic frame element is that of McGuire, Gallagher and Ziemian,
"Matrix Structural Analysis", 2nd edition, 2000, chapter 9.

`solve_buckling` finds the lowest positive factors λ at which
(K + λ Kg) φ = 0, with Kg from the axial forces of one load case. The
load case times λ buckles the structure. This is the *BUCKLE procedure
of CalculiX and the eigen analysis of a geometric stiffness in OpenSees.

`solve_second_order` solves (K + Kg(u)) u = f by repeated solutions. It
gives the P-Delta amplification of sway and of moments.

The eigenproblem is solved in the shifted form of Bathe, "Finite Element
Procedures", 2nd edition, section 11.2.3: (K + s Kg) φ = γ K φ. The scale
s keeps the left matrix positive definite, and λ = s / (1 - γ). The lowest
γ are the lowest positive λ, so `lowest_modes` finds them with its Sturm
check. The code is original and shares no source with CalculiX or
OpenSees.
"""

from std.math import isfinite
from core.ordinal import require_positive
from math.finite import require_finite, require_positive_tolerance
from extensions.numerics.dense import DenseMatrix
from extensions.numerics.eigen import lowest_modes
from extensions.numerics.skyline import SkylineFactor, reverse_cuthill_mckee
from extensions.numerics.sparse import CsrMatrix, SparseBuilder
from extensions.numerics.vector import norm, zeros
from extensions.structure.dynamic import combine
from extensions.structure.frame import (
    frame_local_stiffness,
    frame_transformation,
    member_axes,
    require_member_length,
)
from extensions.structure.ids import LoadCaseId, MemberId, ShellId
from extensions.structure.model import StructuralModel
from extensions.structure.shell import ShellResultants
from extensions.structure.static import (
    EndForces,
    MemberForces,
    StaticResult,
    assemble_stiffness,
    factor_stiffness,
    free_equations,
    load_vector,
    member_loads,
    reduce_matrix,
)
from units.si import Force64, Length64, METER, Moment64, NEWTON

# The relative change of each eigenvalue at which subspace iteration stops.
comptime _TOLERANCE = 1e-11
comptime _ITERATIONS = 400
# How many power iterations estimate the scale of the geometric stiffness.
comptime _POWER_STEPS = 12
# An eigenvalue γ this close to one or above it has no positive factor.
comptime _NO_BUCKLING = 1e-9


def frame_geometric_stiffness(
    length: Length64, axial: Force64
) raises -> DenseMatrix:
    """Return the 12 by 12 geometric stiffness of a member, locally.

    In each bending plane the terms are N / (30 L) times 36, 3 L, 4 L²
    and -L², for the translations and the rotations of the two ends. The
    axial and torsion terms are zero.

    Args:
        length: The member length.
        axial: The axial force N. Tension is positive.

    Returns:
        The geometric stiffness, in newtons per meter, newtons per radian
        and newton meters per radian.

    Raises:
        Error: If the length is not positive and finite, or the force is
            not finite.
    """
    var l = length.to(METER)
    require_member_length(l)
    var n = axial.to(NEWTON)
    require_finite(n, "An axial force must be finite")
    var kg = DenseMatrix(12, 12)
    var block: List[Float64] = [
        36,
        3 * l,
        -36,
        3 * l,
        3 * l,
        4 * l * l,
        -3 * l,
        -l * l,
        -36,
        -3 * l,
        36,
        -3 * l,
        3 * l,
        -l * l,
        -3 * l,
        4 * l * l,
    ]
    var xy: List[Int] = [1, 5, 7, 11]
    var xz: List[Int] = [2, 4, 8, 10]
    var scale = n / (30 * l)
    for r in range(4):  # pragma: no branch
        for c in range(4):  # pragma: no branch
            var value = scale * block[4 * r + c]
            kg.add(xy[r], xy[c], value)
            # The rotation about y is -dw/dx, so each term that couples a
            # translation to a rotation changes sign in the x-z plane.
            if (r % 2) != (c % 2):
                value = -value
            kg.add(xz[r], xz[c], value)
    return kg^


def member_tensions(forces: List[MemberForces]) -> List[Float64]:
    """Return the axial force of each member from its end forces.

    A member with an axial line load has a force that varies along it.
    The value is the mean of the two ends.

    Args:
        forces: The end forces of each member, from a `StaticResult`.

    Returns:
        One force per member, in newtons. Tension is positive.
    """
    var out = List[Float64](capacity=len(forces))
    for i in range(len(forces)):
        var at_end = forces[i].end.axial.to(NEWTON)
        var at_start = forces[i].start.axial.to(NEWTON)
        out.append((at_end - at_start) / 2)
    return out^


def _length(model: StructuralModel, m: Int) -> Length64:
    """Return a member's length."""
    ref member = model.members[m]
    return Length64(
        model.nodes[member.start.value].distance_to(
            model.nodes[member.end.value]
        )
    )


def _transformation(model: StructuralModel, m: Int) raises -> DenseMatrix:
    """Return a member's transformation from global to local axes."""
    ref member = model.members[m]
    return frame_transformation(
        member_axes(
            model.nodes[member.start.value],
            model.nodes[member.end.value],
            member.reference,
        )
    )


def assemble_geometric_stiffness(
    model: StructuralModel, tensions: List[Float64]
) raises -> CsrMatrix:
    """Return the global geometric stiffness of every member.

    No support is applied. A shell adds nothing: its membrane stress does
    not change its stiffness in this port.

    Args:
        model: The model.
        tensions: The axial force of each member, in newtons. Tension is
            positive. `member_tensions` gives these.

    Returns:
        The geometric stiffness, six rows per node.

    Raises:
        Error: If the list does not have one force per member, or a force
            is not finite.
    """
    if len(tensions) != len(model.members):
        raise Error("The axial forces must have one entry per member")
    var builder = SparseBuilder(model.dof_count())
    for m in range(len(model.members)):
        ref member = model.members[m]
        var t = _transformation(model, m)
        var kg = t.triple_product(
            frame_geometric_stiffness(_length(model, m), Force64(tensions[m]))
        )
        var ends = [member.start.value, member.end.value]
        for i in range(12):  # pragma: no branch
            for j in range(12):  # pragma: no branch
                builder.add(
                    6 * ends[i // 6] + i % 6,
                    6 * ends[j // 6] + j % 6,
                    kg.get(i, j),
                )
    return builder.build()


def is_positive_definite(a: CsrMatrix) -> Bool:
    """Return True if a symmetric matrix is positive definite.

    Args:
        a: The matrix.

    Returns:
        Whether its factorization has only positive pivots. A singular
        matrix is not positive definite.
    """
    try:
        var factor = SkylineFactor(a, reverse_cuthill_mckee(a))
        return factor.is_positive_definite()
    except:
        return False


def stable_scale(k: CsrMatrix, kg: CsrMatrix, start: Float64) raises -> Float64:
    """Return a scale s at which K + s Kg is positive definite.

    The scale is the start value, halved until the sum is positive
    definite. For a positive definite K the search ends.

    Args:
        k: The stiffness. Positive definite.
        kg: The geometric stiffness.
        start: The first scale to try. Positive and finite.

    Returns:
        The scale.

    Raises:
        Error: If the start is not positive and finite, the sizes differ,
            or K is not positive definite.
    """
    if not (start > 0 and isfinite(start)):
        raise Error("A scale must be positive and finite")
    if not is_positive_definite(k):
        raise Error("The stiffness must be positive definite")
    var s = start
    while not is_positive_definite(combine(k, kg, 1, s)):
        s = s / 2
    return s


def dominant_ratio(
    factor: SkylineFactor, kg: CsrMatrix, steps: Int
) raises -> Float64:
    """Estimate the largest size of an eigenvalue of K⁻¹ Kg.

    The estimate is the growth of a vector in the last of several power
    iterations.

    Args:
        factor: The factor of the stiffness K.
        kg: The geometric stiffness.
        steps: How many iterations. One or more.

    Returns:
        The estimate. Zero if the geometric stiffness is zero.

    Raises:
        Error: If the step count is not positive or the sizes differ.
    """
    require_positive(steps, "A power iteration needs one step or more")
    var n = kg.size
    var x = zeros(n)
    for i in range(n):
        # A vector with no symmetry, so that it has a part of each shape.
        x[i] = 1 + Float64((7 * i) % 11) / 11
    var ratio = Float64(0)
    for _ in range(steps):  # pragma: no branch
        var size = norm(x)
        if size == 0:
            return 0
        var y = factor.solve(kg.multiply(x))
        ratio = norm(y) / size
        x = y^
    return ratio


struct BucklingResult(Movable):
    """The lowest buckling factors of a load case and their shapes."""

    # The load case times a factor buckles the structure. Ascending.
    var factors: List[Float64]
    # One per factor: six entries per node. The largest entry is one.
    var shapes: List[List[Float64]]

    def __init__(
        out self, var factors: List[Float64], var shapes: List[List[Float64]]
    ):
        """Hold a result. `solve_buckling` makes these.

        Args:
            factors: The buckling factors, ascending.
            shapes: One shape per factor.
        """
        self.factors = factors^
        self.shapes = shapes^


def solve_buckling(
    model: StructuralModel, load_case: LoadCaseId, count: Int
) raises -> BucklingResult:
    """Return the lowest buckling factors of a load case.

    The axial forces come from a linear static solution of the load case.
    A factor λ means that λ times the load case buckles the structure.
    Only positive factors are returned.

    Args:
        model: The model.
        load_case: The load case.
        count: How many factors. From one to the number of free degrees
            of freedom.

    Returns:
        The factors, ascending, and their shapes.

    Raises:
        Error: If the load case id is out of range, the structure is a
            mechanism, the count is out of range, no member has an axial
            force, the load case has fewer positive factors than the
            count, or the iteration does not converge.
    """
    var equation = free_equations(model)
    var size = 0
    for i in range(len(equation)):
        if equation[i] >= 0:
            size += 1
    if count < 1 or count > size:
        raise Error("The mode count must be from one to the matrix size")
    var k = reduce_matrix(assemble_stiffness(model), equation, size)
    var factor = factor_stiffness(k)
    var first = _solve(model, load_case, k, equation, size)
    var kg = reduce_matrix(
        assemble_geometric_stiffness(
            model, member_tensions(first.member_forces)
        ),
        equation,
        size,
    )
    var ratio = dominant_ratio(factor, kg, _POWER_STEPS)
    if not (ratio > 0):
        raise Error(
            "The load case puts no axial force in a member, so it cannot"
            " buckle the structure"
        )
    var s = stable_scale(k, kg, 0.5 / ratio)
    var modes = lowest_modes(
        combine(k, kg, 1, s), k, count, _TOLERANCE, _ITERATIONS
    )
    var factors = List[Float64](capacity=count)
    var shapes = List[List[Float64]](capacity=count)
    for i in range(count):  # pragma: no branch
        var gamma = modes.values[i]
        if not (gamma < 1 - _NO_BUCKLING):
            raise Error(
                "The load case has fewer positive buckling factors than"
                " the count. Tension does not buckle a member."
            )
        factors.append(s / (1 - gamma))
        var largest = Float64(0)
        for j in range(size):  # pragma: no branch
            largest = max(largest, abs(modes.vectors[i][j]))
        var shape = List[Float64](length=len(equation), fill=0)
        for j in range(len(equation)):  # pragma: no branch
            if equation[j] >= 0:
                shape[j] = modes.vectors[i][equation[j]] / largest
        shapes.append(shape^)
    return BucklingResult(factors^, shapes^)


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


def _recover(
    model: StructuralModel,
    load_case: LoadCaseId,
    u: List[Float64],
    tensions: List[Float64],
) raises -> List[MemberForces]:
    """Return the end forces of each member, with its geometric stiffness."""
    var forces = List[MemberForces](capacity=len(model.members))
    for m in range(len(model.members)):
        ref member = model.members[m]
        var axes = member_axes(
            model.nodes[member.start.value],
            model.nodes[member.end.value],
            member.reference,
        )
        var t = frame_transformation(axes)
        var length = _length(model, m)
        var k = frame_local_stiffness(length, member.section, member.material)
        var kg = frame_geometric_stiffness(length, Force64(tensions[m]))
        var ends = [member.start.value, member.end.value]
        var ue = List[Float64](capacity=12)
        for i in range(12):  # pragma: no branch
            ue.append(u[6 * ends[i // 6] + i % 6])
        var local = t.multiply_vector(ue)
        var end = k.multiply_vector(local)
        var extra = kg.multiply_vector(local)
        var equivalent = member_loads(model, load_case, MemberId(m))
        for i in range(12):  # pragma: no branch
            end[i] += extra[i] - equivalent[i]
        forces.append(
            MemberForces(axes, _end_forces(end, 0), _end_forces(end, 6))
        )
    return forces^


def _solve(
    model: StructuralModel,
    load_case: LoadCaseId,
    stiffness: CsrMatrix,
    equation: List[Int],
    size: Int,
) raises -> StaticResult:
    """Solve a load case with a given reduced stiffness.

    The member end forces are those of the elastic stiffness alone.
    """
    var f = load_vector(model, load_case)
    var rhs = zeros(size)
    for i in range(len(equation)):
        if equation[i] >= 0:
            rhs[equation[i]] = f[i]
    var x = SkylineFactor(stiffness, reverse_cuthill_mckee(stiffness)).solve(
        rhs
    )
    var u = zeros(len(equation))
    for i in range(len(equation)):
        if equation[i] >= 0:
            u[i] = x[equation[i]]
    var none = zeros(len(model.members))
    var forces = _recover(model, load_case, u, none)
    return StaticResult(
        u^,
        zeros(len(equation)),
        f^,
        forces^,
        List[ShellResultants](),
    )


struct SecondOrderOptions(ImplicitlyCopyable):
    """When the second-order iteration stops."""

    # The relative change of the largest displacement at which to stop.
    var tolerance: Float64
    var iterations: Int

    def __init__(out self, tolerance: Float64, iterations: Int) raises:
        """Create the options.

        Args:
            tolerance: The relative change of the largest displacement
                between two solutions at which to stop. Positive.
            iterations: The largest number of solutions with a geometric
                stiffness. One or more.

        Raises:
            Error: If the tolerance is not positive and finite or the
                iteration count is not positive.
        """
        require_positive_tolerance(tolerance)
        require_positive(iterations, "An iteration budget must be one or more")
        self.tolerance = tolerance
        self.iterations = iterations


def default_second_order() raises -> SecondOrderOptions:
    """Return a tolerance of 1e-10 and a budget of 50 solutions.

    Returns:
        The options.

    Raises:
        Error: Never.
    """
    return SecondOrderOptions(1e-10, 50)


def solve_second_order(
    model: StructuralModel, load_case: LoadCaseId, options: SecondOrderOptions
) raises -> StaticResult:
    """Solve one load case with the geometric stiffness of its own forces.

    The first solution is linear. Each later solution uses the axial
    forces of the solution before it, until the displacements stop
    changing. The result holds the P-Delta effect of sway and of member
    curvature. The displacements stay small: the kinematics are linear.

    Args:
        model: The model.
        load_case: The load case.
        options: The tolerance and the iteration budget.

    Returns:
        The displacements, reactions, member end forces and shell
        resultants.

    Raises:
        Error: If the load case id is out of range, the structure is a
            mechanism, the load case is at or above its buckling load, or
            the iteration does not converge within the budget.
    """
    var equation = free_equations(model)
    var size = 0
    for i in range(len(equation)):
        if equation[i] >= 0:
            size += 1
    var full = assemble_stiffness(model)
    var k = reduce_matrix(full, equation, size)
    _ = factor_stiffness(k)
    var previous = _solve(model, load_case, k, equation, size)
    var tensions = member_tensions(previous.member_forces)
    for _ in range(options.iterations):  # pragma: no branch
        var full_kg = assemble_geometric_stiffness(model, tensions)
        var total = combine(k, reduce_matrix(full_kg, equation, size), 1, 1)
        if not is_positive_definite(total):
            raise Error(
                "The load case is at or above the buckling load of the"
                " structure"
            )
        var next = _solve(model, load_case, total, equation, size)
        var forces = _recover(model, load_case, next.displacements, tensions)
        var change = Float64(0)
        var largest = Float64(0)
        for i in range(len(equation)):
            var now = next.displacements[i]
            change = max(change, abs(now - previous.displacements[i]))
            largest = max(largest, abs(now))
        tensions = member_tensions(forces)
        if change <= options.tolerance * largest:
            var u = next.displacements.copy()
            var applied = next.loads.copy()
            var ku = combine(full, full_kg, 1, 1).multiply(u)
            var reactions = zeros(len(equation))
            for i in range(len(equation)):
                if equation[i] < 0:
                    reactions[i] = ku[i] - applied[i]
            var resultants = List[ShellResultants](capacity=len(model.shells))
            for s in range(len(model.shells)):
                ref shell = model.shells[s]
                var corners = [shell.a.value, shell.b.value, shell.c.value]
                var ue = List[Float64](capacity=18)
                for i in range(18):  # pragma: no branch
                    ue.append(u[6 * corners[i // 6] + i % 6])
                resultants.append(
                    model.shell_element(ShellId(s)).resultants(ue)
                )
            return StaticResult(u^, reactions^, applied^, forces^, resultants^)
        previous = next^
    raise Error("The second-order iteration did not converge")
