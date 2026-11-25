# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Trusses of bars that yield, followed step by step.

A bar has a bilinear law: it is elastic up to its yield stress and then
follows a smaller modulus. The hardening is kinematic, so a bar that has
yielded in tension yields sooner in compression. A hardening ratio of
zero gives an elastic-perfectly plastic bar. The stress comes from the
return map of Simo and Hughes, "Computational Inelasticity", 1998,
chapter 1.

A `TrussModel` holds nodes, supports, bars and a reference load. A
`TrussState` holds the displacements, the load factor λ and the plastic
state of each bar. `load_step` raises λ by a given amount. It cannot pass
a collapse load, where no displacement carries more load.
`displacement_step` moves one degree of freedom by a given amount and
finds λ, so it follows a path through a plateau. Both use Newton
iteration with the consistent tangent, and both keep the state when they
converge.

The parts follow the OpenSees objects: a uniaxial material with a
committed state, a truss element, the Newton algorithm, and the
LoadControl and DisplacementControl integrators. The displacements are
small, unless `set_corotational` asks for the exact geometry of the
OpenSees corotational truss. The code is original and shares no source
with OpenSees.
"""

from std.math import isfinite
from core.ordinal import require_positive
from math.finite import (
    require_finite,
    require_finite_group,
    require_positive_finite,
    require_positive_tolerance,
)
from extensions.numerics.skyline import SkylineFactor, reverse_cuthill_mckee
from extensions.numerics.sparse import CsrMatrix, SparseBuilder
from extensions.numerics.vector import norm, zeros
from extensions.structure.ids import MemberId, NodeId
from extensions.structure.kinds import Dof
from generators.utils import Vec3d
from units.si import (
    Area64,
    Force64,
    KILOGRAM,
    Length64,
    METER,
    Mass64,
    NEWTON,
    PASCAL,
    Pressure64,
    SQUARE_METER,
)


struct SteelLaw(ImplicitlyCopyable):
    """A bilinear stress-strain law with kinematic hardening."""

    # Young's modulus, in pascals.
    var modulus: Float64
    # The first yield stress, in pascals.
    var yield_stress: Float64
    # The modulus after yield over the modulus before it.
    var hardening: Float64

    def __init__(
        out self,
        modulus: Pressure64,
        yield_stress: Pressure64,
        hardening: Float64,
    ) raises:
        """Create a law.

        Args:
            modulus: Young's modulus. Positive.
            yield_stress: The first yield stress. Positive.
            hardening: The modulus after yield over Young's modulus. From
                zero, which is perfectly plastic, to below one.

        Raises:
            Error: If the modulus or the yield stress is not positive and
                finite, or the hardening is not from zero to below one.
        """
        var e = modulus.to(PASCAL)
        var fy = yield_stress.to(PASCAL)
        require_positive_finite(e, "A modulus must be positive and finite")
        require_positive_finite(
            fy, "A yield stress must be positive and finite"
        )
        if not (hardening >= 0 and hardening < 1):
            raise Error("A hardening ratio must be from zero to below one")
        self.modulus = e
        self.yield_stress = fy
        self.hardening = hardening


@fieldwise_init
struct BarState(ImplicitlyCopyable):
    """The plastic state of a bar."""

    # The plastic strain.
    var plastic_strain: Float64
    # The center of the elastic range, in pascals.
    var back_stress: Float64


@fieldwise_init
struct BarResponse(ImplicitlyCopyable):
    """The stress of a bar at a strain, its tangent and its new state."""

    # The stress, in pascals.
    var stress: Float64
    # The derivative of the stress by the strain, in pascals.
    var tangent: Float64
    var state: BarState


def bar_response(
    law: SteelLaw, state: BarState, strain: Float64
) -> BarResponse:
    """Return the stress of a bar that is taken from a state to a strain.

    The trial stress is elastic. If it leaves the elastic range, whose
    center is the back stress, the plastic strain and the back stress
    move so that it returns to the edge of the range.

    Args:
        law: The law of the bar.
        state: The state at the start of the step.
        strain: The total strain at the end of the step.

    Returns:
        The stress, the consistent tangent and the state at the end.
    """
    var e = law.modulus
    # The kinematic modulus H gives a tangent of E H / (E + H) = b E.
    var h = law.hardening * e / (1 - law.hardening)
    var trial = e * (strain - state.plastic_strain)
    var over = abs(trial - state.back_stress) - law.yield_stress
    if over <= 0:
        return BarResponse(trial, e, state)
    var direction = Float64(1)
    if trial < state.back_stress:
        direction = -1
    var slip = over / (e + h)
    var next = BarState(
        state.plastic_strain + slip * direction,
        state.back_stress + h * slip * direction,
    )
    return BarResponse(trial - e * slip * direction, law.hardening * e, next)


struct Bar(ImplicitlyCopyable):
    """A bar between two nodes that carries an axial force only."""

    var start: NodeId
    var end: NodeId
    # The area of the cross-section, in square meters.
    var area: Float64
    var law: SteelLaw

    def __init__(
        out self, start: NodeId, end: NodeId, area: Float64, law: SteelLaw
    ):
        """Hold a bar. `TrussModel.add_bar` makes these.

        Args:
            start: The start node.
            end: The end node.
            area: The area, in square meters.
            law: The law.
        """
        self.start = start
        self.end = end
        self.area = area
        self.law = law


struct TrussModel(Copyable, Movable):
    """Nodes, supports, bars and a reference load.

    Each node has three degrees of freedom, the translations `UX`, `UY`
    and `UZ`. Entry `3 n + d` of a vector is degree of freedom `d` of
    node `n`.
    """

    var nodes: List[Vec3d]
    # Three entries per node: True where the translation is held.
    var fixed: List[Bool]
    var bars: List[Bar]
    # The reference load, three entries per node, in newtons. The applied
    # load is the load factor times it.
    var loads: List[Float64]
    # True if each bar follows its current length and axis.
    var corotational: Bool
    # The lumped mass of each node, in kilograms. Only a time history
    # uses it.
    var masses: List[Float64]

    def __init__(out self):
        """Create an empty model with small displacements."""
        self.nodes = List[Vec3d]()
        self.fixed = List[Bool]()
        self.bars = List[Bar]()
        self.loads = List[Float64]()
        self.corotational = False
        self.masses = List[Float64]()

    def set_corotational(mut self, corotational: Bool):
        """Choose the geometry of the bars.

        With small displacements a bar takes its strain along its first
        axis. A corotational bar takes its strain from its current
        length, and it pushes along its current axis. So it is exact for
        any displacement and any rotation. Its tangent gets a geometric
        part, which lets a shallow truss snap through.

        Args:
            corotational: True for the exact geometry. False for small
                displacements, which is the start value.
        """
        self.corotational = corotational

    def check_node(self, id: NodeId) raises:
        """Refuse a node id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last node.
        """
        if not id.is_valid() or id.value >= len(self.nodes):
            raise Error("A node id is out of range")

    def add_node(mut self, at: Vec3d) raises -> NodeId:
        """Add a free node.

        Args:
            at: Its position, in meters.

        Returns:
            The new node.

        Raises:
            Error: If the position is not finite.
        """
        require_finite_group(at.is_finite(), "A node position must be finite")
        self.nodes.append(at)
        for _ in range(3):
            self.fixed.append(False)
            self.loads.append(0)
        self.masses.append(0)
        return NodeId(len(self.nodes) - 1)

    def add_mass(mut self, node: NodeId, mass: Mass64) raises:
        """Add a lumped mass at a node, for a time history.

        The mass acts on the three translations. A static step does not
        use it.

        Args:
            node: The node.
            mass: The mass. Zero or more.

        Raises:
            Error: If the node id is out of range or the mass is negative
                or not finite.
        """
        self.check_node(node)
        var m = mass.to(KILOGRAM)
        if not (m >= 0 and isfinite(m)):
            raise Error("A mass must be zero or more and finite")
        self.masses[node.value] += m

    def _entry(self, node: NodeId, dof: Dof) raises -> Int:
        """Return the vector entry of a translation of a node."""
        self.check_node(node)
        if not dof.is_translation():
            raise Error("A truss node has the translations UX, UY and UZ only")
        return 3 * node.value + dof.value

    def add_support(mut self, node: NodeId, dofs: List[Dof]) raises:
        """Hold some translations of a node at zero.

        Args:
            node: The node.
            dofs: The translations to hold.

        Raises:
            Error: If the node id is out of range or a degree of freedom
                is not a translation.
        """
        for i in range(len(dofs)):
            _ = self._entry(node, dofs[i])
        for i in range(len(dofs)):
            self.fixed[3 * node.value + dofs[i].value] = True

    def add_bar(
        mut self, start: NodeId, end: NodeId, area: Area64, law: SteelLaw
    ) raises -> MemberId:
        """Add a bar.

        Args:
            start: The start node.
            end: The end node.
            area: The area of the cross-section. Positive.
            law: The stress-strain law.

        Returns:
            The new bar.

        Raises:
            Error: If a node id is out of range, the ends are at one
                point, or the area is not positive and finite.
        """
        self.check_node(start)
        self.check_node(end)
        var length = self.nodes[start.value].distance_to(self.nodes[end.value])
        if not (length > 0):
            raise Error("A bar's ends must differ")
        var a = area.to(SQUARE_METER)
        require_positive_finite(a, "A bar area must be positive and finite")
        self.bars.append(Bar(start, end, a, law))
        return MemberId(len(self.bars) - 1)

    def add_load(mut self, node: NodeId, dof: Dof, force: Force64) raises:
        """Add a force to the reference load.

        Args:
            node: The node.
            dof: `UX`, `UY` or `UZ`.
            force: The force at a load factor of one.

        Raises:
            Error: If the node id is out of range, the degree of freedom
                is not a translation, or the force is not finite.
        """
        var entry = self._entry(node, dof)
        var f = force.to(NEWTON)
        require_finite(f, "A load must be finite")
        self.loads[entry] += f


struct TrussState(Movable):
    """The displacements, the load factor and the bar states of a truss."""

    # Three per node, in meters.
    var displacements: List[Float64]
    # The applied load over the reference load.
    var load_factor: Float64
    # The committed plastic state of each bar.
    var bars: List[BarState]
    # The axial force of each bar, in newtons. Tension is positive.
    var forces: List[Float64]
    # The Newton iterations of the last step.
    var iterations: Int

    def __init__(out self, model: TrussModel):
        """Create the state of a model with no load and no plastic strain.

        Args:
            model: The model.
        """
        self.displacements = List[Float64](length=3 * len(model.nodes), fill=0)
        self.load_factor = 0
        self.bars = List[BarState](length=len(model.bars), fill=BarState(0, 0))
        self.forces = List[Float64](length=len(model.bars), fill=0)
        self.iterations = 0

    def translation(self, node: NodeId, dof: Dof) raises -> Length64:
        """Return a displacement of a node.

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
            raise Error("A truss node has the translations UX, UY and UZ only")
        if not node.is_valid() or 3 * node.value >= len(self.displacements):
            raise Error("A node id is out of range")
        return Length64(self.displacements[3 * node.value + dof.value])

    def bar_force(self, bar: MemberId) raises -> Force64:
        """Return the axial force of a bar.

        Args:
            bar: The bar.

        Returns:
            The force. Tension is positive.

        Raises:
            Error: If the bar id is out of range.
        """
        if not bar.is_valid() or bar.value >= len(self.forces):
            raise Error("A bar id is out of range")
        return Force64(self.forces[bar.value])

    def has_yielded(self, bar: MemberId) raises -> Bool:
        """Return True if a bar has a plastic strain.

        Args:
            bar: The bar.

        Returns:
            Whether the bar has yielded in a step up to now.

        Raises:
            Error: If the bar id is out of range.
        """
        _ = self.bar_force(bar)
        return self.bars[bar.value].plastic_strain != 0


