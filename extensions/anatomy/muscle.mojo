# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A Hill-type muscle: architecture, force curves and a static solve.

A muscle is its architecture: belly mass, optimal fiber length,
pennation angle at that length, tendon slack length, and the specific
tension of its fibers. The physiological cross-sectional area is
`PCSA = m / (rho L0)` (Sacks and Roy, *Architecture of the hind limb
muscles of cats: functional significance*, J. Morphol. 1982). The
maximum isometric force is `F0 = sigma PCSA`.

The force curves are those of Thelen, *Adjustment of muscle mechanics
model parameters to simulate dynamic contractions in older adults*,
J. Biomech. Eng. 125:70-77, 2003, with the young-adult parameters:

- active force-length: `exp(-(l - 1)^2 / 0.45)`,
- passive force-length: `(exp(4 (l - 1) / 0.6) - 1) / (exp(4) - 1)`,
- force-velocity: the inverse of Thelen's equation at full activation,
  with `Af = 0.25`, `Flen = 1.4`, and a maximum shortening velocity of
  ten optimal fiber lengths per second that falls to a quarter of that
  as activation falls to zero,
- tendon: an exponential toe to strain `0.609 e0` and then a line, with
  `e0 = 0.04` the strain at `F0`.

The fibers keep a constant thickness, so the pennation angle grows as
they shorten: `sin a = L0 sin a0 / l`.

