# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How a wall moves when it fails, and the colors of its utilization.

**Motions.** Each external failure mode moves the wall as a rigid body in
the plane of its section. x runs from the toe edge toward the heel and y
up from the footing's base, so the front of the wall is toward -x.

- **Sliding** moves the wall straight forward.
- **Overturning** turns it forward about the toe's bottom edge.
- **Bearing** sinks the toe: the wall turns forward about the heel's
  bottom edge and settles, while the soil heaves in front.
- **A global slip** turns the wall and its soil about the slip circle's
  center.

The stem's own failures hinge the stem forward at its base.
`RigidMotion.apply` moves a point. A drawing scales the motion up so the
eye can follow it; the motions are not predictions of displacement.

**Colors.** `utilization_color` maps a demand-to-capacity ratio to a color
that reads at a glance: greens below 0.7, yellow to orange from 0.7 to
1.0, red past 1.0 and dark red past 2.0. The stops are linear sRGB.
"""

from std.math import cos, isfinite, sin
from extensions.geotech.kinds import (
    BEARING,
    FailureMode,
    GLOBAL_SLIP,
    OVERTURNING,
    SLIDING,
    STEM_FLEXURE,
    STEM_SHEAR,
)
from extensions.geotech.wall import CantileverWall
from units.si import Angle64, Length64


@fieldwise_init
struct RigidMotion(ImplicitlyCopyable):
    """A turn about a pivot, then a shift, in a section's plane."""

    var pivot_x: Length64
    var pivot_y: Length64
    # Counterclockwise, with x toward the heel and y up: a forward tip.
    var turn: Angle64
    var shift_x: Length64
    var shift_y: Length64

    def apply(self, x: Length64, y: Length64) -> Tuple[Length64, Length64]:
        """Return where a point of the section moves to.

        Args:
            x: The point's distance from the toe edge.
            y: Its height above the footing's base.

        Returns:
            The moved point.
        """
        var dx = x.value - self.pivot_x.value
        var dy = y.value - self.pivot_y.value
        var c = cos(self.turn.value)
        var s = sin(self.turn.value)
        return (
            Length64(self.pivot_x.value + c * dx - s * dy + self.shift_x.value),
            Length64(self.pivot_y.value + s * dx + c * dy + self.shift_y.value),
        )


def still() -> RigidMotion:
    """Return no motion.

    Returns:
        The identity.
    """
    return RigidMotion(
        Length64(0), Length64(0), Angle64(0), Length64(0), Length64(0)
    )


def sliding(distance: Length64) -> RigidMotion:
    """Return the wall sliding forward.

    Args:
        distance: How far it slides.

    Returns:
        A shift toward -x.
    """
    return RigidMotion(
        Length64(0), Length64(0), Angle64(0), -distance, Length64(0)
    )


def overturning(wall: CantileverWall, turn: Angle64) -> RigidMotion:
    """Return the wall tipping forward over its toe.

    The pivot is the bottom of the key if there is one, else the toe's
    bottom edge.

    Args:
        wall: The section.
        turn: How far it tips.

    Returns:
        A turn about the toe.
    """
    return RigidMotion(
        Length64(0), -wall.key_depth, turn, Length64(0), Length64(0)
    )


def bearing(
    wall: CantileverWall, turn: Angle64, settlement: Length64
) -> RigidMotion:
    """Return the toe punching into the soil.

    Args:
        wall: The section.
        turn: How far the wall tips forward about its heel edge.
        settlement: How far the heel edge settles as well.

    Returns:
        A turn about the heel edge, then a drop.
    """
    return RigidMotion(wall.width, Length64(0), turn, Length64(0), -settlement)


