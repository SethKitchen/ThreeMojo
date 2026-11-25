# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Linear time-history analysis of a structural model by Newmark's method.

The equation of motion is M a + C v + K u = s f(t). The vector s is a
fixed load shape and f(t) is a `TimeSeries`. `solve_load_history` takes
the shape from a load case. `solve_ground_motion` takes it from a ground
acceleration: the shape is -M r, with r the rigid motion along one global
axis, and the response is relative to the ground.

The damping is Rayleigh damping, C = a M + b K. The integrator is the
Newmark family of Newmark, "A method of computation for structural
dynamics", 1959, in the form of Chopra, "Dynamics of Structures", 4th
edition, table 5.4.2. The effective stiffness is factored once, so each
step costs one forward and one back substitution.

The analysis classes follow the OpenSees model of a load pattern with a
time series, a Rayleigh damping command and a Newmark integrator. The
code is original and shares no source with OpenSees.
"""

from std.math import isfinite, pi
from core.ordinal import require_positive
from math.finite import require_finite, require_non_negative_finite
from extensions.numerics.skyline import SkylineFactor, reverse_cuthill_mckee
from extensions.numerics.sparse import CsrMatrix, SparseBuilder
from extensions.numerics.vector import zeros
from extensions.structure.ids import LoadCaseId, NodeId
from extensions.structure.kinds import Dof
from extensions.structure.modal import assemble_mass
from extensions.structure.model import StructuralModel
from extensions.structure.static import (
    assemble_stiffness,
    factor_stiffness,
    free_equations,
    load_vector,
    reduce_matrix,
)
from units.si import (
    Acceleration64,
    Duration64,
    Frequency64,
    Length64,
    METER_PER_SECOND_SQUARED,
    PER_SECOND,
    SECOND,
)

# The largest number of steps that one analysis stores.
comptime MAX_HISTORY_STEPS = 1048576


@fieldwise_init
struct NewmarkMethod(ImplicitlyCopyable):
    """The two parameters of a Newmark integrator."""

    # The velocity parameter γ. One half gives no numerical damping.
    var gamma: Float64
    # The displacement parameter β.
    var beta: Float64

    def is_valid(self) -> Bool:
        """Return True if the method is stable for every time step.

        Returns:
            Whether γ is at least one half, β is at least γ / 2 and both
            are finite.
        """
        if not isfinite(self.gamma) or not isfinite(self.beta):
            return False
        return self.gamma >= 0.5 and 2 * self.beta >= self.gamma

    def is_usable(self) -> Bool:
        """Return True if the method can step at all.

        The linear acceleration method is usable but not valid: it is
        stable only for a step below 0.551 of the shortest period.

        Returns:
            Whether γ is at least one half, β is positive and both are
            finite.
        """
        if not isfinite(self.gamma) or not isfinite(self.beta):
            return False
        return self.gamma >= 0.5 and self.beta > 0


def average_acceleration() -> NewmarkMethod:
    """Return the constant average acceleration method.

    Returns:
        γ = 1/2 and β = 1/4. It is stable for every step and keeps the
        energy of an undamped free vibration.
    """
    return NewmarkMethod(0.5, 0.25)


def linear_acceleration() -> NewmarkMethod:
    """Return the linear acceleration method.

    Returns:
        γ = 1/2 and β = 1/6. It is more accurate than the average
        acceleration method, but it is stable only for a step below 0.551
        of the shortest period of the model.
    """
    return NewmarkMethod(0.5, 1.0 / 6.0)


@fieldwise_init
struct RayleighDamping(ImplicitlyCopyable):
    """The factors of the damping matrix C = a M + b K."""

    # The mass factor a, per second.
    var mass_factor: Float64
    # The stiffness factor b, in seconds.
    var stiffness_factor: Float64

    def is_valid(self) -> Bool:
        """Return True if both factors are zero or more and finite.

        Returns:
            Whether the damping cannot add energy.
        """
        if not isfinite(self.mass_factor):
            return False
        if not isfinite(self.stiffness_factor):
            return False
        return self.mass_factor >= 0 and self.stiffness_factor >= 0


def no_damping() -> RayleighDamping:
    """Return a damping of zero.

    Returns:
        Both factors zero.
    """
    return RayleighDamping(0, 0)


def rayleigh_damping(
    ratio: Float64, first: Frequency64, second: Frequency64
) raises -> RayleighDamping:
    """Return the factors that give one damping ratio at two frequencies.

    With ω = 2π f, the factors are a = 2 ζ ω₁ ω₂ / (ω₁ + ω₂) and
    b = 2 ζ / (ω₁ + ω₂). Between the two frequencies the ratio is lower.
    Outside them it is higher.

    Args:
        ratio: The damping ratio ζ, as a fraction of critical. Zero or
            more.
        first: The first frequency, in cycles per time.
        second: The second frequency, in cycles per time.

    Returns:
        The factors.

    Raises:
        Error: If the ratio is negative or not finite, or a frequency is
            not positive and finite.
    """
    require_non_negative_finite(
        ratio, "A damping ratio must be zero or more and finite"
    )
    var w1 = 2 * pi * first.to(PER_SECOND)
    var w2 = 2 * pi * second.to(PER_SECOND)
    if not (w1 > 0 and isfinite(w1)):
        raise Error("A damping frequency must be positive and finite")
    if not (w2 > 0 and isfinite(w2)):
        raise Error("A damping frequency must be positive and finite")
    return RayleighDamping(
        2 * ratio * w1 * w2 / (w1 + w2), 2 * ratio / (w1 + w2)
    )


struct TimeSeries(Copyable, Movable):
    """Factors at equal time intervals, starting at time zero.

    Between two values the factor varies linearly. After the last value it
    is zero, as in the OpenSees `Path` series.
    """

    # The interval between two values, in seconds.
    var interval: Float64
    var values: List[Float64]

    def __init__(
        out self, interval: Duration64, var values: List[Float64]
    ) raises:
        """Create a series.

        Args:
            interval: The time between two values. Positive.
            values: The factors. At least one.

        Raises:
            Error: If the interval is not positive and finite, there is no
                value, or a value is not finite.
        """
        var dt = interval.to(SECOND)
        if not (dt > 0 and isfinite(dt)):
            raise Error("A series interval must be positive and finite")
        if len(values) == 0:
            raise Error("A series must have at least one value")
        for i in range(len(values)):  # pragma: no branch
            require_finite(values[i], "A series value must be finite")
        self.interval = dt
        self.values = values^

    def at(self, time: Float64) -> Float64:
        """Return the factor at a time.

        Args:
            time: The time, in seconds.

        Returns:
            The interpolated factor, or zero before time zero and after
            the last value.
        """
        if not (time >= 0):
            return 0
        var position = time / self.interval
        var last = len(self.values) - 1
        if not (position <= Float64(last)):
            return 0
        var i = Int(position)
        if i == last:
            return self.values[last]
        var t = position - Float64(i)
        return self.values[i] + t * (self.values[i + 1] - self.values[i])


def constant_series(duration: Duration64) raises -> TimeSeries:
    """Return a series that is one from time zero to a duration.

    It makes a load case a step load.

    Args:
        duration: The time at which the series ends. Positive.

    Returns:
        A series with the two values one and one.

    Raises:
        Error: If the duration is not positive and finite.
    """
    return TimeSeries(duration, [1.0, 1.0])


struct GroundMotion(Copyable, Movable):
    """A ground acceleration along one global axis."""

    var dof: Dof
    var series: TimeSeries
    # The acceleration of a series value of one, in meters per second
    # squared.
    var scale: Float64

    def __init__(
        out self, dof: Dof, var series: TimeSeries, scale: Acceleration64
    ) raises:
        """Create a ground motion.

        Args:
            dof: `UX`, `UY` or `UZ`.
            series: The record. Each value times the scale is an
                acceleration of the ground.
            scale: The acceleration of a series value of one. For a record
                in units of g it is 9.80665 meters per second squared.

        Raises:
            Error: If the degree of freedom is not a translation or the
                scale is not finite.
        """
        if not dof.is_translation():
            raise Error("A ground motion must act along a translation")
        var s = scale.to(METER_PER_SECOND_SQUARED)
        require_finite(s, "A ground motion scale must be finite")
        self.dof = dof
        self.series = series^
        self.scale = s


struct HistoryOptions(Copyable, Movable):
    """The time step, the step count, the integrator and the damping."""

    # The time step, in seconds.
    var step: Float64
    var steps: Int
    var method: NewmarkMethod
    var damping: RayleighDamping

    def __init__(
        out self,
        step: Duration64,
        steps: Int,
        method: NewmarkMethod,
        damping: RayleighDamping,
    ) raises:
        """Create the options of a time-history analysis.

        Args:
            step: The time step. Positive.
            steps: How many steps. From 1 to 1048576.
            method: The integrator. `average_acceleration()` is the usual
                choice.
            damping: The Rayleigh damping.

        Raises:
            Error: If the step is not positive and finite, the step count
                is out of range, the method cannot step or the damping is
                not valid.
        """
        var dt = step.to(SECOND)
        if not (dt > 0 and isfinite(dt)):
            raise Error("A time step must be positive and finite")
        require_positive(steps, "A step count must be positive")
        if steps > MAX_HISTORY_STEPS:
            raise Error("A step count is larger than this port stores")
        if not method.is_usable():
            raise Error(
                "A Newmark method needs gamma of one half or more and a"
                " positive beta"
            )
        if not damping.is_valid():
            raise Error("A damping factor must be zero or more and finite")
        self.step = dt
        self.steps = steps
        self.method = method
        self.damping = damping


struct Response(Movable):
    """The motion of every equation at every step.

    Each list has one vector per time, from time zero. The units are those
    of the matrices given to `newmark`.
    """

    # The time step.
    var step: Float64
    var displacements: List[List[Float64]]
    var velocities: List[List[Float64]]
    var accelerations: List[List[Float64]]

    def __init__(
        out self,
        step: Float64,
        var displacements: List[List[Float64]],
        var velocities: List[List[Float64]],
        var accelerations: List[List[Float64]],
    ):
        """Hold a response. `newmark` makes these.

        Args:
            step: The time step.
            displacements: One vector per time.
            velocities: One vector per time.
            accelerations: One vector per time.
        """
        self.step = step
        self.displacements = displacements^
        self.velocities = velocities^
        self.accelerations = accelerations^


def combine(
    k: CsrMatrix, m: CsrMatrix, k_factor: Float64, m_factor: Float64
) raises -> CsrMatrix:
    """Return k_factor K + m_factor M.

    Args:
        k: The first matrix.
        m: The second matrix, of the same size.
        k_factor: The factor of the first matrix.
        m_factor: The factor of the second matrix.

    Returns:
        The sum.

    Raises:
        Error: If the sizes differ or an entry of the sum is not finite.
    """
    if k.size != m.size:
        raise Error("The stiffness and the mass must have the same size")
    var builder = SparseBuilder(k.size)
    for i in range(k.size):
        for p in range(k.row_start[i], k.row_start[i + 1]):
            builder.add(i, k.columns[p], k_factor * k.values[p])
        for p in range(m.row_start[i], m.row_start[i + 1]):
            builder.add(i, m.columns[p], m_factor * m.values[p])
    return builder.build()


def newmark(
    k: CsrMatrix,
    m: CsrMatrix,
    shape: List[Float64],
    series: TimeSeries,
    options: HistoryOptions,
) raises -> Response:
    """Integrate M a + C v + K u = shape f(t) from rest.

    The matrices can be in any consistent units. C is the Rayleigh damping
    of the options. The initial acceleration solves M a = shape f(0), so
    the mass must be positive definite.

    Args:
        k: The stiffness. Symmetric.
        m: The mass. Symmetric and positive definite.
        shape: The load shape, one entry per equation.
        series: The factor of the load shape in time.
        options: The step, the step count, the integrator and the damping.

    Returns:
        The displacements, velocities and accelerations at every step.

    Raises:
        Error: If the sizes differ, the mass or the effective stiffness is
            not positive definite, or the response is not finite.
    """
    if len(shape) != k.size:
        raise Error("A load shape must have one entry per equation")
    var n = k.size
    var dt = options.step
    var gamma = options.method.gamma
    var beta = options.method.beta
    var a_m = options.damping.mass_factor
    var a_k = options.damping.stiffness_factor
    # K̂ = K + γ/(β Δt) C + M/(β Δt²), with C = a_m M + a_k K.
    var c_factor = gamma / (beta * dt)
    var effective = combine(
        k, m, 1 + c_factor * a_k, c_factor * a_m + 1 / (beta * dt * dt)
    )
    var mass_factor = SkylineFactor(m, reverse_cuthill_mckee(m))
    if not mass_factor.is_positive_definite():
        raise Error("The mass must be positive definite")
    var factor = SkylineFactor(effective, reverse_cuthill_mckee(effective))
    if not factor.is_positive_definite():
        raise Error("The effective stiffness must be positive definite")
    var u = zeros(n)
    var v = zeros(n)
    var f0 = series.at(0)
    var start = zeros(n)
    for i in range(n):
        start[i] = shape[i] * f0
    var a = mass_factor.solve(start)
    var us = List[List[Float64]](capacity=options.steps + 1)
    var vs = List[List[Float64]](capacity=options.steps + 1)
    var accs = List[List[Float64]](capacity=options.steps + 1)
    us.append(u.copy())
    vs.append(v.copy())
    accs.append(a.copy())
    # The factors of Chopra's table 5.4.2.
    var mu = 1 / (beta * dt * dt)
    var mv = 1 / (beta * dt)
    var ma = 1 / (2 * beta) - 1
    var cu = gamma / (beta * dt)
    var cv = gamma / beta - 1
    var ca = dt * (gamma / (2 * beta) - 1)
    for step in range(1, options.steps + 1):  # pragma: no branch
        var f = series.at(Float64(step) * dt)
        var for_mass = zeros(n)
        var for_damping = zeros(n)
        for i in range(n):
            for_mass[i] = mu * u[i] + mv * v[i] + ma * a[i]
            for_damping[i] = cu * u[i] + cv * v[i] + ca * a[i]
        # C x = a_m M x + a_k K x, so the mass takes both terms.
        for i in range(n):
            for_mass[i] += a_m * for_damping[i]
        var rhs = m.multiply(for_mass)
        var stiff = k.multiply(for_damping)
        for i in range(n):
            rhs[i] += shape[i] * f + a_k * stiff[i]
        var next = factor.solve(rhs)
        for i in range(n):
            var du = next[i] - u[i]
            var new_v = cu * du - cv * v[i] - ca * a[i]
            var new_a = mu * du - mv * v[i] - ma * a[i]
            require_finite(next[i], "The response is not finite")
            u[i] = next[i]
            v[i] = new_v
            a[i] = new_a
        us.append(u.copy())
        vs.append(v.copy())
        accs.append(a.copy())
    return Response(dt, us^, vs^, accs^)


struct TimeHistory(Movable):
    """The motion of a structural model in time.

    Each list has one vector per time, from time zero. A vector has six
    entries per node, in the order of `Dof`, in meters and radians and
    their rates. A fixed degree of freedom is zero. Under a ground motion
    the motion is relative to the ground.
    """

    # The time step, in seconds.
    var step: Float64
    var displacements: List[List[Float64]]
    var velocities: List[List[Float64]]
    var accelerations: List[List[Float64]]

    def __init__(
        out self,
        step: Float64,
        var displacements: List[List[Float64]],
        var velocities: List[List[Float64]],
        var accelerations: List[List[Float64]],
    ):
        """Hold a history. The `solve_` functions make these.

        Args:
            step: The time step, in seconds.
            displacements: One vector per time.
            velocities: One vector per time.
            accelerations: One vector per time.
        """
        self.step = step
        self.displacements = displacements^
        self.velocities = velocities^
        self.accelerations = accelerations^

    def count(self) -> Int:
        """Return how many times the history holds.

        Returns:
            The step count plus one, for time zero.
        """
        return len(self.displacements)

    def time(self, index: Int) raises -> Duration64:
        """Return the time of an entry.

        Args:
            index: The entry, from zero.

        Returns:
            The time.

        Raises:
            Error: If the index is out of range.
        """
        if index < 0 or index >= self.count():
            raise Error("A history index is out of range")
        return Duration64(Float64(index) * self.step)

    def _entry(self, node: NodeId, dof: Dof) raises -> Int:
        """Return the entry of a node's translation."""
        if not dof.is_translation():
            raise Error("A translation needs UX, UY or UZ")
        if not node.is_valid() or 6 * node.value >= len(self.displacements[0]):
            raise Error("A node id is out of range")
        return 6 * node.value + dof.value

    def translation(
        self, index: Int, node: NodeId, dof: Dof
    ) raises -> Length64:
        """Return a displacement along a global axis at one time.

        Args:
            index: The entry, from zero.
            node: The node.
            dof: `UX`, `UY` or `UZ`.

        Returns:
            The displacement.

        Raises:
            Error: If the index or the node id is out of range, or the
                degree of freedom is not a translation.
        """
        _ = self.time(index)
        return Length64(self.displacements[index][self._entry(node, dof)])

    def peak_translation(self, node: NodeId, dof: Dof) raises -> Length64:
        """Return the largest size of a displacement over the history.

        Args:
            node: The node.
            dof: `UX`, `UY` or `UZ`.

        Returns:
            The largest absolute displacement. Zero or more.

        Raises:
            Error: If the node id is out of range or the degree of freedom
                is not a translation.
        """
        var entry = self._entry(node, dof)
        var peak = Float64(0)
        for i in range(self.count()):  # pragma: no branch
            peak = max(peak, abs(self.displacements[i][entry]))
        return Length64(peak)


