# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A 3D vector, ported from three.js `src/math/Vector3.js`."""

from std.math import sqrt


@fieldwise_init
struct Vector3(ImplicitlyCopyable):
    """A point or direction in 3D space.

    Like three.js, the mutating methods change the vector in place rather than
    returning a new one. Unlike three.js, `ImplicitlyCopyable` means assignment
    makes a real copy, so there is no aliasing to worry about.
    """

    var x: Float32
    var y: Float32
    var z: Float32

    def dot(self, other: Self) -> Float32:
        """Return the dot product of `self` and `other`."""
        return self.x * other.x + self.y * other.y + self.z * other.z

    def length(self) -> Float32:
        """Return the Euclidean length of the vector."""
        return sqrt(self.dot(self))

    def add(mut self, other: Self):
        """Add `other` into `self`, component-wise."""
        self.x += other.x
        self.y += other.y
        self.z += other.z

    def cross(mut self, other: Self):
        """Set `self` to the cross product of `self` and `other`."""
        # Keep the original components until all outputs are calculated.
        var x = self.y * other.z - self.z * other.y
        var y = self.z * other.x - self.x * other.z
        var z = self.x * other.y - self.y * other.x
        self.x = x
        self.y = y
        self.z = z

    def normalize(mut self):
        """Scale `self` to unit length, leaving a zero vector unchanged."""
        var magnitude = self.length()
        if magnitude > 0:
            self.x /= magnitude
            self.y /= magnitude
            self.z /= magnitude