def slip(center_x: Length64, center_y: Length64, turn: Angle64) -> RigidMotion:
    """Return a turn about a slip circle's center.

    A positive turn carries the mass under the center forward, toward
    -x: for a center above the wall that is a clockwise turn.

    Args:
        center_x: The center's distance from the toe edge.
        center_y: The center's height above the footing's base.
        turn: How far the mass turns.

    Returns:
        A turn about the center.
    """
    return RigidMotion(center_x, center_y, -turn, Length64(0), Length64(0))


def stem_hinge(wall: CantileverWall, turn: Angle64) -> RigidMotion:
    """Return the stem hinging forward at its base.

    Apply it to the stem only.

    Args:
        wall: The section.
        turn: How far the stem turns.

    Returns:
        A turn about the front of the stem's base.
    """
    return RigidMotion(wall.toe, wall.footing, turn, Length64(0), Length64(0))


def failure_motion(
    mode: FailureMode, wall: CantileverWall, progress: Float64, scale: Length64
) raises -> RigidMotion:
    """Return a failure mode's motion at a point of its progress.

    Args:
        mode: The mode; a global slip turns about a center above the footing.
        wall: The section.
        progress: From 0, at rest, to 1, fully failed.
        scale: A length that sets how large the motion is drawn: the
            slide distance, the settlement, and, over the wall's height,
            the turn.

    Returns:
        The motion.

    Raises:
        Error: If the mode is not valid or progress is not finite.
    """
    if not mode.is_valid():
        raise Error("A failure mode is not valid")
    if not isfinite(progress):
        raise Error("A failure progress must be finite")
    var t = max(0.0, min(1.0, progress))
    var h = wall.height.value
    var turn = Angle64(t * scale.value / h)
    if mode == SLIDING:
        return sliding(Length64(t * scale.value))
    if mode == OVERTURNING:
        return overturning(wall, turn)
    if mode == BEARING:
        return bearing(wall, turn, Length64(0.4 * t * scale.value))
    if mode == GLOBAL_SLIP:
        return slip(
            Length64(wall.width.value * 0.3),
            Length64(h * 1.3),
            Angle64(t * scale.value / (h * 1.6)),
        )
    if mode == STEM_FLEXURE or mode == STEM_SHEAR:
        return stem_hinge(wall, turn)
    return still()


def utilization_color(ratio: Float64) -> Tuple[Float64, Float64, Float64]:
    """Return a color for a demand-to-capacity ratio.

    Args:
        ratio: The ratio; above one fails.

    Returns:
        The color as linear red, green and blue from zero to one. A ratio
        that is not finite is the color of 2.0 and past.
    """
    var stops: List[Tuple[Float64, Float64, Float64, Float64]] = [
        (0.0, 0.010, 0.230, 0.050),
        (0.5, 0.090, 0.450, 0.040),
        (0.7, 0.520, 0.640, 0.010),
        (0.85, 0.950, 0.660, 0.000),
        (1.0, 1.000, 0.250, 0.000),
        (1.3, 0.750, 0.010, 0.005),
        (2.0, 0.300, 0.000, 0.040),
    ]
    var r = ratio
    if not isfinite(r) or r >= 2.0:
        r = 2.0
    r = max(r, 0.0)
    # The ratio is now from 0 to 2.0, the last stop, so the last span
    # holds any ratio the spans before it do not. Seven stops make the
    # loop over the first five spans always run.
    var last = len(stops) - 2
    for i in range(last):  # pragma: no branch
        if r <= stops[i + 1][0]:
            return _between(stops[i], stops[i + 1], r)
    return _between(stops[last], stops[last + 1], r)


def _between(
    a: Tuple[Float64, Float64, Float64, Float64],
    b: Tuple[Float64, Float64, Float64, Float64],
    r: Float64,
) -> Tuple[Float64, Float64, Float64]:
    """Return the color at a ratio between two stops."""
    var t = (r - a[0]) / (b[0] - a[0])
    return (
        a[1] + t * (b[1] - a[1]),
        a[2] + t * (b[2] - a[2]),
        a[3] + t * (b[3] - a[3]),
    )
