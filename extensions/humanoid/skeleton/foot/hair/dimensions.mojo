# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named hair groups of one foot, as short implicit shafts.

Dorsal roots span the tarsus. Digital roots sit on the toes. Six shafts
keep either group from becoming one sample strip. Physical shaft
diameter is an authored adult mean. The mesh uses a separate
diagrammatic radius for visibility.

The solids live in the foot frame. The origin is the tibial plafond.
Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var dims = foot_muscle_dimensions(person)
    var d = foot_hair_distance(dims, DORSAL_HAIR, Vector3(0, 0.04, 0.02))
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
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    FootMuscleDimensions,
)
from extensions.humanoid.skeleton.foot.skin.dimensions import SkinField
from math.vector3 import Vector3


@fieldwise_init
struct FootHair(Equatable, ImplicitlyCopyable, Writable):
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
        return self.value <= DIGITAL_HAIR.value


comptime DORSAL_HAIR = FootHair(0)
comptime DIGITAL_HAIR = FootHair(1)


struct FootHairField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one `FootHair`."""

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

    def __init__(
        out self, dimensions: FootMuscleDimensions, part: FootHair
    ) raises:
        """Build one hair group from the fitted skin.

        Args:
            dimensions: Landmarks shared with the muscles.
            part: A named hair group.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `part`
                is not named.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A foot hair part must be a named hair group")
        var foot = dimensions.foot
        var S = foot.stature.value
        var lat = Float32(1)
        if dimensions.foot.side == LEFT:
            lat = Float32(-1)
        var skin = SkinField(dimensions)
        var length = Float32(0.008)
        self.radius = Float32(0.000018)
        self.k = Float32(0.5) * self.radius
        self.epsilon = Float32(0.5) * self.radius
        var d0 = Vector3(0, 1, 0.25)
        var d1 = Vector3(-lat * 0.45, 1, 0.10)
        var d2 = Vector3(lat * 0.45, 1, 0.10)
        var d3 = Vector3(-lat * 0.20, 1, -0.15)
        var d4 = Vector3(lat * 0.20, 1, 0.35)
        var d5 = Vector3(0, 1, -0.05)
        if part == DORSAL_HAIR:
            self.a0 = _root(skin, foot.talar_body, d0, S)
            self.a1 = _root(skin, foot.navicular, d1, S)
            self.a2 = _root(skin, foot.cuboid, d2, S)
            self.a3 = _root(skin, foot.medial_cuneiform, d3, S)
            self.a4 = _root(skin, foot.intermediate_cuneiform, d4, S)
            self.a5 = _root(
                skin, mix_point(foot.mt2_base, foot.mt2_head, 0.40), d5, S
            )
        else:
            length = Float32(0.005)
            self.radius = Float32(0.000014)
            self.k = Float32(0.5) * self.radius
            self.epsilon = Float32(0.5) * self.radius
            self.a0 = _root(
                skin, mix_point(foot.mt1_head, foot.hallux_ip, 0.45), d0, S
            )
            self.a1 = _root(skin, foot.toe2_pip, d1, S)
            self.a2 = _root(skin, foot.toe3_pip, d2, S)
            self.a3 = _root(skin, foot.toe4_pip, d3, S)
            self.a4 = _root(skin, foot.toe5_pip, d4, S)
            self.a5 = _root(
                skin, mix_point(foot.hallux_ip, foot.hallux_tip, 0.40), d5, S
            )
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


def foot_hair_distance(
    dimensions: FootMuscleDimensions, part: FootHair, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `foot_muscle_dimensions`.
        part: Which solid to sample.
        point: A point in the foot frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return FootHairField(dimensions, part).distance(point)


def foot_hair_part_label(part: FootHair) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A hair part.

    Returns:
        A short English name, or `"foot hair"` when `part` is not named.
    """
    if part == DORSAL_HAIR:
        return "dorsal hair"
    if part == DIGITAL_HAIR:
        return "digital hair"
    return "foot hair"


def named_foot_hair() -> List[FootHair]:
    """Return every named hair group in a stable order.

    Returns:
        Dorsal hair and digital hair.
    """
    var parts = List[FootHair]()
    parts.append(DORSAL_HAIR)
    parts.append(DIGITAL_HAIR)
    return parts^


def _root(
    skin: SkinField, inside: Vector3, outward: Vector3, S: Float32
) -> Vector3:
    """Project one hair root from an interior point onto the skin."""
    return _surface_root(skin, inside, outward, S)


def _tip(root: Vector3, outward: Vector3, length: Float32) -> Vector3:
    """Lay one hair distally with a small dorsal component."""
    var direction = Vector3(
        Float32(0.15) * outward.x,
        Float32(0.25),
        Float32(0.95),
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
