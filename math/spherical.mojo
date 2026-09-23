# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Spherical and cylindrical coordinates, from three.js
`src/math/Spherical.js` and `src/math/Cylindrical.js`.

A spherical point is a radius and two angles: `phi` down from +y and
`theta` about y from +z. A cylindrical point is a radius from the y axis,
an angle `theta` about y from +z, and a height. The angles are `Angle`s;
the radius and the height are bare `Float32` meters, as `Vector3`'s
components are.
"""

from math.vector3 import Vector3
from std.math import acos, atan2, cos, pi, sin, sqrt
from units.si import Angle, RADIAN

# How close to a pole `make_safe` lets `phi` go. three.js: `EPS`.
comptime POLE_MARGIN = Float32(1e-6)


@fieldwise_init
struct Spherical(ImplicitlyCopyable):
    """A radius, a polar angle and an azimuth."""

    var radius: Float32
    var phi: Angle
    var theta: Angle

    @staticmethod
    def from_vector3(vector: Vector3) -> Spherical:
        """Return a vector's spherical coordinates. three.js:
        `setFromVector3`.

        Args:
            vector: The point.

        Returns:
            Its radius and angles. The origin has both angles zero.
        """
        var radius = vector.length()
        if radius == 0:
            return Spherical(0, Angle(0.0, RADIAN), Angle(0.0, RADIAN))
        var ratio = max(Float32(-1), min(Float32(1), vector.y / radius))
        return Spherical(
            radius,
            Angle(acos(ratio), RADIAN),
            Angle(atan2(vector.x, vector.z), RADIAN),
        )

    def to_vector3(self) -> Vector3:
        """Return the point these coordinates name. three.js:
        `Vector3.setFromSpherical`.

        Returns:
            The point.
        """
        var phi = self.phi.to(RADIAN)
        var theta = self.theta.to(RADIAN)
        var along = sin(phi) * self.radius
        return Vector3(
            along * sin(theta), cos(phi) * self.radius, along * cos(theta)
        )

    def make_safe(mut self):
        """Keep `phi` a millionth of a radian away from each pole, where
        the azimuth is undefined."""
        var phi = self.phi.to(RADIAN)
        phi = max(POLE_MARGIN, min(Float32(pi) - POLE_MARGIN, phi))
        self.phi = Angle(phi, RADIAN)


@fieldwise_init
struct Cylindrical(ImplicitlyCopyable):
    """A radius from the y axis, an azimuth and a height."""

    var radius: Float32
    var theta: Angle
    var y: Float32

    @staticmethod
    def from_vector3(vector: Vector3) -> Cylindrical:
        """Return a vector's cylindrical coordinates. three.js:
        `setFromVector3`.

        Args:
            vector: The point.

        Returns:
            Its radius, azimuth and height.
        """
        return Cylindrical(
            sqrt(vector.x * vector.x + vector.z * vector.z),
            Angle(atan2(vector.x, vector.z), RADIAN),
            vector.y,
        )

    def to_vector3(self) -> Vector3:
        """Return the point these coordinates name. three.js:
        `Vector3.setFromCylindrical`.

        Returns:
            The point.
        """
        var theta = self.theta.to(RADIAN)
        return Vector3(
            self.radius * sin(theta), self.y, self.radius * cos(theta)
        )
