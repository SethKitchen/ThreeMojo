# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Osteometric size of a patella, and the implicit solid that has that size.

The patella has no Trotter and Gleser line. Height, width and thickness
are authored sex-specific ratios of stature. They are template parameters.
They are not a cited osteometric table.

The solid is a triangular sesamoid: a proximal base, a distal apex, an
anterior convex face, and a posterior articular face with a vertical
ridge. The lateral facet is the larger of the two.

The bone's own frame is osteological. Plus y is proximal, plus x is
lateral, plus z is anterior, the origin is the centroid. A right patella
uses that frame. A left patella is the same points with x flipped.

`PatellaDimensions` is fieldwise-constructible. Editing a measurement
does not rebuild landmarks. Call `patella_dimensions` to resolve a
template. Call `validate` at every public consumer of an edited copy.
"""

from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.field import (
    DistanceField,
    check_spec,
    empty_bounds,
    field_gradient,
    finite_point,
    flip_x,
    positive_length,
    sd_ellipse_segment,
    sd_ellipsoid,
    sd_segment,
    smin,
)
from math.vector3 import Vector3
from units.si import Length

# Authored ratios of stature, adult male template.
comptime MALE_HEIGHT = Float32(0.0253)
comptime MALE_WIDTH = Float32(0.0248)
comptime MALE_THICK = Float32(0.0123)

# Authored adult female template ratios.
comptime FEMALE_HEIGHT = Float32(0.0240)
comptime FEMALE_WIDTH = Float32(0.0236)
comptime FEMALE_THICK = Float32(0.0118)

# Mediolateral hint for the tapered shield body.
comptime PATELLA_ML = Vector3(1, 0, 0)


@fieldwise_init
struct PatellaDimensions(ImplicitlyCopyable):
    """Measured size of one patella, and the landmarks a skeleton will bind.

    Positions are in meters in the bone's frame. Landmarks come from
    `patella_dimensions`. Editing a length does not move them.
    """

    var stature: Length
    var sex: Sex
    var side: BodySide
    var height: Length
    var width: Length
    var thickness: Length
    var apex: Vector3
    var base: Vector3
    var ridge: Vector3

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If sex or side is not valid, if a required length is
                not finite or not positive, or if a landmark is not finite.
        """
        check_spec(self.stature, self.sex, self.side, "patella")
        positive_length(self.height, "height", "patella")
        positive_length(self.width, "width", "patella")
        positive_length(self.thickness, "thickness", "patella")
        finite_point(self.apex, "apex", "patella")
        finite_point(self.base, "base", "patella")
        finite_point(self.ridge, "ridge", "patella")


struct PatellaField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one `PatellaDimensions`."""

    var body: Vector3
    var body_r: Vector3
    var apex: Vector3
    var apex_r: Vector3
    var base: Vector3
    var base_r: Vector3
    var medial: Vector3
    var medial_r: Vector3
    var lateral: Vector3
    var lateral_r: Vector3
    var ridge_a: Vector3
    var ridge_b: Vector3
    var ridge_r: Float32
    var r2: Float32
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: PatellaDimensions) raises:
        """Build the solid from dimensions that `validate` accepts.

        Args:
            dimensions: Size and landmarks.

        Raises:
            Error: If `dimensions.validate` refuses the copy.
        """
        dimensions.validate()
        var H = dimensions.height.value
        var W = dimensions.width.value
        var T = dimensions.thickness.value
        self.body = Vector3(0, 0.08 * H, 0.08 * T)
        self.body_r = Vector3(0.45 * W, 0.32 * H, 0.40 * T)
        self.apex = dimensions.apex
        self.apex_r = Vector3(0.16 * W, 0.10 * H, 0.20 * T)
        self.base = dimensions.base
        self.base_r = Vector3(0.42 * W, 0.12 * H, 0.30 * T)
        var lateral_sign = Float32(1)
        if dimensions.side == LEFT:
            lateral_sign = Float32(-1)
        self.lateral = Vector3(lateral_sign * 0.18 * W, 0.02 * H, -0.22 * T)
        self.lateral_r = Vector3(0.28 * W, 0.32 * H, 0.18 * T)
        self.medial = Vector3(-lateral_sign * 0.14 * W, 0.02 * H, -0.20 * T)
        self.medial_r = Vector3(0.22 * W, 0.28 * H, 0.16 * T)
        self.ridge_a = dimensions.ridge + Vector3(0, 0.22 * H, 0)
        self.ridge_b = dimensions.ridge + Vector3(0, -0.18 * H, 0)
        self.ridge_r = 0.07 * W
        self.r2 = 0.28 * T
        self.k = 0.12 * T
        self.epsilon = 0.004 * T
        var box = empty_bounds()
        box.include_ellipsoid(self.body, self.body_r)
        box.include_ellipsoid(self.apex, self.apex_r)
        box.include_ellipsoid(self.base, self.base_r)
        box.include_ellipsoid(self.medial, self.medial_r)
        box.include_ellipsoid(self.lateral, self.lateral_r)
        var padded = box.padded(0.12 * T + Float32(0.002))
        self.low = padded.low
        self.high = padded.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the patella, in meters.

        Negative is inside. Zero is the surface.
        """
        var d = sd_ellipse_segment(
            point,
            self.apex,
            self.base,
            self.apex_r.x,
            self.apex_r.z,
            self.base_r.x,
            self.base_r.z,
            PATELLA_ML,
        )
        d = smin(d, sd_ellipsoid(point, self.body, self.body_r), self.k)
        return smin(
            d,
            sd_segment(
                point, self.ridge_a, self.ridge_b, self.ridge_r, self.ridge_r
            ),
            self.k,
        )

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def patella_dimensions(
    stature: Length, sex: Sex, side: BodySide = RIGHT
) raises -> PatellaDimensions:
    """Return the size of a patella for an adult humanoid.

    Args:
        stature: Standing height. Must lie in 1.2 m through 2.5 m.
        sex: `MALE` or `FEMALE`.
        side: `RIGHT` or `LEFT`. A right patella is the default.

    Returns:
        Lengths and landmark positions in the bone's frame.

    Raises:
        Error: If `sex` or `side` is not valid, or stature is not finite
            or is outside the software range.
    """
    check_spec(stature, sex, side, "patella")

    var height_ratio: Float32
    var width_ratio: Float32
    var thick_ratio: Float32
    if sex == MALE:
        height_ratio = MALE_HEIGHT
        width_ratio = MALE_WIDTH
        thick_ratio = MALE_THICK
    else:
        height_ratio = FEMALE_HEIGHT
        width_ratio = FEMALE_WIDTH
        thick_ratio = FEMALE_THICK

    var H = height_ratio * stature.value
    var W = width_ratio * stature.value
    var T = thick_ratio * stature.value
    var apex = Vector3(0, -0.42 * H, 0.04 * T)
    var base = Vector3(0, 0.40 * H, 0.02 * T)
    var ridge = Vector3(0.04 * W, 0, -0.32 * T)
    if side == LEFT:
        apex = flip_x(apex)
        base = flip_x(base)
        ridge = flip_x(ridge)

    return PatellaDimensions(
        stature,
        sex,
        side,
        Length(H),
        Length(W),
        Length(T),
        apex,
        base,
        ridge,
    )


def patella_distance(
    dimensions: PatellaDimensions, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside the patella, in meters.

    Negative is inside. The surface `patella` meshes is the zero set.

    Args:
        dimensions: A patella already sized from stature and sex.
        point: A point in the bone's frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    return PatellaField(dimensions).distance(point)
