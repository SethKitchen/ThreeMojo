# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Steady flow with a free surface in a prismatic channel.

A `Channel` is a trapezoid with a bed slope and a Manning coefficient. A
side slope of zero gives a rectangle, and a bottom width of zero gives a
triangle. For a depth y, a bottom width b and a side slope z, the area is
(b + z y) y, the wetted perimeter is b + 2 y sqrt(1 + z²) and the top
width is b + 2 z y.

- Uniform flow follows Manning: Q = A R^(2/3) sqrt(S) / n. Its depth is
  the normal depth.
- Critical flow has a Froude number of one: Q² T = g A³.
- A hydraulic jump keeps the momentum function Q² / (g A) + A ȳ, with
  A ȳ the first moment of the area about the surface.
- A gradually varied profile keeps the energy between two sections:
  the change of the specific energy is (S₀ - S_f) Δx, with S_f the mean
  friction slope of the two sections. This is the standard step method
  of Chow, "Open-Channel Hydraulics", 1959, chapter 10, which HEC-RAS
  uses for steady profiles.

A subcritical profile is fixed by a control downstream, so it is computed
upstream. A supercritical profile is computed downstream. HEC-RAS is in
the public domain, and the code here is original.
"""

from std.math import isfinite, sqrt
from core.ordinal import require_positive
from math.finite import require_finite, require_positive_finite
from units.si import (
    Area64,
    CUBIC_METER_PER_SECOND,
    Length64,
    METER,
    VolumeFlowRate64,
)

# The standard acceleration of gravity, in meters per second squared.
comptime GRAVITY = 9.80665
# The halvings of a bisection. Each finds a depth to the last bit.
comptime _BISECTIONS = 200
# The largest number of steps of one profile.
comptime MAX_PROFILE_STEPS = 1048576


struct Channel(ImplicitlyCopyable):
    """A trapezoidal channel with a bed slope and a Manning coefficient."""

    # The bottom width, in meters.
    var bottom: Float64
    # The horizontal run of each side for a rise of one.
    var side: Float64
    # The fall of the bed per length along the flow.
    var slope: Float64
    # The Manning coefficient, in s / m^(1/3).
    var roughness: Float64

    def __init__(
        out self,
        bottom_width: Length64,
        side_slope: Float64,
        bed_slope: Float64,
        manning_n: Float64,
    ) raises:
        """Create a channel.

        Args:
            bottom_width: The width of the bed. Zero or more.
            side_slope: The horizontal run of each side for a rise of
                one. Zero or more. Zero gives vertical walls.
            bed_slope: The fall of the bed per length. Finite. Zero is a
                horizontal bed and a negative value is an adverse one.
            manning_n: The Manning coefficient. Positive.

        Raises:
            Error: If the width or the side slope is negative or not
                finite, both are zero, the bed slope is not finite, or
                the coefficient is not positive and finite.
        """
        var b = bottom_width.to(METER)
        if not (b >= 0 and isfinite(b)):
            raise Error("A bottom width must be zero or more and finite")
        if not (side_slope >= 0 and isfinite(side_slope)):
            raise Error("A side slope must be zero or more and finite")
        if b == 0 and side_slope == 0:
            raise Error("A channel needs a bottom width or a side slope")
        require_finite(bed_slope, "A bed slope must be finite")
        require_positive_finite(
            manning_n, "A Manning coefficient must be positive and finite"
        )
        self.bottom = b
        self.side = side_slope
        self.slope = bed_slope
        self.roughness = manning_n

    def area(self, depth: Length64) -> Area64:
        """Return the area of the flow at a depth.

        Args:
            depth: The depth.

        Returns:
            The area (b + z y) y.
        """
        return Area64(_area(self, depth.to(METER)))

    def wetted_perimeter(self, depth: Length64) -> Length64:
        """Return the wetted perimeter at a depth.

        Args:
            depth: The depth.

        Returns:
            The length of the bed and the two sides under water.
        """
        return Length64(_perimeter(self, depth.to(METER)))

    def top_width(self, depth: Length64) -> Length64:
        """Return the width of the water surface at a depth.

        Args:
            depth: The depth.

        Returns:
            The width b + 2 z y.
        """
        return Length64(_top(self, depth.to(METER)))

    def hydraulic_radius(self, depth: Length64) -> Length64:
        """Return the area over the wetted perimeter at a depth.

        Args:
            depth: The depth. Positive.

        Returns:
            The hydraulic radius.
        """
        var y = depth.to(METER)
        return Length64(_area(self, y) / _perimeter(self, y))


def _area(c: Channel, y: Float64) -> Float64:
    """Return the area at a depth, in square meters."""
    return (c.bottom + c.side * y) * y


def _perimeter(c: Channel, y: Float64) -> Float64:
    """Return the wetted perimeter at a depth, in meters."""
    return c.bottom + 2 * y * sqrt(1 + c.side * c.side)


def _top(c: Channel, y: Float64) -> Float64:
    """Return the top width at a depth, in meters."""
    return c.bottom + 2 * c.side * y


def _conveyance(c: Channel, y: Float64) -> Float64:
    """Return A R^(2/3) / n at a depth."""
    var a = _area(c, y)
    return a * (a / _perimeter(c, y)) ** (2.0 / 3.0) / c.roughness


def _energy(c: Channel, q: Float64, y: Float64) -> Float64:
    """Return the specific energy y + v² / (2 g), in meters."""
    var v = q / _area(c, y)
    return y + v * v / (2 * GRAVITY)


def _friction(c: Channel, q: Float64, y: Float64) -> Float64:
    """Return the friction slope (Q / K)²."""
    var ratio = q / _conveyance(c, y)
    return ratio * ratio


def _froude2(c: Channel, q: Float64, y: Float64) -> Float64:
    """Return the Froude number squared, Q² T / (g A³)."""
    var a = _area(c, y)
    return q * q * _top(c, y) / (GRAVITY * a * a * a)


def _momentum(c: Channel, q: Float64, y: Float64) -> Float64:
    """Return the momentum function Q² / (g A) + A ȳ."""
    return q * q / (GRAVITY * _area(c, y)) + (
        c.bottom * y * y / 2 + c.side * y * y * y / 3
    )


def _flow(flow: VolumeFlowRate64) raises -> Float64:
    """Return a flow in cubic meters per second, checked positive."""
    var q = flow.to(CUBIC_METER_PER_SECOND)
    require_positive_finite(q, "A channel flow must be positive and finite")
    return q


def _depth(depth: Length64) raises -> Float64:
    """Return a depth in meters, checked positive."""
    var y = depth.to(METER)
    require_positive_finite(y, "A depth must be positive and finite")
    return y


def manning_flow(channel: Channel, depth: Length64) raises -> VolumeFlowRate64:
    """Return the uniform flow of a channel at a depth.

    Args:
        channel: The channel. Its bed slope must be zero or more.
        depth: The depth. Positive.

    Returns:
        The flow A R^(2/3) sqrt(S) / n.

    Raises:
        Error: If the depth is not positive and finite or the bed slope
            is negative.
    """
    var y = _depth(depth)
    if channel.slope < 0:
        raise Error("Uniform flow needs a bed slope of zero or more")
    return VolumeFlowRate64(_conveyance(channel, y) * sqrt(channel.slope))


def critical_depth(channel: Channel, flow: VolumeFlowRate64) raises -> Length64:
    """Return the depth at which a flow is critical.

    Args:
        channel: The channel.
        flow: The flow. Positive.

    Returns:
        The depth with Q² T = g A³. A shallower flow is supercritical and
        a deeper flow is subcritical.

    Raises:
        Error: If the flow is not positive and finite.
    """
    var q = _flow(flow)
    # The Froude number falls as the depth grows, so bracket and halve.
    var low = Float64(0)
    var high = Float64(1)
    while _froude2(channel, q, high) > 1:
        high *= 2
    for _ in range(_BISECTIONS):  # pragma: no branch
        var middle = 0.5 * (low + high)
        if _froude2(channel, q, middle) > 1:
            low = middle
        else:
            high = middle
    return Length64(0.5 * (low + high))


def normal_depth(channel: Channel, flow: VolumeFlowRate64) raises -> Length64:
    """Return the depth of uniform flow.

    Args:
        channel: The channel. Its bed slope must be positive.
        flow: The flow. Positive.

    Returns:
        The depth at which Manning's formula gives the flow.

    Raises:
        Error: If the flow is not positive and finite or the bed slope is
            not positive. A horizontal or adverse bed has no uniform
            flow.
    """
    var q = _flow(flow)
    if not (channel.slope > 0):
        raise Error("A normal depth needs a positive bed slope")
    # The conveyance grows with the depth, so bracket and halve.
    var needed = q / sqrt(channel.slope)
    var low = Float64(0)
    var high = Float64(1)
    while _conveyance(channel, high) < needed:
        high *= 2
    for _ in range(_BISECTIONS):  # pragma: no branch
        var middle = 0.5 * (low + high)
        if _conveyance(channel, middle) < needed:
            low = middle
        else:
            high = middle
    return Length64(0.5 * (low + high))


def froude_number(
    channel: Channel, flow: VolumeFlowRate64, depth: Length64
) raises -> Float64:
    """Return the Froude number of a flow at a depth.

    Args:
        channel: The channel.
        flow: The flow. Positive.
        depth: The depth. Positive.

    Returns:
        The velocity over sqrt(g A / T). Below one the flow is
        subcritical.

    Raises:
        Error: If the flow or the depth is not positive and finite.
    """
    return sqrt(_froude2(channel, _flow(flow), _depth(depth)))


def specific_energy(
    channel: Channel, flow: VolumeFlowRate64, depth: Length64
) raises -> Length64:
    """Return the specific energy of a flow at a depth.

    Args:
        channel: The channel.
        flow: The flow. Positive.
        depth: The depth. Positive.

    Returns:
        The depth plus the velocity head v² / (2 g).

    Raises:
        Error: If the flow or the depth is not positive and finite.
    """
    return Length64(_energy(channel, _flow(flow), _depth(depth)))


def friction_slope(
    channel: Channel, flow: VolumeFlowRate64, depth: Length64
) raises -> Float64:
    """Return the slope of the energy line of a flow at a depth.

    Args:
        channel: The channel.
        flow: The flow. Positive.
        depth: The depth. Positive.

    Returns:
        The slope n² Q² / (A² R^(4/3)), from Manning's formula.

    Raises:
        Error: If the flow or the depth is not positive and finite.
    """
    return _friction(channel, _flow(flow), _depth(depth))


def sequent_depth(
    channel: Channel, flow: VolumeFlowRate64, depth: Length64
) raises -> Length64:
    """Return the depth on the other side of a hydraulic jump.

    The two depths have the same momentum function. One is supercritical
    and the other is subcritical.

    Args:
        channel: The channel.
        flow: The flow. Positive.
        depth: The depth on one side of the jump. Positive.

    Returns:
        The depth on the other side. A critical depth returns itself.

    Raises:
        Error: If the flow or the depth is not positive and finite.
    """
    var q = _flow(flow)
    var y = _depth(depth)
    var critical = critical_depth(channel, flow).to(METER)
    var target = _momentum(channel, q, y)
    var low: Float64
    var high: Float64
    # The momentum function falls to the critical depth and then rises.
    var rising = y < critical
    if rising:
        low = critical
        high = 2 * critical
        while _momentum(channel, q, high) < target:
            high *= 2
    else:
        low = 0
        high = critical
    for _ in range(_BISECTIONS):  # pragma: no branch
        var middle = 0.5 * (low + high)
        if (_momentum(channel, q, middle) < target) == rising:
            low = middle
        else:
            high = middle
    return Length64(0.5 * (low + high))


@fieldwise_init
struct ProfilePoint(ImplicitlyCopyable):
    """The depth of a profile at a station."""

    # The distance along the channel from the start, positive downstream.
    var station: Length64
    var depth: Length64


def water_surface_profile(
    channel: Channel,
    flow: VolumeFlowRate64,
    start_depth: Length64,
    reach: Length64,
    steps: Int,
) raises -> List[ProfilePoint]:
    """Return a gradually varied profile by the standard step method.

    A start depth above the critical depth gives a subcritical profile.
    It runs upstream from the start, so its stations are negative. A
    start depth below the critical depth gives a supercritical profile,
    which runs downstream.

    Args:
        channel: The channel.
        flow: The flow. Positive.
        start_depth: The depth at the control, at station zero. Positive.
        reach: The length of the profile. Positive.
        steps: How many equal steps. From 1 to 1048576. The error falls
            with the square of the step.

    Returns:
        The start point and one point per step.

    Raises:
        Error: If the flow, the depth or the reach is not positive and
            finite, the step count is out of range, the start depth is
            critical, or the profile reaches the critical depth. A
            profile cannot pass through the critical depth gradually.
    """
    var q = _flow(flow)
    var y = _depth(start_depth)
    var length = reach.to(METER)
    require_positive_finite(length, "A reach must be positive and finite")
    require_positive(steps, "A step count must be positive")
    if steps > MAX_PROFILE_STEPS:
        raise Error("A step count is larger than this port stores")
    var critical = critical_depth(channel, flow).to(METER)
    if y == critical:
        raise Error("A profile cannot start at the critical depth")
    var subcritical = y > critical
    var dx = length / Float64(steps)
    # Upstream of a subcritical section the energy is higher by
    # (S_f - S₀) Δx. Downstream of a supercritical one it is higher by
    # (S₀ - S_f) Δx.
    var direction = Float64(1)
    if subcritical:
        direction = -1
    var out = List[ProfilePoint](capacity=steps + 1)
    out.append(ProfilePoint(Length64(0), Length64(y)))
    for step in range(1, steps + 1):  # pragma: no branch
        var energy = _energy(channel, q, y)
        var friction = _friction(channel, q, y)
        var low: Float64
        var high: Float64
        if subcritical:
            low = critical
            high = 2 * max(y, critical)
            while (
                _balance(channel, q, high, energy, friction, dx, direction) < 0
            ):
                high *= 2
        else:
            low = 0
            high = critical
        if _balance(channel, q, critical, energy, friction, dx, direction) > 0:
            raise Error(
                "The profile reaches the critical depth. Use a shorter reach."
            )
        for _ in range(_BISECTIONS):  # pragma: no branch
            var middle = 0.5 * (low + high)
            var value = _balance(
                channel, q, middle, energy, friction, dx, direction
            )
            if (value < 0) == subcritical:
                low = middle
            else:
                high = middle
        y = 0.5 * (low + high)
        out.append(
            ProfilePoint(Length64(direction * Float64(step) * dx), Length64(y))
        )
    return out^


def _balance(
    c: Channel,
    q: Float64,
    y: Float64,
    energy: Float64,
    friction: Float64,
    dx: Float64,
    direction: Float64,
) -> Float64:
    """Return the energy at a trial depth less the energy it must have.

    The trial section is one step from a section of known energy and
    friction slope, upstream for a direction of -1 and downstream for 1.
    """
    var mean = 0.5 * (friction + _friction(c, q, y))
    return _energy(c, q, y) - energy - direction * (c.slope - mean) * dx
