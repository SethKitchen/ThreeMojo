# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The shadows of the castle on its courtyard.

The sun is a point at infinity in one direction. A point of the lawn is in the
sun if the ray from it toward the sun meets no part of the castle. The ray is
marched in half meter steps and each step is tested against the solids of the
plan: each tower is a cylinder up to its top, each wing is a prism over its
band up to its ridge, and the gate is a prism over its block up to its top. A
roof slopes below its ridge, so the shade of a wing is a little too large, which
is safe.

The courtyard is the island: the ground that lies inside the convex hull of the
moat, outside the water, and outside the footprint of any solid. The share of
it that is in the sun at an hour is the quantity that matters to a lawn, a tree
or a garden.
"""

from std.math import sqrt
from extensions.castle.plan import (
    CastlePlan,
    Point,
    convex_hull,
    point,
    polygon_contains,
)
from extensions.castle.sun import SunPosition, shadow_length
from units.si import Length64

# The step of the ray, in meters.
comptime _RAY_STEP = 0.5
# The longest ray, in meters. A shadow of the donjon is 50 m long in October.
comptime _RAY_LENGTH = 150.0


def _blocked(
    plan: CastlePlan, x: Float64, y: Float64, z: Float64
) raises -> Bool:
    """Return True if a point, at a height over the ground of the island, lies
    inside a solid of the plan."""
    var datum = plan.island_level.value
    var at = point(x, y)
    for tower in plan.towers:  # pragma: no branch
        var dx = x - tower.center.x.value
        var dy = y - tower.center.y.value
        if (
            dx * dx + dy * dy < tower.radius.value**2
            and z < tower.top().value - datum
        ):
            return True
    for wing in plan.wings:  # pragma: no branch
        if z < wing.base.value + wing.ridge_height.value - datum:
            if polygon_contains(wing.outline(), at):
                return True
    ref gate = plan.gate
    if z < gate.base.value + gate.height.value + gate.parapet.value - datum:
        if polygon_contains(gate.outline(), at):
            return True
    return False


def courtyard_points(plan: CastlePlan, step: Length64) raises -> List[Point]:
    """Return a grid of points of the courtyard.

    Args:
        plan: The plan.
        step: The spacing of the grid.

    Returns:
        The points on the island that lie outside every solid.

    Raises:
        Error: If the step is not positive and finite, or the plan is not
            valid.
    """
    if not (step.value > 0.0 and step.value < 1.0e6):
        raise Error("A step must be positive and finite")
    plan.check()
    var hull = convex_hull(plan.moat.outline)
    var low_x = Float64(1.0e30)
    var low_y = Float64(1.0e30)
    var high_x = Float64(-1.0e30)
    var high_y = Float64(-1.0e30)
    for corner in hull:  # pragma: no branch
        low_x = min(low_x, corner.x.value)
        low_y = min(low_y, corner.y.value)
        high_x = max(high_x, corner.x.value)
        high_y = max(high_y, corner.y.value)
    var points = List[Point]()
    var y = low_y + step.value / 2.0
    while y < high_y:
        var x = low_x + step.value / 2.0
        while x < high_x:
            var at = point(x, y)
            if polygon_contains(hull, at) and not polygon_contains(
                plan.moat.outline, at
            ):
                if not _blocked(plan, x, y, 0.05):
                    points.append(at)
            x += step.value
        y += step.value
    return points^


def is_in_sun(
    plan: CastlePlan, at: Point, position: SunPosition
) raises -> Bool:
    """Return True if a point of the ground of the island is in the sun.

    Args:
        plan: The plan.
        at: The point, in the plan.
        position: Where the sun is.

    Returns:
        False if the sun is under the horizon or a solid stands between.

    Raises:
        Error: If the plan is not valid.
    """
    if not position.above_horizon():
        return False
    var toward = position.toward()
    var highest = Float64(0)
    for tower in plan.towers:  # pragma: no branch
        highest = max(highest, tower.top().value - plan.island_level.value)
    var t = _RAY_STEP
    while t < _RAY_LENGTH:
        var z = 0.05 + t * toward[2]
        if z > highest:
            return True
        if _blocked(
            plan,
            at.x.value + t * toward[0],
            at.y.value + t * toward[1],
            z,
        ):
            return False
        t += _RAY_STEP
    return True


def lit_fraction(
    plan: CastlePlan, position: SunPosition, step: Length64
) raises -> Float64:
    """Return the share of the courtyard that is in the sun.

    Args:
        plan: The plan.
        position: Where the sun is.
        step: The spacing of the grid of points.

    Returns:
        A number from 0 to 1, by area.

    Raises:
        Error: If the step is not positive and finite, the plan is not valid,
            or the courtyard has no point at this step.
    """
    var points = courtyard_points(plan, step)
    if len(points) == 0:
        raise Error("The courtyard has no point at this step")
    var lit = 0
    for at in points:  # pragma: no branch
        if is_in_sun(plan, at, position):
            lit += 1
    return Float64(lit) / Float64(len(points))


def donjon_shadow(
    plan: CastlePlan, position: SunPosition
) raises -> Tuple[Length64, Length64, Length64]:
    """Return how far the shadow of the donjon falls, and where its tip is.

    Args:
        plan: The plan, whose first tower is the donjon.
        position: Where the sun is.

    Returns:
        The length of the shadow, and the east and north offset of its tip
        from the middle of the donjon.

    Raises:
        Error: If the plan has no tower or the sun is not over the horizon.
    """
    if len(plan.towers) == 0:
        raise Error("A plan needs a tower for a donjon")
    var height = Length64(plan.towers[0].top().value - plan.island_level.value)
    var length = shadow_length(height, position)
    var toward = position.toward()
    var flat = sqrt(toward[0] * toward[0] + toward[1] * toward[1])
    return (
        length,
        Length64(-length.value * toward[0] / flat),
        Length64(-length.value * toward[1] / flat),
    )
