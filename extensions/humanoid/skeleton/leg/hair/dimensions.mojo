# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named hair groups of one leg, as short implicit shafts.

Thigh roots span hip to knee. Calf roots span knee to ankle. Six
circumferential directions prevent either group from becoming one
sample strip. Physical shaft diameter follows published site means.
The mesh uses a separate diagrammatic radius for visibility.

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
        var knee = mix_point(
            dimensions.med_condyle, dimensions.lat_condyle, 0.50
        )
        var ankle = mix_point(dimensions.med_mal, dimensions.lat_mal, 0.50)
        var d0 = Vector3(0, 0, 1)
        var d1 = Vector3(lat * 0.65, 0, 0.75)
        var d2 = Vector3(lat, 0, 0.15)
        var d3 = Vector3(lat * 0.65, 0, -0.75)
        var d4 = Vector3(0, 0, -1)
        var d5 = Vector3(-lat * 0.65, 0, 0.75)
        self.radius = Float32(0.0000145)
        self.k = Float32(0.5) * self.radius
        self.epsilon = Float32(0.5) * self.radius
        if part == THIGH_HAIR:
            self.a0 = _root(skin, dimensions.hip, knee, 0.12, d0, S)
            self.a1 = _root(skin, dimensions.hip, knee, 0.28, d1, S)
            self.a2 = _root(skin, dimensions.hip, knee, 0.44, d2, S)
            self.a3 = _root(skin, dimensions.hip, knee, 0.60, d3, S)
            self.a4 = _root(skin, dimensions.hip, knee, 0.76, d4, S)
            self.a5 = _root(skin, dimensions.hip, knee, 0.88, d5, S)
        else:
            self.radius = Float32(0.000021)
            self.k = Float32(0.5) * self.radius
            self.epsilon = Float32(0.5) * self.radius
            self.a0 = _root(skin, knee, ankle, 0.12, d0, S)
            self.a1 = _root(skin, knee, ankle, 0.28, d1, S)
            self.a2 = _root(skin, knee, ankle, 0.44, d2, S)
            self.a3 = _root(skin, knee, ankle, 0.60, d3, S)
            self.a4 = _root(skin, knee, ankle, 0.76, d4, S)
            self.a5 = _root(skin, knee, ankle, 0.88, d5, S)
        self.b0 = _tip(self.a0, d0, length)
        self.b1 = _tip(self.a1, d1, length)
        self.b2 = _tip(self.a2, d2, length)
        self.b3 = _tip(self.a3, d3, length)
        self.b4 = _tip(self.a4, d4, length)
        self.b5 = _tip(self.a5, d5, length)
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
    outward: Vector3,
    S: Float32,
) -> Vector3:
    """Project a representative hair root onto the actual skin."""
    return _surface_root(skin, mix_point(a, b, t), outward, S)


def _tip(root: Vector3, outward: Vector3, length: Float32) -> Vector3:
    """Lay one hair distally with a small outward component."""
    var direction = Vector3(
        Float32(0.18) * outward.x,
        Float32(-0.94),
        Float32(0.18) * outward.z,
    )
    direction.normalize()
    return root + direction * length


def _surface_root(
    skin: SkinField, inside: Vector3, outward: Vector3, S: Float32
) -> Vector3:
    """Return where an outward ray leaves the anatomy-derived skin."""
    var direction = outward
    direction.normalize()
    var low = inside
    var high = inside + direction * (0.16 * S)
    for _ in range(18):  # pragma: no branch
        var middle = (low + high) * Float32(0.5)
        if skin.distance(middle) < 0:
            low = middle
        else:
            high = middle
    return high