struct NewtonOptions(ImplicitlyCopyable):
    """When the Newton iteration of a step stops."""

    # The norm of the unbalanced force, over the norm of the applied load
    # plus the norm of the bar forces, at which to stop.
    var tolerance: Float64
    var iterations: Int

    def __init__(out self, tolerance: Float64, iterations: Int) raises:
        """Create the options.

        Args:
            tolerance: The norm of the unbalanced force, over the norm of
                the applied load plus the norm of the bar forces, at
                which a step has converged. Positive.
            iterations: The largest number of iterations of a step. One
                or more.

        Raises:
            Error: If the tolerance is not positive and finite or the
                iteration count is not positive.
        """
        require_positive_tolerance(tolerance)
        require_positive(iterations, "An iteration budget must be one or more")
        self.tolerance = tolerance
        self.iterations = iterations


def default_newton() raises -> NewtonOptions:
    """Return a tolerance of 1e-10 and a budget of 25 iterations.

    Returns:
        The options.

    Raises:
        Error: Never.
    """
    return NewtonOptions(1e-10, 25)


struct TrussTangent(Movable):
    """The response of every bar at trial displacements."""

    # The internal force of each degree of freedom, three per node, in
    # newtons.
    var internal: List[Float64]
    # The state of each bar at the trial displacements.
    var states: List[BarState]
    # The axial force of each bar, in newtons.
    var forces: List[Float64]
    # The tangent stiffness of the free degrees of freedom.
    var matrix: CsrMatrix

    def __init__(
        out self,
        var internal: List[Float64],
        var states: List[BarState],
        var forces: List[Float64],
        var matrix: CsrMatrix,
    ):
        """Hold a tangent. `assemble_truss` makes these.

        Args:
            internal: Three internal forces per node.
            states: One state per bar.
            forces: One axial force per bar.
            matrix: The tangent of the free degrees of freedom.
        """
        self.internal = internal^
        self.states = states^
        self.forces = forces^
        self.matrix = matrix^


