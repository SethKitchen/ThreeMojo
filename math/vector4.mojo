# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A 4D vector, ported from three.js `src/math/Vector4.js`.

The fourth component is what a `Matrix4` multiplies but a `Vector3` cannot
carry: a position has `w = 1`, a direction `w = 0`, and a point that has
been through a projection has whatever the matrix's bottom row made of it.
`Matrix4.transform_point` builds that `w`, divides by it and throws it
away, and `transform_w` hands it back on its own; `apply_matrix4` here is
the product in full, which is the form a clip-space coordinate has.

Everything else is `Vector3` with one more component. The mutating methods
change the vector in place, as three.js's do, and the operators return a
new one.
"""

from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.math import sqrt


@fieldwise_init
struct Vector4(ImplicitlyCopyable):
    """A point or direction in homogeneous coordinates."""

    var x: Float32
    var y: Float32
    var z: Float32
    var w: Float32

    def __init__(out self, *, of: Vector3, w: Float32 = 1.0):
        """Create a vector from a `Vector3` and a fourth component.

        Args:
            of: The first three components.
            w: The fourth. One for a position, zero for a direction.
        """
        self.x = of.x
        self.y = of.y
        self.z = of.z
        self.w = w

    def xyz(self) -> Vector3:
        """Return the first three components, the fourth dropped."""
        return Vector3(self.x, self.y, self.z)

    def dot(self, other: Self) -> Float32:
        """Return the dot product of `self` and `other`.

        Args:
            other: The other vector.

        Returns:
            The dot product, all four components in.
        """
        return (
            self.x * other.x
            + self.y * other.y
            + self.z * other.z
            + self.w * other.w
        )

    def length(self) -> Float32:
        """Return the Euclidean length of the vector, all four components
        in."""
        return sqrt(self.dot(self))

    def add(mut self, other: Self):
        """Add `other` into `self`, component-wise.

        Args:
            other: The vector to add.
        """
        self.x += other.x
        self.y += other.y
        self.z += other.z
        self.w += other.w

    def sub(mut self, other: Self):
        """Subtract `other` from `self`, component-wise.

        Args:
            other: The vector to subtract.
        """
        self.x -= other.x
        self.y -= other.y
        self.z -= other.z
        self.w -= other.w

    def normalize(mut self):
        """Scale `self` to unit length, leaving a zero vector unchanged."""
        var magnitude = self.length()
        if magnitude > 0:
            self.x /= magnitude
            self.y /= magnitude
            self.z /= magnitude
            self.w /= magnitude

    def apply_matrix4(mut self, matrix: Matrix4):
        """Multiply `self` by `matrix`, three.js's `applyMatrix4`.

        The whole product, with nothing divided: a position that goes
        through a projection comes out with the clip-space `w` still in its
        fourth component, which is what `Matrix4.transform_point` divides
        by and `transform_w` reports.

        Args:
            matrix: The matrix to apply.
        """
        ref e = matrix.elements
        var x = self.x
        var y = self.y
        var z = self.z
        var w = self.w
        self.x = e[0] * x + e[4] * y + e[8] * z + e[12] * w
        self.y = e[1] * x + e[5] * y + e[9] * z + e[13] * w
        self.z = e[2] * x + e[6] * y + e[10] * z + e[14] * w
        self.w = e[3] * x + e[7] * y + e[11] * z + e[15] * w

    def __add__(self, other: Self) -> Self:
        """Return the component-wise sum.

        Args:
            other: The vector to add.

        Returns:
            A new vector.
        """
        return Vector4(
            self.x + other.x,
            self.y + other.y,
            self.z + other.z,
            self.w + other.w,
        )

    def __sub__(self, other: Self) -> Self:
        """Return the component-wise difference.

        Args:
            other: The vector to subtract.

        Returns:
            A new vector.
        """
        return Vector4(
            self.x - other.x,
            self.y - other.y,
            self.z - other.z,
            self.w - other.w,
        )

    def __mul__(self, factor: Float32) -> Self:
        """Return this vector scaled by a number.

        Args:
            factor: The scale.

        Returns:
            A new vector.
        """
        return Vector4(
            self.x * factor, self.y * factor, self.z * factor, self.w * factor
        )

    def __neg__(self) -> Self:
        """Return this vector pointing the other way."""
        return Vector4(-self.x, -self.y, -self.z, -self.w)
