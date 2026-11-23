# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Time history of a truss whose bars can yield.

The equation of motion is M a + C v + f(u) = λ(t) P. M is the lumped mass
of the nodes. f(u) is the internal force of the bars, with their plastic
states. P is the reference load of the model and λ its factor at a time.
C is Rayleigh damping, a M + b K₀, with K₀ the tangent stiffness at the
start of the motion.

`dynamic_step` takes one step of Newmark's method. The velocity and the
acceleration at the end of the step follow from the displacement there,
so the step solves for the displacement by Newton iteration:

    (K + γ/(β Δt) C + M/(β Δt²)) Δu = λ P - f(u) - C v - M a

with K the tangent stiffness of the trial displacement. The state and
the motion change only when the step converges. See Chopra, "Dynamics of
Structures", 4th edition, section 5.7.

OpenSees does this analysis with its Newmark integrator and its Newton
algorithm. The code is original and shares no source with OpenSees.
"""

from core.ordinal import require_valid
from math.finite import require_finite, require_positive_finite
from extensions.numerics.skyline import SkylineFactor, reverse_cuthill_mckee
from extensions.numerics.sparse import CsrMatrix, SparseBuilder
from extensions.numerics.vector import norm, zeros
from extensions.structure.dynamic import (
    NewmarkMethod,
    RayleighDamping,
    combine,
)
from extensions.structure.nonlinear import (
    NewtonOptions,
    TrussModel,
    TrussState,
    assemble_truss,
    truss_equations,
)
from units.si import Duration64, SECOND


struct TrussMotion(Movable):
    """The rates of a truss at one time, and what its damping needs."""

    # Three per node, in meters per second and per second squared.
    var velocities: List[Float64]
    var accelerations: List[Float64]
    # The time, in seconds.
    var time: Float64
    # The lumped mass and the first tangent stiffness of the free degrees
    # of freedom.
    var mass: CsrMatrix
    var stiffness: CsrMatrix

    def __init__(
        out self,
        var velocities: List[Float64],
        var accelerations: List[Float64],
        var mass: CsrMatrix,
        var stiffness: CsrMatrix,
    ):
        """Hold a motion at time zero. `start_motion` makes these.

        Args:
            velocities: Three per node.
            accelerations: Three per node.
            mass: The mass of the free degrees of freedom.
            stiffness: The first tangent stiffness of the free degrees of
                freedom.
        """
        self.velocities = velocities^
        self.accelerations = accelerations^
        self.time = 0
        self.mass = mass^
        self.stiffness = stiffness^


def _free(
    full: List[Float64], equation: List[Int], size: Int
) raises -> List[Float64]:
    """Return the entries of the free degrees of freedom."""
    var out = zeros(size)
    for i in range(len(equation)):  # pragma: no branch
        if equation[i] >= 0:
            out[equation[i]] = full[i]
    return out^


def start_motion(model: TrussModel, state: TrussState) raises -> TrussMotion:
    """Return the motion of a truss that starts from rest.

    The first acceleration is the unbalanced force of the state over the
    mass. A state in balance starts with no acceleration.

    Args:
        model: The model. Each node with a free translation needs a
            mass.
        state: The state at the start, such as a new `TrussState` or the
            end of a static step.

    Returns:
        The motion at time zero.

    Raises:
        Error: If the state does not fit the model, or a node with a
            free translation has no mass.
    """
    var tangent = assemble_truss(model, state, state.displacements)
    var equation = truss_equations(model)
    var size = tangent.matrix.size
    var builder = SparseBuilder(size)
    for i in range(len(equation)):
        if equation[i] < 0:
            continue
        var mass = model.masses[i // 3]
        if not (mass > 0):
            raise Error("Each node with a free translation needs a mass")
        builder.add(equation[i], equation[i], mass)
    var accelerations = zeros(len(equation))
    for i in range(len(equation)):
        if equation[i] >= 0:
            accelerations[i] = (
                state.load_factor * model.loads[i] - tangent.internal[i]
            ) / model.masses[i // 3]
    return TrussMotion(
        zeros(len(equation)),
        accelerations^,
        builder.build(),
        tangent.matrix.copy(),
    )


def dynamic_step(
    model: TrussModel,
    mut state: TrussState,
    mut motion: TrussMotion,
    load_factor: Float64,
    step: Duration64,
    method: NewmarkMethod,
    damping: RayleighDamping,
    options: NewtonOptions,
) raises:
    """Advance a truss by one time step.

    The state and the motion change only if the step converges.

    Args:
        model: The model.
        state: The state. It must come from this model.
        motion: The motion, from `start_motion` with this model.
        load_factor: The factor of the reference load at the end of the
            step.
        step: The time step. Positive.
        method: The Newmark method. `average_acceleration()` is the
            usual choice.
        damping: The Rayleigh damping. The stiffness factor acts on the
            stiffness at the start of the motion.
        options: The tolerance and the iteration budget of the Newton
            iteration.

    Raises:
        Error: If the load factor is not finite, the step is not positive
            and finite, the method cannot step, the damping is not valid,
            the state or the motion does not fit the model, the effective
            stiffness is singular, or the iteration does not converge.
    """
    require_finite(load_factor, "A load factor must be finite")
    var dt = step.to(SECOND)
    require_positive_finite(dt, "A time step must be positive and finite")
    require_valid(
        method.is_usable(),
        "A Newmark method needs gamma of one half or more and a positive beta",
    )
    require_valid(
        damping.is_valid(), "A damping factor must be zero or more and finite"
    )
    var equation = truss_equations(model)
    if len(motion.velocities) != len(equation):
        raise Error("The motion does not fit the model")
    var size = motion.mass.size
    var gamma = method.gamma
    var beta = method.beta
    var reference = _free(model.loads, equation, size)
    var u0 = _free(state.displacements, equation, size)
    var v0 = _free(motion.velocities, equation, size)
    var a0 = _free(motion.accelerations, equation, size)
    var u = state.displacements.copy()
    # C = a M + b K₀, and the factors of M and of C in the Newton matrix.
    var c_factor = gamma / (beta * dt)
    var m_factor = 1 / (beta * dt * dt) + c_factor * damping.mass_factor
    var k0_factor = c_factor * damping.stiffness_factor
    var damped = combine(motion.stiffness, motion.mass, k0_factor, m_factor)
    for iteration in range(options.iterations + 1):  # pragma: no branch
        var tangent = assemble_truss(model, state, u)
        var now = _free(u, equation, size)
        var v = zeros(size)
        var a = zeros(size)
        for i in range(size):  # pragma: no branch
            var du = now[i] - u0[i]
            v[i] = (
                c_factor * du
                + (1 - gamma / beta) * v0[i]
                + dt * (1 - gamma / (2 * beta)) * a0[i]
            )
            a[i] = (
                du / (beta * dt * dt)
                - v0[i] / (beta * dt)
                - (1 / (2 * beta) - 1) * a0[i]
            )
        var inertia = motion.mass.multiply(a)
        var by_mass = motion.mass.multiply(v)
        var by_stiffness = motion.stiffness.multiply(v)
        var internal = _free(tangent.internal, equation, size)
        var residual = zeros(size)
        for i in range(size):  # pragma: no branch
            residual[i] = (
                load_factor * reference[i]
                - internal[i]
                - damping.mass_factor * by_mass[i]
                - damping.stiffness_factor * by_stiffness[i]
                - inertia[i]
            )
        var scale = (
            abs(load_factor) * norm(reference)
            + norm(tangent.forces)
            + norm(inertia)
        )
        if norm(residual) <= options.tolerance * scale:
            for i in range(len(equation)):  # pragma: no branch
                if equation[i] >= 0:
                    motion.velocities[i] = v[equation[i]]
                    motion.accelerations[i] = a[equation[i]]
            motion.time += dt
            state.displacements = u^
            state.load_factor = load_factor
            state.bars = tangent.states.copy()
            state.forces = tangent.forces.copy()
            state.iterations = iteration
            return
        if iteration == options.iterations:
            break
        var effective = combine(tangent.matrix, damped, 1, 1)
        var change: List[Float64]
        try:
            var factor = SkylineFactor(
                effective, reverse_cuthill_mckee(effective)
            )
            change = factor.solve(residual)
        except:
            raise Error("The effective stiffness of the step is singular")
        for i in range(len(equation)):  # pragma: no branch
            if equation[i] >= 0:
                u[i] += change[equation[i]]
    raise Error("The Newton iteration did not converge within its budget")