struct _Trial(Movable):
    """A tangent with its matrix factored."""

    var internal: List[Float64]
    var states: List[BarState]
    var forces: List[Float64]
    var factor: SkylineFactor

    def __init__(
        out self,
        var internal: List[Float64],
        var states: List[BarState],
        var forces: List[Float64],
        var factor: SkylineFactor,
    ):
        """Hold a trial."""
        self.internal = internal^
        self.states = states^
        self.forces = forces^
        self.factor = factor^


def truss_equations(model: TrussModel) -> List[Int]:
    """Number the free degrees of freedom of a truss.

    Args:
        model: The model.

    Returns:
        For each degree of freedom, three per node, its equation number,
        or -1 if a support holds it.
    """
    var equation = List[Int](capacity=len(model.fixed))
    var count = 0
    for i in range(len(model.fixed)):
        if model.fixed[i]:
            equation.append(-1)
        else:
            equation.append(count)
            count += 1
    return equation^


def assemble_truss(
    model: TrussModel, state: TrussState, u: List[Float64]
) raises -> TrussTangent:
    """Return the internal forces and the tangent of a truss at trial
    displacements.

    Args:
        model: The model.
        state: The committed state. Each bar steps from its state here to
            its strain at the trial displacements.
        u: The trial displacements, three per node, in meters.

    Returns:
        The internal forces, the bar states, the bar forces and the
        tangent stiffness of the free degrees of freedom.

    Raises:
        Error: If the state or the displacements do not fit the model, or
            a value is not finite.
    """
    _check_state(model, state)
    if len(u) != 3 * len(model.nodes):
        raise Error("The displacements do not fit the model")
    var equation = truss_equations(model)
    var size = 0
    for i in range(len(equation)):
        if equation[i] >= 0:
            size += 1
    var internal = zeros(len(u))
    var states = List[BarState](capacity=len(model.bars))
    var forces = zeros(len(model.bars))
    var builder = SparseBuilder(size)
    for b in range(len(model.bars)):
        ref bar = model.bars[b]
        var axis = model.nodes[bar.end.value] - model.nodes[bar.start.value]
        var length = axis.length()
        var s = 3 * bar.start.value
        var e = 3 * bar.end.value
        var n = axis * (1 / length)
        var current = length
        var stretch: Float64
        if model.corotational:
            var moved = Vec3d(
                axis.x + u[e] - u[s],
                axis.y + u[e + 1] - u[s + 1],
                axis.z + u[e + 2] - u[s + 2],
            )
            current = moved.length()
            n = moved * (1 / current)
            stretch = current - length
        else:
            stretch = (
                n.x * (u[e] - u[s])
                + n.y * (u[e + 1] - u[s + 1])
                + n.z * (u[e + 2] - u[s + 2])
            )
        var cosines = [n.x, n.y, n.z]
        var response = bar_response(bar.law, state.bars[b], stretch / length)
        var force = response.stress * bar.area
        forces[b] = force
        states.append(response.state)
        var stiffness = response.tangent * bar.area / length
        # The geometric part: a bar under a force resists a turn.
        var geometric = Float64(0)
        if model.corotational:
            geometric = force / current
        var entries = [s, s + 1, s + 2, e, e + 1, e + 2]
        for i in range(6):
            var end_sign = Float64(1)
            if i < 3:
                end_sign = -1
            internal[entries[i]] += force * end_sign * cosines[i % 3]
            var row = equation[entries[i]]
            if row < 0:
                continue
            for j in range(6):
                var column = equation[entries[j]]
                if column < 0:
                    continue
                var along = cosines[i % 3] * cosines[j % 3]
                var value = (stiffness - geometric) * along
                if i % 3 == j % 3:
                    value += geometric
                if (i < 3) != (j < 3):
                    value = -value
                builder.add(row, column, value)
    return TrussTangent(internal^, states^, forces^, builder.build())


