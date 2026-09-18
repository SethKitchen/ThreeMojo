# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A 2D vector, ported from three.js `src/math/Vector2.js`."""

from std.math import sqrt


@fieldwise_init
struct Vector2(ImplicitlyCopyable):
    """A point or direction in 2D space.

    The members are `Vector3`'s members, in two dimensions and for the same
    reasons: the mutating ones change the vector in place as three.js's do,
    and the operators spell `b - a` the way a value type lets you.

    The curves are what asked for them. A Bezier is a weighted sum of its
    control points, and writing that sum component by component hid the
    arithmetic behind twice as much text as the formula has.
    """

    var x: Float32
    var y: Float32

    def dot(self, other: Self) -> Float32:
        """Return the dot product of `self` and `other`."""
        return self.x * other.x + self.y * other.y

    def cross(self, other: Self) -> Float32:
        """Return the z component of the cross product, which is the only
        one two vectors in a plane have. It is positive when `other` lies
        to the left of `self`, and zero when the two are parallel."""
        return self.x * other.y - self.y * other.x

    def length(self) -> Float32:
        """Return the Euclidean length of the vector."""
        return sqrt(self.dot(self))

    def add(mut self, other: Self):
        """Add `other` into `self`, component-wise."""
        self.x += other.x
        self.y += other.y

    def sub(mut self, other: Self):
        """Subtract `other` from `self`, component-wise."""
        self.x -= other.x
        self.y -= other.y

    def normalize(mut self):
        """Scale `self` to unit length, leaving a zero vector unchanged."""
        var magnitude = self.length()
        if magnitude > 0:
            self.x /= magnitude
            self.y /= magnitude

    def __add__(self, other: Self) -> Self:
        """Return the component-wise sum."""
        return Vector2(self.x + other.x, self.y + other.y)

    def __sub__(self, other: Self) -> Self:
        """Return the component-wise difference."""
        return Vector2(self.x - other.x, self.y - other.y)

    def __mul__(self, factor: Float32) -> Self:
        """Return this vector scaled by a number."""
        return Vector2(self.x * factor, self.y * factor)

    def __neg__(self) -> Self:
        """Return this vector pointing the other way."""
        return Vector2(-self.x, -self.y)