Every input and output carries its unit. The curves are dimensionless
and take and return `Float64`.
"""

from generators.utils import Vec3d
from std.math import asin, cos, exp, isfinite, sin, sqrt
from units.si import (
    KILOGRAM_PER_CUBIC_METER,
    DEGREE,
    METER,
    MEGAPASCAL,
    PER_SECOND,
    RADIAN,
    SQUARE_METER,
    Angle,
    Area,
    Density,
    Force,
    Frequency,
    Length,
    Mass,
    Pressure,
    Velocity,
)

# Thelen 2003, young adults.
comptime SHAPE_FACTOR = 0.45
comptime PASSIVE_SHAPE = 4.0
comptime PASSIVE_STRAIN = 0.6
comptime SHORTENING_SHAPE = 0.25
comptime LENGTHENING_LIMIT = 1.4
comptime MAX_VELOCITY = 10.0
comptime TENDON_STRAIN = 0.04
comptime TOE_FORCE = 0.33
comptime TOE_SHAPE = 3.0
comptime ACTIVATION_TIME = 0.015
comptime DEACTIVATION_TIME = 0.050

# Mammalian skeletal muscle, after Mendez and Keys 1960.
comptime MUSCLE_DENSITY = 1060.0
# A whole-muscle maximum isometric stress of 0.3 MPa: the middle of the
# vertebrate range that Medler, *Comparative trends in shortening
# velocity and force production in skeletal muscles*, Am. J. Physiol.
# Regul. Integr. Comp. Physiol. 283:R368-R378, 2002, reviews.
comptime SPECIFIC_TENSION = 0.3

# The static solve halves its bracket this many times: 2^-60 of the
# muscle-tendon length is far below a Float32 meter.
comptime SOLVE_STEPS = 60


def _check_normalized_length(value: Float64) raises:
    if not (isfinite(value) and value >= 0.0):
        raise Error("A normalized fiber length must be finite and nonnegative")


def _check_activation(value: Float64) raises:
    if not (value >= 0.0 and value <= 1.0):
        raise Error("A muscle's activation or excitation must be 0 to 1")


def _finite_force(value: Float64) raises -> Float64:
    if not isfinite(value):
        raise Error("The muscle force is outside the finite numeric range")
    return value


def active_force_length(l: Float64) raises -> Float64:
    """Return the active force at a normalized fiber length.

    Args:
        l: The fiber length over the optimal fiber length.

    Returns:
        A fraction of `F0`, one at `l = 1`.

    Raises:
        Error: If the normalized length is negative or not finite.
    """
    _check_normalized_length(l)
    var d = l - 1.0
    return exp(-d * d / SHAPE_FACTOR)


def passive_force_length(l: Float64) raises -> Float64:
    """Return the passive fiber force at a normalized fiber length.

    Args:
        l: The fiber length over the optimal fiber length.

    Returns:
        A fraction of `F0`: zero up to `l = 1`, one at `l = 1.6`.

    Raises:
        Error: If the length is invalid or the force overflows.
    """
    _check_normalized_length(l)
    if l <= 1.0:
        return 0.0
    var top = exp(PASSIVE_SHAPE * (l - 1.0) / PASSIVE_STRAIN) - 1.0
    return _finite_force(top / (exp(PASSIVE_SHAPE) - 1.0))


def force_velocity(v: Float64) raises -> Float64:
    """Return the force-velocity factor at a normalized fiber velocity.

    Args:
        v: The fiber velocity over the maximum shortening velocity:
            negative while the fiber shortens, positive while it
            lengthens.

    Returns:
        Zero at `v <= -1`, one at `v = 0`, and up to 1.4 while the fiber
        lengthens.

    Raises:
        Error: If the normalized velocity is not finite.
    """
    if not isfinite(v):
        raise Error("A normalized fiber velocity must be finite")
    if v <= -1.0:
        return 0.0
    if v <= 0.0:
        return (1.0 + v) / (1.0 - v / SHORTENING_SHAPE)
    var k = (2.0 + 2.0 / SHORTENING_SHAPE) / (LENGTHENING_LIMIT - 1.0)
    return LENGTHENING_LIMIT - (LENGTHENING_LIMIT - 1.0) / (1.0 + v * k)


def tendon_force(strain: Float64) raises -> Float64:
    """Return the tendon force at a tendon strain.

    Args:
        strain: The tendon length over its slack length, minus one.

    Returns:
        A fraction of `F0`: zero for a slack tendon, one at 4% strain.

    Raises:
        Error: If the strain is not finite or the force overflows.
    """
    if not isfinite(strain):
        raise Error("A tendon strain must be finite")
    if strain <= 0.0:
        return 0.0
    var toe = 0.609 * TENDON_STRAIN
    if strain <= toe:
        var rise = exp(TOE_SHAPE * strain / toe) - 1.0
        return TOE_FORCE * rise / (exp(TOE_SHAPE) - 1.0)
    return _finite_force(1.712 / TENDON_STRAIN * (strain - toe) + TOE_FORCE)


def activation_rate(
    excitation: Float64, activation: Float64
) raises -> Frequency:
    """Return the rate of change of activation.

    Thelen's first-order dynamics: activation rises with a time constant
    of 15 ms and falls with one of 50 ms, both scaled by activation.

    Args:
        excitation: The neural drive, zero to one.
        activation: The present activation, zero to one.

    Returns:
        `da/dt`, per second.

    Raises:
        Error: If either input is outside `[0, 1]` or not finite.
    """
    _check_activation(excitation)
    _check_activation(activation)
    var scale = 0.5 + 1.5 * activation
    var tau = DEACTIVATION_TIME / scale
    if excitation > activation:
        tau = ACTIVATION_TIME * scale
    return Frequency(Float32((excitation - activation) / tau), PER_SECOND)


@fieldwise_init
struct MuscleArchitecture(ImplicitlyCopyable, Writable):
    """The measured architecture of one muscle-tendon unit."""

    # The belly's wet mass, tendon excluded.
    var mass: Mass
    # The fiber length at which active force peaks.
    var fiber_length: Length
    # The pennation angle at the optimal fiber length.
    var pennation: Angle
    # The tendon length below which the tendon carries no force.
    var tendon_slack: Length
    # The maximum isometric stress of the fibers.
    var specific_tension: Pressure
    # The belly's wet density.
    var density: Density

    def check(self) raises:
        """Refuse an architecture no muscle has.

        Raises:
            Error: If a quantity is not finite, if the mass, fiber
                length, specific tension or density is not positive, if
                the tendon slack is negative, or if the pennation angle
                is not in `[0, 60]` degrees.
        """
        var values = [
            self.mass.value,
            self.fiber_length.value,
            self.pennation.value,
            self.tendon_slack.value,
            self.specific_tension.value,
            self.density.value,
        ]
        for v in values:  # pragma: no branch
            if not isfinite(v):
                raise Error("A muscle's architecture must be finite")
        if self.mass.value <= 0.0:
            raise Error("A muscle's mass must be positive")
        if self.fiber_length.value <= 0.0:
            raise Error("A muscle's fiber length must be positive")
        if self.specific_tension.value <= 0.0:
            raise Error("A muscle's specific tension must be positive")
        if self.density.value <= 0.0:
            raise Error("A muscle's density must be positive")
        if self.tendon_slack.value < 0.0:
            raise Error("A muscle's tendon slack length cannot be negative")
        if (
            self.pennation.value < 0.0
            or self.pennation.value > Angle(60, DEGREE).value
        ):
            raise Error("A muscle's pennation must be 0 to 60 degrees")

    def volume_m3(self) raises -> Float64:
        """Return the belly's volume, in cubic meters.

        Returns:
            Mass over density.

        Raises:
            Error: If the architecture is invalid.
        """
        self.check()
        return Float64(self.mass.value) / Float64(self.density.value)

    def pcsa(self) raises -> Area:
        """Return the physiological cross-sectional area.

        Returns:
            Volume over optimal fiber length.

        Raises:
            Error: If the architecture or the SI result is invalid.
        """
        var area = self.volume_m3() / Float64(self.fiber_length.value)
        if not (isfinite(Float32(area)) and Float32(area) > 0.0):
            raise Error("Muscle PCSA must fit a finite positive SI quantity")
        return Area(Float32(area), SQUARE_METER)

    def max_force(self) raises -> Force:
        """Return the maximum isometric fiber force, `F0`.

        Returns:
            Specific tension times PCSA.

        Raises:
            Error: If the architecture or the SI result is invalid.
        """
        var force = self.specific_tension * self.pcsa()
        if not (isfinite(force.value) and force.value > 0.0):
            raise Error("Maximum muscle force must be finite and positive")
        return force

    def thickness(self) raises -> Float64:
        """Return the fibers' constant perpendicular spacing, in meters.

        Returns:
            `L0 sin a0`.

        Raises:
            Error: If the architecture is invalid.
        """
        self.check()
        return Float64(self.fiber_length.value) * sin(
            Float64(self.pennation.value)
        )

    def pennation_at(self, fiber_m: Float64) raises -> Float64:
        """Return the pennation angle at a fiber length.

        Args:
            fiber_m: The fiber length, in meters.

        Returns:
            The angle, in radians, at most a right angle.

        Raises:
            Error: If the architecture or fiber length is invalid.
        """
        if not (isfinite(fiber_m) and fiber_m > 0.0):
            raise Error("A fiber length must be finite and positive")
        var s = self.thickness() / fiber_m
        if s >= 1.0:
            return asin(1.0)
        return asin(s)

    def fiber_force(
        self,
        activation: Float64,
        fiber: Length,
        velocity: Velocity,
    ) raises -> Force:
        """Return the force the fibers put on the tendon.

        Args:
            activation: The activation, zero to one.
            fiber: The fiber length.
            velocity: The fiber velocity, negative while it shortens.

        Returns:
            Active and passive fiber force, along the tendon.

        Raises:
            Error: If the architecture or state is invalid, or the force overflows.
        """
        self.check()
        _check_activation(activation)
        if not (isfinite(fiber.value) and fiber.value > 0.0):
            raise Error("A fiber length must be finite and positive")
        if not isfinite(velocity.value):
            raise Error("A fiber velocity must be finite")
        var l0 = Float64(self.fiber_length.value)
        var l = Float64(fiber.value) / l0
        var top = (0.25 + 0.75 * activation) * MAX_VELOCITY * l0
        var v = Float64(velocity.value) / top
        var f = activation * active_force_length(l) * force_velocity(
            v
        ) + passive_force_length(l)
        var along = f * cos(self.pennation_at(Float64(fiber.value)))
        var value = Float64(self.max_force().value) * along
        _ = _finite_force(value)
        var narrowed = Float32(value)
        if not isfinite(narrowed) or (value != 0.0 and narrowed == 0.0):
            raise Error("Muscle force must fit a finite SI quantity")
        return Force(narrowed)


@fieldwise_init
struct MuscleEquilibrium(ImplicitlyCopyable):
    """A muscle-tendon unit at rest under a held activation."""

    var force: Force
    var fiber_length: Length
    var tendon_length: Length
    var pennation: Angle


def _fiber_from_reach(
    arch: MuscleArchitecture, reach: Float64
) raises -> Float64:
    var h = arch.thickness()
    return sqrt(reach * reach + h * h)


def _mismatch(
    arch: MuscleArchitecture, activation: Float64, unit: Float64, reach: Float64
) raises -> Float64:
    # Fiber force along the tendon minus tendon force, both over F0.
    var l0 = Float64(arch.fiber_length.value)
    var slack = Float64(arch.tendon_slack.value)
    var fiber = _fiber_from_reach(arch, reach)
    var l = fiber / l0
    var fibers = activation * active_force_length(l) + passive_force_length(l)
    var along = fibers * reach / fiber
    var tendon = tendon_force((unit - reach - slack) / slack)
    return along - tendon


def isometric_equilibrium(
    arch: MuscleArchitecture, activation: Float64, unit_length: Length
) raises -> MuscleEquilibrium:
    """Return the force of a muscle-tendon unit held at one length.

    The fibers and the tendon are in series, so at rest they carry one
    force. The solve bisects the fibers' reach along the unit: a slack
    tendon means the fibers carry more than the tendon, and a stretched
    one means less.

    Args:
        arch: The muscle's architecture.
        activation: The held activation, zero to one.
        unit_length: The origin-to-insertion length of the unit.

    Returns:
        The force, the fiber and tendon lengths, and the pennation.

    Raises:
        Error: If the architecture is not valid, if the activation is
            not in `[0, 1]`, the unit is not finite, the force overflows,
            or if the unit is not longer than its
            tendon's slack length.
    """
    arch.check()
    _check_activation(activation)
    if arch.tendon_slack.value <= 0.0:
        raise Error("The static solve needs a tendon with a slack length")
    var unit = Float64(unit_length.value)
    var slack = Float64(arch.tendon_slack.value)
    if not (isfinite(unit) and unit > slack):
        raise Error("A muscle-tendon unit must be longer than its tendon")
    # At zero reach the fibers stand across the unit and pull nothing
    # along it; at full reach the tendon is slack.
    var low = 0.0
    var high = unit - slack
    for _ in range(SOLVE_STEPS):  # pragma: no branch
        var mid = 0.5 * (low + high)
        if _mismatch(arch, activation, unit, mid) < 0.0:
            low = mid
        else:
            high = mid
    var reach = 0.5 * (low + high)
    var fiber = _fiber_from_reach(arch, reach)
    var strain = (unit - reach - slack) / slack
    var factor = tendon_force(strain)
    var residual = _mismatch(arch, activation, unit, reach)
    if not (isfinite(residual) and abs(residual) <= 1e-8 * (1.0 + abs(factor))):
        raise Error("The available precision cannot resolve equilibrium")
    var value = Float64(arch.max_force().value) * factor
    var force = Force(Float32(value))
    if value != 0.0 and force.value == 0.0:
        raise Error("Equilibrium force must fit a finite SI quantity")
    _ = _finite_force(Float64(force.value))
    if not (isfinite(Float32(fiber)) and Float32(fiber) > 0.0):
        raise Error(
            "Equilibrium fiber length must fit a positive finite SI length"
        )
    if not (isfinite(Float32(unit - reach)) and Float32(unit - reach) > 0.0):
        raise Error(
            "Equilibrium tendon length must fit a positive finite SI length"
        )
    return MuscleEquilibrium(
        force,
        Length(Float32(fiber), METER),
        Length(Float32(unit - reach), METER),
        Angle(Float32(asin(arch.thickness() / fiber)), RADIAN),
    )


def moment_arm(
    origin: Vec3d, insertion: Vec3d, center: Vec3d, axis: Vec3d
) raises -> Length:
    """Return the moment arm of a straight muscle about a joint axis.

    The muscle pulls the insertion toward the origin. A positive moment
    arm turns the distal segment about `axis` by the right-hand rule.

    Args:
        origin: Where the muscle leaves the proximal segment, in meters.
        insertion: Where it attaches to the distal segment, in meters.
        center: A point on the joint axis, in meters.
        axis: The joint axis, any length but zero.

    Returns:
        `((insertion - center) x pull) . axis`, with `pull` the unit
        vector from the insertion toward the origin.

    Raises:
        Error: If the origin and insertion meet, or if the axis has no
            length.
    """
    for p in [origin, insertion, center, axis]:  # pragma: no branch
        if not (isfinite(p.x) and isfinite(p.y) and isfinite(p.z)):
            raise Error("Muscle moment-arm points and axis must be finite")
    var line = origin - insertion
    var reach = line.length()
    var size = axis.length()
    if not (isfinite(reach) and reach > 0.0):
        raise Error("A muscle's origin and insertion must differ")
    if not (isfinite(size) and size > 0.0):
        raise Error("A joint axis must have a direction")
    var lever = insertion - center
    var pull = line * (1.0 / reach)
    var arm = lever.cross(pull).dot(axis * (1.0 / size))
    if not isfinite(Float32(arm)):
        raise Error("A muscle moment arm must fit a finite SI length")
    return Length(Float32(arm), METER)


def default_tension() -> Pressure:
    """Return the specific tension the anatomy uses by default.

    Returns:
        0.3 MPa.
    """
    return Pressure(Float32(SPECIFIC_TENSION), MEGAPASCAL)


def muscle_density() -> Density:
    """Return the wet density of skeletal muscle.

    Returns:
        1060 kg/m^3.
    """
    return Density(Float32(MUSCLE_DENSITY), KILOGRAM_PER_CUBIC_METER)