def _expand(
    values: List[List[Float64]], equation: List[Int]
) -> List[List[Float64]]:
    """Return each reduced vector with zeros at the fixed entries."""
    var out = List[List[Float64]](capacity=len(values))
    for s in range(len(values)):  # pragma: no branch
        var full = List[Float64](length=len(equation), fill=0)
        for j in range(len(equation)):
            if equation[j] >= 0:
                full[j] = values[s][equation[j]]
        out.append(full^)
    return out^


def _solve(
    model: StructuralModel,
    mass: CsrMatrix,
    shape: List[Float64],
    series: TimeSeries,
    options: HistoryOptions,
) raises -> TimeHistory:
    """Integrate a model under a full load shape."""
    var equation = free_equations(model)
    var size = 0
    for i in range(len(equation)):
        if equation[i] >= 0:
            size += 1
    var k = reduce_matrix(assemble_stiffness(model), equation, size)
    _ = factor_stiffness(k)
    var m = reduce_matrix(mass, equation, size)
    var reduced = zeros(size)
    for i in range(len(equation)):
        if equation[i] >= 0:
            reduced[equation[i]] = shape[i]
    var response = newmark(k, m, reduced, series, options)
    return TimeHistory(
        options.step,
        _expand(response.displacements, equation),
        _expand(response.velocities, equation),
        _expand(response.accelerations, equation),
    )


