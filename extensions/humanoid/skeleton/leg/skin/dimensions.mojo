# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Skin envelope of one leg, as one implicit solid in the leg frame.

The envelope is a stocking around the glute, thigh, knee and calf.
Radii are authored ratios of stature, then scaled by athleticism so a
toned limb is thicker. They are template parameters.

The solid lives in the leg frame. The origin is the tibiofemoral joint
line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var dims = muscle_dimensions(person)
    var d = skin_distance(dims, Vector3(0, 0.2, 0.08))
"""

from extensions.humanoid.side import LEFT
from extensions.humanoid.skeleton.field import (
    DistanceField,
    empty_bounds,
    field_gradient,
    mix_point,
    sd_ellipse_segment,
    smin,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import MuscleDimensions
from math.vector3 import Vector3


struct SkinField(DistanceField, ImplicitlyCopyable):
    """The implicit stocking around one leg."""

    var g0: Vector3
    var g1: Vector3
    var t0: Vector3
    var t1: Vector3
    var t2: Vector3
    var c0: Vector3
    var c1: Vector3
    var c2: Vector3
    var gr0: Float32
    var gr1: Float32
    var tr0: Float32
    var tr1: Float32
    var tr2: Float32
    var cr0: Float32
    var cr1: Float32
    var cr2: Float32
    var gd0: Float32
    var gd1: Float32
    var td0: Float32
    var td1: Float32
    var td2: Float32
    var cd0: Float32
    var cd1: Float32
    var cd2: Float32
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: MuscleDimensions) raises:
        """Build the skin envelope from muscle landmarks.

        Args:
            dimensions: Landmarks shared with the muscles.

        Raises:
            Error: If `dimensions.validate` refuses the copy.
        """
        dimensions.validate()
        var S = dimensions.stature.value
        var scale = dimensions.scale
        var lat = Float32(1)
        if dimensions.side == LEFT:
            lat = Float32(-1)
        self.g0 = dimensions.iliac + Vector3(0, -0.008 * S, -0.008 * S)
        self.g1 = dimensions.hip + Vector3(0, -0.040 * S, -0.028 * S)
        self.t0 = dimensions.hip + Vector3(lat * 0.004 * S, -0.010 * S, 0)
        self.t1 = dimensions.femur_mid + Vector3(0, 0, 0.006 * S)
        self.t2 = mix_point(dimensions.patella, dimensions.tuberosity, 0.20)
        self.c0 = dimensions.lat_condyle + Vector3(0, -0.012 * S, -0.004 * S)
        self.c1 = dimensions.tibia_mid + Vector3(0, 0, -0.008 * S)
        self.c2 = mix_point(dimensions.med_mal, dimensions.lat_mal, 0.50)
        self.gr0 = 0.038 * S * scale
        self.gr1 = 0.048 * S * scale
        self.tr0 = 0.046 * S * scale
        self.tr1 = 0.052 * S * scale
        self.tr2 = 0.036 * S * scale
        self.cr0 = 0.038 * S * scale
        self.cr1 = 0.042 * S * scale
        self.cr2 = 0.024 * S * scale
        self.gd0 = 0.72 * self.gr0
        self.gd1 = 0.78 * self.gr1
        self.td0 = 0.82 * self.tr0
        self.td1 = 0.86 * self.tr1
        self.td2 = 0.80 * self.tr2
        self.cd0 = 0.84 * self.cr0
        self.cd1 = 0.88 * self.cr1
        self.cd2 = 0.78 * self.cr2
        self.k = 0.018 * S
        self.epsilon = dimensions.epsilon
        var box = empty_bounds()
        box.include_sphere(self.g0, self.gr0)
        box.include_sphere(self.g1, self.gr1)
        box.include_sphere(self.t0, self.tr0)
        box.include_sphere(self.t1, self.tr1)
        box.include_sphere(self.t2, self.tr2)
        box.include_sphere(self.c0, self.cr0)
        box.include_sphere(self.c1, self.cr1)
        box.include_sphere(self.c2, self.cr2)
        var padded = box.padded(0.010 + self.tr1)
        self.low = padded.low
        self.high = padded.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the envelope, in meters.

        Negative is inside. Zero is the surface.
        """
        var ml = Vector3(1, 0, 0)
        var d = sd_ellipse_segment(
            point,
            self.g0,
            self.g1,
            self.gr0,
            self.gd0,
            self.gr1,
            self.gd1,
            ml,
        )
        d = smin(
            d,
            sd_ellipse_segment(
                point,
                self.t0,
                self.t1,
                self.tr0,
                self.td0,
                self.tr1,
                self.td1,
                ml,
            ),
            self.k,
        )
        d = smin(
            d,
            sd_ellipse_segment(
                point,
                self.t1,
                self.t2,
                self.tr1,
                self.td1,
                self.tr2,
                self.td2,
                ml,
            ),
            self.k,
        )
        d = smin(
            d,
            sd_ellipse_segment(
                point,
                self.c0,
                self.c1,
                self.cr0,
                self.cd0,
                self.cr1,
                self.cd1,
                ml,
            ),
            self.k,
        )
        return smin(
            d,
            sd_ellipse_segment(
                point,
                self.c1,
                self.c2,
                self.cr1,
                self.cd1,
                self.cr2,
                self.cd2,
                ml,
            ),
            self.k,
        )

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def skin_distance(
    dimensions: MuscleDimensions, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside the skin envelope, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        point: A point in the leg frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    return SkinField(dimensions).distance(point)
