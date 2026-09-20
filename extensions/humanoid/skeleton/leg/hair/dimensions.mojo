# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named hair groups of one leg, as short implicit shafts.

Thigh hair sits on the anterior and lateral thigh. Calf hair sits on
the posterior and lateral calf. Physical shaft diameter follows
published site means. The mesh uses a separate diagrammatic radius so
the current rasterizer can show the shafts.

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
from extensions.humanoid.skeleton.leg.skin.dimensions import SkinField
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
        var lat = Float32(1)
        if dimensions.side == LEFT:
            lat = Float32(-1)
        var skin = SkinField(dimensions)
        var length = Float32(0.010)
        self.radius = Float32(0.0000145)
        self.k = Float32(0.5) * self.radius
        self.epsilon = Float32(0.5) * self.radius
        if part == THIGH_HAIR:
            self.a0 = _root(
                skin, dimensions.hip, dimensions.femur_mid, 0.40, lat, 0.000, S
            )
            self.a1 = _root(
                skin, dimensions.hip, dimensions.femur_mid, 0.46, lat, 0.004, S
            )
            self.a2 = _root(
                skin, dimensions.hip, dimensions.femur_mid, 0.52, lat, 0.008, S
            )
            self.a3 = _root(
                skin, dimensions.hip, dimensions.femur_mid, 0.58, lat, 0.012, S
            )
            self.a4 = _root(
                skin, dimensions.hip, dimensions.femur_mid, 0.64, lat, 0.016, S
            )
            self.a5 = _root(
                skin, dimensions.hip, dimensions.femur_mid, 0.70, lat, 0.020, S
            )
            self.b0 = self.a0 + Vector3(lat * 0.10, -0.92, 0.24) * length
            self.b1 = self.a1 + Vector3(lat * 0.18, -0.90, 0.28) * length
            self.b2 = self.a2 + Vector3(lat * 0.08, -0.94, 0.20) * length
            self.b3 = self.a3 + Vector3(lat * 0.22, -0.88, 0.30) * length
            self.b4 = self.a4 + Vector3(lat * 0.14, -0.92, 0.26) * length
            self.b5 = self.a5 + Vector3(lat * 0.10, -0.94, 0.22) * length
        else:
            self.radius = Float32(0.000021)
            self.k = Float32(0.5) * self.radius
            self.epsilon = Float32(0.5) * self.radius
            self.a0 = _calf_root(
                skin,
                dimensions.lat_condyle,
                dimensions.tibia_mid,
                0.32,
                lat,
                0.000,
                S,
            )
            self.a1 = _calf_root(
                skin,
                dimensions.lat_condyle,
                dimensions.tibia_mid,
                0.39,
                lat,
                0.003,
                S,
            )
            self.a2 = _calf_root(
                skin,
                dimensions.lat_condyle,
                dimensions.tibia_mid,
                0.46,
                lat,
                0.006,
                S,
            )
            self.a3 = _calf_root(
                skin,
                dimensions.lat_condyle,
                dimensions.tibia_mid,
                0.53,
                lat,
                0.010,
                S,
            )
            self.a4 = _calf_root(
                skin,
                dimensions.lat_condyle,
                dimensions.tibia_mid,
                0.60,
                lat,
                0.013,
                S,
            )
            self.a5 = _calf_root(
                skin,
                dimensions.lat_condyle,
                dimensions.tibia_mid,
                0.67,
                lat,
                0.016,
                S,
            )
            self.b0 = self.a0 + Vector3(lat * 0.10, -0.92, -0.24) * length
            self.b1 = self.a1 + Vector3(lat * 0.18, -0.90, -0.28) * length
            self.b2 = self.a2 + Vector3(lat * 0.08, -0.94, -0.20) * length
            self.b3 = self.a3 + Vector3(lat * 0.22, -0.88, -0.30) * length
            self.b4 = self.a4 + Vector3(lat * 0.14, -0.92, -0.26) * length
            self.b5 = self.a5 + Vector3(lat * 0.10, -0.94, -0.22) * length
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


def _display_hair_field(
    dimensions: MuscleDimensions, part: HairPart
) raises -> HairField:
    """Return the same shafts with a diagrammatic mesh radius."""
    var field = HairField(dimensions, part)
    var S = dimensions.stature.value
    field.radius = 0.0015 * S
    field.k = 0.00020 * S
    field.epsilon = Float32(0.25) * field.radius
    var box = empty_bounds()
    box.include_sphere(field.a0, field.radius)
    box.include_sphere(field.a1, field.radius)
    box.include_sphere(field.a2, field.radius)
    box.include_sphere(field.a3, field.radius)
    box.include_sphere(field.a4, field.radius)
    box.include_sphere(field.a5, field.radius)
    box.include_sphere(field.b0, field.radius)
    box.include_sphere(field.b1, field.radius)
    box.include_sphere(field.b2, field.radius)
    box.include_sphere(field.b3, field.radius)
    box.include_sphere(field.b4, field.radius)
    box.include_sphere(field.b5, field.radius)
    var padded = box.padded(0.006 + field.radius)
    field.low = padded.low
    field.high = padded.high
    return field


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
    skin: SkinField,
    a: Vector3,
    b: Vector3,
    t: Float32,
    lat: Float32,
    lateral: Float32,
    S: Float32,
) -> Vector3:
    """Project a thigh hair root onto the actual anterior skin surface."""
    var inside = mix_point(a, b, t) + Vector3(lat * lateral * S, 0, 0)
    return _surface_root(skin, inside, Vector3(lat * 0.12, 0, 1), S)


def _calf_root(
    skin: SkinField,
    a: Vector3,
    b: Vector3,
    t: Float32,
    lat: Float32,
    lateral: Float32,
    S: Float32,
) -> Vector3:
    """Project a calf hair root onto the actual posterior skin surface."""
    var inside = mix_point(a, b, t) + Vector3(lat * lateral * S, 0, 0)
    return _surface_root(skin, inside, Vector3(lat * 0.10, 0, -1), S)


def _surface_root(
    skin: SkinField, inside: Vector3, outward: Vector3, S: Float32
) -> Vector3:
    """Return where an outward ray leaves the anatomy-derived skin."""
    var direction = outward
    direction.normalize()
    var low = inside
    var high = inside + direction * (0.16 * S)
    for _ in range(18):
        var middle = (low + high) * Float32(0.5)
        if skin.distance(middle) < 0:
            low = middle
        else:
            high = middle
    return high