def _trial(
    model: TrussModel, state: TrussState, u: List[Float64]
) raises -> _Trial:
    """Return the internal forces and the factored tangent at u."""
    var tangent = assemble_truss(model, state, u)
    try:
        # The tangent can be indefinite past a limit point of a
        # corotational truss. The factorization takes that. It refuses
        # only a zero pivot.
        var factor = SkylineFactor(
            tangent.matrix, reverse_cuthill_mckee(tangent.matrix)
        )
        return _Trial(
            tangent.internal.copy(),
            tangent.states.copy(),
            tangent.forces.copy(),
            factor^,
        )
    except:
        raise Error(
            "The truss cannot carry more load: its tangent stiffness is"
            " singular. It is a mechanism, or it is at its collapse load."
        )


def _reduce(
    full: List[Float64], equation: List[Int], size: Int
) raises -> List[Float64]:
    """Return the entries of the free degrees of freedom."""
    var out = zeros(size)
    for i in range(len(equation)):
        if equation[i] >= 0:
            out[equation[i]] = full[i]
    return out^


def _advance(
    model: TrussModel,
    mut state: TrussState,
    factor_change: Float64,
    entry: Int,
    step: Float64,
    options: NewtonOptions,
) raises:
    """Take one step by load control or by displacement control.

    With `entry` below zero the load factor rises by `factor_change`.
    Otherwise the degree of freedom `entry` moves by `step`, and the load
    factor is an unknown.
    """
    var equation = truss_equations(model)
    var size = 0
    for i in range(len(equation)):
        if equation[i] >= 0:
            size += 1
    var reference = _reduce(model.loads, equation, size)
    var scale = norm(reference)
    if not (scale > 0):
        raise Error("A truss needs a load on a free degree of freedom")
    var u = state.displacements.copy()
    var factor = state.load_factor + factor_change
    var target = Float64(0)
    if entry >= 0:
        target = u[entry] + step
    for iteration in range(options.iterations + 1):  # pragma: no branch
        var trial = _trial(model, state, u)
        var residual = _reduce(trial.internal, equation, size)
        for i in range(size):  # pragma: no branch
            residual[i] = factor * reference[i] - residual[i]
        var on_target = True
        if entry >= 0:
            on_target = abs(u[entry] - target) <= options.tolerance * abs(step)
        # The forces in balance: the applied load and the bar forces.
        var size_of_forces = abs(factor) * scale + norm(trial.forces)
        if on_target and norm(residual) <= options.tolerance * size_of_forces:
            state.displacements = u^
            state.load_factor = factor
            state.bars = trial.states.copy()
            state.forces = trial.forces.copy()
            state.iterations = iteration
            return
        if iteration == options.iterations:
            break
        var change = trial.factor.solve(residual)
        if entry >= 0:
            # u_c + a_c + δλ b_c = target, with K a = R and K b = P.
            var control = equation[entry]
            var by_load = trial.factor.solve(reference)
            if by_load[control] == 0:
                raise Error(
                    "The load does not move the controlled degree of freedom"
                )
            var factor_step = (target - u[entry] - change[control]) / by_load[
                control
            ]
            factor += factor_step
            for i in range(size):  # pragma: no branch
                change[i] += factor_step * by_load[i]
        for i in range(len(equation)):  # pragma: no branch
            if equation[i] >= 0:
                u[i] += change[equation[i]]
    raise Error("The Newton iteration did not converge within its budget")


