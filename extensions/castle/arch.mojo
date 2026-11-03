# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Limit analysis of a masonry arch, after Heyman.

Heyman's three assumptions make masonry a rigid-plastic material: it has no
tensile strength, its compressive strength is so high that crushing does not
govern, and one stone does not slide on another. The safe theorem then says
that an arch stands if a line of thrust, in equilibrium with the loads, lies
inside the masonry everywhere. Nothing more is needed. The arch need not be
shown to be elastic, and the line need not be the one that the arch carries.

A semicircular ring of mean radius R and thickness t carries its own weight.
A free body from the crown to a joint at the angle theta from the crown has
the horizontal thrust H of the crown on its end, the weight W of the ring
over it, and the force at the joint. Moments about the point where the line
of thrust cuts the joint, at the distance rho from the center, give

    rho (H cos(theta) + W sin(theta)) = M0 + W x(theta),

with M0 the moment H rho0 of the crown thrust about the center, and x the
distance of the centroid of the weight from the crown axis. The line is inside
the masonry when the inner radius is no more than rho, and the outer radius no
less, at every joint. Each limit is linear in H and M0, so for any H the
possible M0 form an interval. The interval is the largest at the thrust that
the arch needs, and the arch stands if it is not empty there. The difference
of the limits is a concave function of H, so a ternary search finds its
maximum.

