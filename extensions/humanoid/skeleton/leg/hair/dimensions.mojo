# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named hair groups of one leg, as short implicit shafts.

Thigh hair sits on the anterior and lateral thigh. Calf hair sits on
the posterior and lateral calf. Shaft length and radius are authored
ratios of stature. They are template parameters. They are thicker than
a live hair so the isosurface can hold them.

The solids live in the leg frame. The origin is the tibiofemoral joint
line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var dims = muscle_dimensions(person)
    var d = hair_distance(dims, THIGH_HAIR, Vector3(0.04, 0.2, 0.06))
"""

from extensions.humanoid.side import LEFT
from extensions.humanoid.skeleton.field import (
    DistanceField,
    empty_bounds,
    field_gradient,
    mix_point,
    sd_segment,
    smin,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import MuscleDimensions
from math.vector3 import Vector3


@fieldwise_init
struct HairPart(Equatable, ImplicitlyCopyable, Writable):
    """Which named hair group a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary that
    reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named hair group."""
        if self.value < 0:
            return False
        return self.value <= CALF_HAIR.value


comptime THIGH_HAIR = HairPart(0)
comptime CALF_HAIR = HairPart(1)


struct HairField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one `HairPart`."""

    var a0: Vector3
    var a1: Vector3
    var a2: Vector3
    var a3: Vector3
    var a4: Vector3
    var a5: Vector3
    var b0: Vector3
    var b1: Vector3
    var b2: Vector3
    var b3: Vector3
    var b4: Vector3
    var b5: Vector3
    var radius: Float32
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: MuscleDimensions, part: HairPart) raises:
        """Build one hair group from muscle landmarks.

        Args:
            dimensions: Landmarks shared with the muscles.
            part: A named hair group.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `part`
                is not named.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A hair part must be a named hair group")
        var S = dimensions.stature.value
        var scale = dimensions.scale
        var lat = Float32(1)
        if dimensions.side == LEFT:
            lat = Float32(-1)
        var length = 0.022 * S
        self.radius = 0.0032 * S
        self.k = 0.0018 * S
        self.epsilon = dimensions.epsilon
        if part == THIGH_HAIR:
            var standoff = 0.062 * S * scale
            self.a0 = _root(
                dimensions.hip, dimensions.femur_mid, 0.48, lat, standoff, S
            )
            self.a1 = _root(
                dimensions.hip, dimensions.femur_mid, 0.52, lat, standoff, S
            )
            self.a2 = _root(
                dimensions.hip, dimensions.femur_mid, 0.56, lat, standoff, S
            )
            self.a3 = _root(
                dimensions.hip, dimensions.femur_mid, 0.60, lat, standoff, S
            )
            self.a4 = _root(
                dimensions.hip, dimensions.femur_mid, 0.64, lat, standoff, S
            )
            self.a5 = _root(
                dimensions.hip, dimensions.femur_mid, 0.68, lat, standoff, S
            )
            self.b0 = self.a0 + Vector3(lat * 0.36, 0.08, 0.92) * length
            self.b1 = self.a1 + Vector3(lat * 0.50, 0.04, 0.86) * length
            self.b2 = self.a2 + Vector3(lat * 0.22, 0.10, 0.96) * length
            self.b3 = self.a3 + Vector3(lat * 0.60, 0.02, 0.80) * length
            self.b4 = self.a4 + Vector3(lat * 0.40, -0.04, 0.90) * length
            self.b5 = self.a5 + Vector3(lat * 0.30, -0.08, 0.94) * length
        else:
            var standoff = 0.054 * S * scale
            self.a0 = _calf_root(
                dimensions.lat_condyle,
                dimensions.tibia_mid,
                0.36,
                lat,
                standoff,
                S,
            )
            self.a1 = _calf_root(
                dimensions.lat_condyle,
                dimensions.tibia_mid,
                0.42,
                lat,
                standoff,
                S,
            )
            self.a2 = _calf_root(
                dimensions.lat_condyle,
                dimensions.tibia_mid,
                0.48,
                lat,
                standoff,
                S,
            )
            self.a3 = _calf_root(
                dimensions.lat_condyle,
                dimensions.tibia_mid,
                0.54,
                lat,
                standoff,
                S,
            )
            self.a4 = _calf_root(
                dimensions.lat_condyle,
                dimensions.tibia_mid,
                0.60,
                lat,
                standoff,
                S,
            )
            self.a5 = _calf_root(
                dimensions.lat_condyle,
                dimensions.tibia_mid,
                0.66,
                lat,
                standoff,
                S,
            )
            self.b0 = self.a0 + Vector3(lat * 0.28, -0.06, -0.96) * length
            self.b1 = self.a1 + Vector3(lat * 0.40, -0.04, -0.90) * length
            self.b2 = self.a2 + Vector3(lat * 0.18, -0.08, -0.98) * length
            self.b3 = self.a3 + Vector3(lat * 0.50, -0.02, -0.86) * length
            self.b4 = self.a4 + Vector3(lat * 0.34, -0.10, -0.92) * length
            self.b5 = self.a5 + Vector3(lat * 0.22, -0.06, -0.96) * length
        var box = empty_bounds()
        box.include_sphere(self.a0, self.radius)
        box.include_sphere(self.a1, self.radius)
        box.include_sphere(self.a2, self.radius)
        box.include_sphere(self.a3, self.radius)
        box.include_sphere(self.a4, self.radius)
        box.include_sphere(self.a5, self.radius)
        box.include_sphere(self.b0, self.radius)
        box.include_sphere(self.b1, self.radius)
        box.include_sphere(self.b2, self.radius)
        box.include_sphere(self.b3, self.radius)
        box.include_sphere(self.b4, self.radius)
        box.include_sphere(self.b5, self.radius)
        var padded = box.padded(0.006 + self.radius)
        self.low = padded.low
        self.high = padded.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the shafts, in meters.

        Negative is inside. Zero is the surface.
        """
        var d = sd_segment(point, self.a0, self.b0, self.radius, self.radius)
        d = smin(
            d,
            sd_segment(point, self.a1, self.b1, self.radius, self.radius),
            self.k,
        )
        d = smin(
            d,
            sd_segment(point, self.a2, self.b2, self.radius, self.radius),
            self.k,
        )
        d = smin(
            d,
            sd_segment(point, self.a3, self.b3, self.radius, self.radius),
            self.k,
        )
        d = smin(
            d,
            sd_segment(point, self.a4, self.b4, self.radius, self.radius),
            self.k,
        )
        return smin(
            d,
            sd_segment(point, self.a5, self.b5, self.radius, self.radius),
            self.k,
        )

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def hair_distance(
    dimensions: MuscleDimensions, part: HairPart, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        part: Which solid to sample.
        point: A point in the leg frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return HairField(dimensions, part).distance(point)


def hair_part_label(part: HairPart) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A hair part.

    Returns:
        A short English name, or `"hair"` when `part` is not named.
    """
    if part == THIGH_HAIR:
        return "thigh hair"
    if part == CALF_HAIR:
        return "calf hair"
    return "hair"


def named_hair_parts() -> List[HairPart]:
    """Return every named hair group in a stable order.

    Returns:
        Thigh hair and calf hair.
    """
    var parts = List[HairPart]()
    parts.append(THIGH_HAIR)
    parts.append(CALF_HAIR)
    return parts^


def _root(
    a: Vector3,
    b: Vector3,
    t: Float32,
    lat: Float32,
    stand_off: Float32,
    S: Float32,
) -> Vector3:
    """Return a thigh hair root anterior and slightly lateral of the bone."""
    var along = mix_point(a, b, t)
    return along + Vector3(lat * 0.018 * S, 0, stand_off)


def _calf_root(
    a: Vector3,
    b: Vector3,
    t: Float32,
    lat: Float32,
    stand_off: Float32,
    S: Float32,
) -> Vector3:
    """Return a calf hair root posterior and slightly lateral of the bone."""
    var along = mix_point(a, b, t)
    return along + Vector3(lat * 0.014 * S, 0, -stand_off)
