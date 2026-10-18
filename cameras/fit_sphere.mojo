# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Place a camera so that a sphere fills its view.

The three.js splat example frames a scan this way. It takes the scan's
bounding sphere and finds the distance at which the sphere just fits the
field of view. It then puts the camera on a chosen side of the sphere at 1.15
times that distance, and sets the near and far planes from the same distance.
`fit_distance` is the first step and `fit_sphere` is all of them.

The distance is `radius / sin(fov / 2)`, which holds for a sphere in the
middle of a square view. A view that is wider than it is tall sees the sphere
fit with room at the sides. A view that is taller than it is wide cuts the
sphere at the sides. three.js does the same.
"""

from cameras.perspective_camera import PerspectiveCamera
from math.vector3 import Vector3
from std.math import isfinite, max, pi, sin
from units.si import Angle, Length, METER, RADIAN

comptime FIT_MARGIN = Float32(1.15)
"""The three.js example's margin: the camera stands 15 % beyond a tight fit."""
comptime NEAR_SHARE = Float32(0.001)
"""The near plane is this share of the tight-fit distance, as the example sets it."""
comptime NEAREST = Float32(0.001)
"""The least that the near plane is, in meters."""
comptime FAR_SHARE = Float32(10)
"""The far plane is this many times the tight-fit distance."""
comptime FARTHEST = Float32(10)
"""The least that the far plane is, in meters."""


def fit_distance(radius: Length, fov: Angle) raises -> Length:
    """Return how far a camera must be for a sphere to just fit its view.

    Args:
        radius: The sphere's radius. It must be positive and finite.
        fov: The camera's vertical field of view. It must be between zero and
            half a turn.

    Returns:
        The distance from the sphere's center to the camera.

    Raises:
        Error: If the radius is not positive and finite, or the field of
            view is not between zero and pi.
    """
    if not (isfinite(radius.value) and radius.value > 0):
        raise Error("The sphere's radius must be positive and finite")
    var angle = fov.to(RADIAN)
    if not (isfinite(angle) and angle > 0 and angle < Float32(pi)):
        raise Error("The field of view must be between zero and pi")
    return Length(radius.value / sin(angle / 2), METER)


def fit_sphere(
    mut camera: PerspectiveCamera,
    center: Vector3,
    radius: Length,
    direction: Vector3,
    margin: Float32 = FIT_MARGIN,
) raises -> Length:
    """Place a camera on one side of a sphere, looking at its center.

    The near plane becomes a thousandth of the tight-fit distance, but at
    least `NEAREST`. The far plane becomes ten times the distance, but at
    least `FARTHEST`. The margin does not change them.

    Args:
        camera: The camera to place. Its field of view sets the distance.
        center: The sphere's center.
        radius: The sphere's radius. It must be positive and finite.
        direction: Which way from the center the camera stands. Its length is
            not used, but it must not be zero.
        margin: How many times the tight-fit distance the camera stands away.
            It must be positive and finite.

    Returns:
        The distance from the center to the camera.

    Raises:
        Error: If the radius or the field of view is refused by
            `fit_distance`, the direction is zero or not finite, or the
            margin is not positive and finite. The camera is not changed.
    """
    var tight = fit_distance(radius, camera.fov)
    if not (isfinite(margin) and margin > 0):
        raise Error("The margin must be positive and finite")
    var side = direction
    var reach = side.length()
    if not (isfinite(reach) and reach > 0):
        raise Error("The direction must be finite and not zero")
    side.normalize()
    var distance = Length(tight.value * margin, METER)
    camera.place(center + side * distance.value, center)
    camera.near = Length(max(tight.value * NEAR_SHARE, NEAREST), METER)
    camera.far = Length(max(tight.value * FAR_SHARE, FARTHEST), METER)
    return distance