The least thickness is found by bisection. For the semicircular arch with
only its own weight it is 0.1075 of the mean radius (Couplet, 1730;
Heyman, 1966). The ratio of the real thickness to the least is Heyman's
geometrical factor of safety. A factor of 2 means that the ring could be half
as thick and still stand.
"""

from std.math import cos, isfinite, pi, sin, sqrt
from extensions.castle.masonry import Masonry, historic_brick
from extensions.castle.plan import CastlePlan
from units.si import Length64, LineLoad64

# The number of joints between the crown and the springing that the search
# checks. At 720 they are an eighth of a degree apart.
comptime DEFAULT_JOINTS = 720
# The largest horizontal thrust that the search considers, in units of the
# unit weight times the radius squared. A semicircular ring of any thickness up
# to the radius needs under 1.
comptime _LARGEST_THRUST = 3.0
# The width of the bisection, in thicknesses over radius, at which it stops.
comptime _TOLERANCE = 1.0e-9


def _slack(ratio: Float64, thrust: Float64, joints: Int) -> Float64:
    """Return how much room the moment of the crown thrust has, for a ring of
    a thickness, a thrust and a number of joints.

    The ring has a mean radius of 1 and a unit weight of 1. The result is the
    upper bound of the moment least the lower bound, so it is not negative when
    a line of thrust fits.
    """
    var outer = 1.0 + ratio / 2.0
    var inner = 1.0 - ratio / 2.0
    var centroid_factor = (
        4.0 / 3.0 * (outer**3 - inner**3) / (outer * outer - inner * inner)
    )
    var lowest_upper = Float64(1.0e30)
    var highest_lower = Float64(-1.0e30)
    for k in range(joints + 1):  # pragma: no branch
        var theta = pi / 2.0 * Float64(k) / Float64(joints)
        var weight = ratio * theta
        var centroid = Float64(0)
        if theta > 0.0:
            var half = sin(theta / 2.0)
            centroid = centroid_factor * half * half / theta
        var arm = thrust * cos(theta) + weight * sin(theta)
        var offset = weight * centroid
        var upper = outer * arm - offset
        var lower = inner * arm - offset
        lowest_upper = min(lowest_upper, upper)
        highest_lower = max(highest_lower, lower)
    return lowest_upper - highest_lower


def _best_thrust(ratio: Float64, joints: Int) -> Tuple[Float64, Float64]:
    """Return the thrust at which the room is greatest, and the room there,
    by ternary search on a concave function."""
    var low = Float64(0)
    var high = _LARGEST_THRUST
    for _ in range(100):
        var a = low + (high - low) / 3.0
        var b = high - (high - low) / 3.0
        if _slack(ratio, a, joints) < _slack(ratio, b, joints):
            low = a
        else:
            high = b
    var thrust = (low + high) / 2.0
    return (thrust, _slack(ratio, thrust, joints))


def minimum_thickness_ratio(joints: Int = DEFAULT_JOINTS) raises -> Float64:
    """Return the least thickness over the mean radius at which a semicircular
    ring stands under its own weight.

    Args:
        joints: The number of joints between the crown and the springing at
            which the line of thrust is held inside the ring. At least 8.

    Returns:
        The ratio, 0.1075 for a fine mesh of joints.

    Raises:
        Error: If there are too few joints.
    """
    if joints < 8:
        raise Error("A search needs at least 8 joints")
    var low = Float64(1.0e-4)
    var high = Float64(1.0)
    while high - low > _TOLERANCE:
        var middle = (low + high) / 2.0
        if _best_thrust(middle, joints)[1] >= 0.0:
            high = middle
        else:
            low = middle
    return high


def thrust_range(
    ratio: Float64, joints: Int = DEFAULT_JOINTS
) raises -> Tuple[Float64, Float64]:
    """Return the least and the greatest horizontal thrust that a line of thrust
    in the ring can have.

    Args:
        ratio: The thickness over the mean radius.
        joints: The number of joints that the line is held inside at.

    Returns:
        The two thrusts, in units of the unit weight times the radius squared
        for a unit width.

    Raises:
        Error: If the ratio is not positive and finite, there are too few
            joints, or no line of thrust fits, so the ring does not stand.
    """
    if not (isfinite(ratio) and ratio > 0.0):
        raise Error("A thickness ratio must be positive and finite")
    if joints < 8:
        raise Error("A search needs at least 8 joints")
    var best = _best_thrust(ratio, joints)
    if best[1] < 0.0:
        raise Error("No line of thrust fits inside this ring: it falls")
    var peak = best[0]
    # On each side of the peak the room falls to 0. Bisection finds where.
    var left = Float64(0)
    var right = peak
    for _ in range(100):
        var middle = (left + right) / 2.0
        if _slack(ratio, middle, joints) < 0.0:
            left = middle
        else:
            right = middle
    var low = right
    left = peak
    right = _LARGEST_THRUST
    for _ in range(100):
        var middle = (left + right) / 2.0
        if _slack(ratio, middle, joints) < 0.0:
            right = middle
        else:
            left = middle
    var high = left
    return (low, high)


@fieldwise_init
struct Arch(Copyable, Movable):
    """A semicircular ring of masonry, for a unit width."""

    # The radius of the center line of the ring, and its thickness.
    var mean_radius: Length64
    var thickness: Length64
    # The masonry.
    var masonry: Masonry

    def check(self) raises:
        """Refuse a ring that cannot be.

        Raises:
            Error: If the radius or the thickness is not positive and finite,
                the ring is thicker than twice its mean radius, or the
                masonry is not valid.
        """
        if not (
            isfinite(self.mean_radius.value)
            and self.mean_radius.value > 0.0
            and isfinite(self.thickness.value)
            and self.thickness.value > 0.0
        ):
            raise Error("An arch needs a positive finite radius and thickness")
        if not (self.thickness.value < 2.0 * self.mean_radius.value):
            raise Error("A ring cannot be thicker than its mean diameter")
        self.masonry.check()

    def thickness_ratio(self) -> Float64:
        """Return the thickness over the mean radius.

        Returns:
            The ratio.
        """
        return self.thickness.value / self.mean_radius.value


@fieldwise_init
struct ArchCheck(Copyable, Movable):
    """What the limit analysis finds for a ring."""

    # The least thickness over the radius at which a ring stands, and the
    # ratio of this ring.
    var minimum_ratio: Float64
    var ratio: Float64
    # Heyman's geometrical factor of safety: the ratio over the least.
    var geometric_factor: Float64
    # The least and the greatest horizontal thrust, per meter of width.
    var least_thrust: LineLoad64
    var greatest_thrust: LineLoad64
    # The force at the springing when the thrust is least, per meter of width,
    # and the share of the design strength of the masonry that it would take if
    # it acted over the whole thickness.
    var springing_force: LineLoad64
    var crushing_utilization: Float64


def arch_check(arch: Arch, joints: Int = DEFAULT_JOINTS) raises -> ArchCheck:
    """Check a ring by Heyman's safe theorem.

    Args:
        arch: The ring.
        joints: The number of joints the line of thrust is held inside at.

    Returns:
        The least thickness, the geometrical factor of safety, the range of
        the thrust, and the force at the springing.

    Raises:
        Error: If the ring is not valid or does not stand.
    """
    arch.check()
    var minimum = minimum_thickness_ratio(joints)
    var ratio = arch.thickness_ratio()
    var range_ = thrust_range(ratio, joints)
    var scale = arch.masonry.unit_weight().value * arch.mean_radius.value**2
    var weight = ratio * pi / 2.0
    var spring = sqrt(range_[0] * range_[0] + weight * weight)
    var strength = arch.masonry.design_strength().value
    return ArchCheck(
        minimum,
        ratio,
        ratio / minimum,
        LineLoad64(range_[0] * scale),
        LineLoad64(range_[1] * scale),
        LineLoad64(spring * scale),
        spring * scale / (strength * arch.thickness.value),
    )


def bridge_arch(plan: CastlePlan) raises -> Arch:
    """Return an arch of the bridge of a plan.

    The ring is a semicircle across the clear span, as many courses thick as
    the ring of the plan.

    Args:
        plan: The plan.

    Returns:
        The ring, with the masonry assumed for the castle.

    Raises:
        Error: If the bridge is not valid.
    """
    ref bridge = plan.bridge
    var arch = Arch(
        Length64(bridge.clear_span().value / 2.0 + bridge.ring.value / 2.0),
        Length64(bridge.ring.value),
        historic_brick(),
    )
    arch.check()
    return arch^