def solve_load_history(
    model: StructuralModel,
    load_case: LoadCaseId,
    series: TimeSeries,
    options: HistoryOptions,
) raises -> TimeHistory:
    """Return the motion of a model under a load case scaled in time.

    The load at a time is the load vector of the case times the series
    factor. The model starts at rest.

    Args:
        model: The model. Every free degree of freedom needs mass.
        load_case: The load case.
        series: The factor of the load case in time.
        options: The step, the step count, the integrator and the damping.

    Returns:
        The history.

    Raises:
        Error: If the load case id is out of range, the structure is a
            mechanism, the mass is not positive definite or the response
            is not finite.
    """
    var shape = load_vector(model, load_case)
    return _solve(model, assemble_mass(model), shape, series, options)


def solve_ground_motion(
    model: StructuralModel, motion: GroundMotion, options: HistoryOptions
) raises -> TimeHistory:
    """Return the motion of a model relative to an accelerating ground.

    Every support moves with the ground. The effective load is
    -M r a(t), with r one at each translation along the motion's axis and
    a(t) the ground acceleration.

    Args:
        model: The model. Every free degree of freedom needs mass.
        motion: The ground motion.
        options: The step, the step count, the integrator and the damping.

    Returns:
        The history, relative to the ground.

    Raises:
        Error: If the structure is a mechanism, the mass is not positive
            definite or the response is not finite.
    """
    var mass = assemble_mass(model)
    var rigid = zeros(model.dof_count())
    for n in range(len(model.nodes)):
        rigid[6 * n + motion.dof.value] = -motion.scale
    var shape = mass.multiply(rigid)
    return _solve(model, mass, shape, motion.series, options)