def load_step(
    model: TrussModel,
    mut state: TrussState,
    factor_change: Float64,
    options: NewtonOptions,
) raises:
    """Change the load factor by an amount and find the new state.

    The state changes only if the step converges.

    Args:
        model: The model.
        state: The state. It must come from this model.
        factor_change: The change of the load factor. A negative change
            unloads.
        options: The tolerance and the iteration budget.

    Raises:
        Error: If the change is not finite, the state does not fit the
            model, no free degree of freedom has a load, the tangent
            stiffness is singular, or the iteration does not converge. A
            truss at its collapse load has a singular tangent stiffness.
    """
    require_finite(factor_change, "A load factor change must be finite")
    _check_state(model, state)
    _advance(model, state, factor_change, -1, 0, options)


def displacement_step(
    model: TrussModel,
    mut state: TrussState,
    node: NodeId,
    dof: Dof,
    change: Length64,
    options: NewtonOptions,
) raises:
    """Move one degree of freedom by an amount and find the load factor.

    The state changes only if the step converges.

    Args:
        model: The model.
        state: The state. It must come from this model.
        node: The controlled node.
        dof: The controlled translation. It must be free.
        change: The change of its displacement. Not zero.
        options: The tolerance and the iteration budget.

    Raises:
        Error: If the node id is out of range, the degree of freedom is
            not a free translation, the change is zero or not finite, the
            state does not fit the model, no free degree of freedom has a
            load, the load does not move the controlled degree of
            freedom, the tangent stiffness is singular, or the iteration
            does not converge.
    """
    model.check_node(node)
    if not dof.is_translation():
        raise Error("A truss node has the translations UX, UY and UZ only")
    var entry = 3 * node.value + dof.value
    if model.fixed[entry]:
        raise Error("The controlled degree of freedom must be free")
    var step = change.to(METER)
    if not (isfinite(step) and step != 0):
        raise Error("A displacement step must be finite and not zero")
    _check_state(model, state)
    _advance(model, state, 0, entry, step, options)


def _check_state(model: TrussModel, state: TrussState) raises:
    """Refuse a state whose sizes are not those of the model."""
    if len(state.displacements) != 3 * len(model.nodes):
        raise Error("The state does not fit the model")
    if len(state.bars) != len(model.bars):
        raise Error("The state does not fit the model")
