# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A 2D vector, ported from three.js `src/math/Vector2.js`."""

from math.matrix3 import Matrix3
from math.utils import SeededRandom
from math.vector3 import _js_round
from std.math import acos, atan2, ceil, cos, floor, pi, sin, sqrt, trunc
from units.si import Angle, RADIAN


@fieldwise_init
struct Vector2(Equatable, ImplicitlyCopyable):
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

    def __truediv__(self, divisor: Float32) -> Self:
        """Return this vector divided by a number, three.js's
        `divideScalar`: a multiply by the reciprocal, as there.

        Args:
            divisor: The number to divide by.

        Returns:
            The divided vector.
        """
        return self * (1 / divisor)

    def __eq__(self, other: Self) -> Bool:
        """Return True if both components are exactly equal, three.js's
        `equals`.

        Args:
            other: The vector to compare with.

        Returns:
            Whether the two are the same vector.
        """
        return self.x == other.x and self.y == other.y

    def __ne__(self, other: Self) -> Bool:
        """Return True if either component differs.

        Args:
            other: The vector to compare with.

        Returns:
            Whether the two differ.
        """
        return not self == other

    def get_component(self, index: Int) raises -> Float32:
        """Return one component by its index, three.js's `getComponent`.

        Args:
            index: 0 for x, 1 for y.

        Returns:
            The component.

        Raises:
            Error: If the index is not 0 or 1.
        """
        if index == 0:
            return self.x
        if index == 1:
            return self.y
        raise Error("A Vector2 component index is 0 or 1")

    def set_component(mut self, index: Int, value: Float32) raises:
        """Set one component by its index, three.js's `setComponent`.

        Args:
            index: 0 for x, 1 for y.
            value: The new component.

        Raises:
            Error: If the index is not 0 or 1.
        """
        if index == 0:
            self.x = value
        elif index == 1:
            self.y = value
        else:
            raise Error("A Vector2 component index is 0 or 1")

    def negate(mut self):
        """Point this vector the other way, in place."""
        self = -self

    def add_scaled_vector(mut self, other: Self, factor: Float32):
        """Add `other` times `factor` into this vector, three.js's
        `addScaledVector`.

        Args:
            other: The vector to add.
            factor: What to scale it by first.
        """
        self = self + other * factor

    def add_scalar(mut self, value: Float32):
        """Add one number to both components, three.js's `addScalar`.

        Args:
            value: The number to add.
        """
        self = Vector2(self.x + value, self.y + value)

    def sub_scalar(mut self, value: Float32):
        """Subtract one number from both components, three.js's
        `subScalar`.

        Args:
            value: The number to subtract.
        """
        self = Vector2(self.x - value, self.y - value)

    def length_sq(self) -> Float32:
        """Return the squared length, three.js's `lengthSq`.

        Returns:
            The dot product of this vector with itself.
        """
        return self.dot(self)

    def manhattan_length(self) -> Float32:
        """Return the sum of the absolute components, three.js's
        `manhattanLength`.

        Returns:
            `|x| + |y|`.
        """
        return abs(self.x) + abs(self.y)

    def set_length(mut self, length: Float32):
        """Scale this vector to `length`, three.js's `setLength`. A zero
        vector stays zero.

        Args:
            length: The new length.
        """
        self.normalize()
        self = self * length

    def angle(self) -> Angle:
        """Return the angle this vector makes with +x, three.js's `angle`.

        Returns:
            From zero up to a whole turn, counterclockwise. A zero vector
            gives a half turn, as three.js's formula gives.
        """
        return Angle(atan2(-self.y, -self.x) + Float32(pi), RADIAN)

    def angle_to(self, other: Self) -> Angle:
        """Return the angle between two vectors, three.js's `angleTo`.

        Args:
            other: The other vector.

        Returns:
            From zero to a half turn. A right angle if either vector is
            zero, as in three.js.
        """
        var denominator = sqrt(self.length_sq() * other.length_sq())
        if denominator == 0:
            return Angle(Float32(pi / 2), RADIAN)
        var theta = self.dot(other) / denominator
        return Angle(acos(max(Float32(-1), min(Float32(1), theta))), RADIAN)

    def distance_to(self, other: Self) -> Float32:
        """Return the distance between two points, three.js's `distanceTo`.

        Args:
            other: The other point.

        Returns:
            The Euclidean distance.
        """
        return sqrt(self.distance_to_squared(other))

    def distance_to_squared(self, other: Self) -> Float32:
        """Return the squared distance between two points, three.js's
        `distanceToSquared`.

        Args:
            other: The other point.

        Returns:
            The squared Euclidean distance.
        """
        return (self - other).length_sq()

    def manhattan_distance_to(self, other: Self) -> Float32:
        """Return the distance between two points along the axes,
        three.js's `manhattanDistanceTo`.

        Args:
            other: The other point.

        Returns:
            The sum of the absolute differences.
        """
        return (self - other).manhattan_length()

    def lerp(mut self, other: Self, alpha: Float32):
        """Move this vector toward `other` by `alpha`, three.js's `lerp`.

        Args:
            other: The vector to move toward.
            alpha: Zero stays, one arrives.
        """
        self.x += (other.x - self.x) * alpha
        self.y += (other.y - self.y) * alpha

    def lerp_vectors(mut self, start: Self, end: Self, alpha: Float32):
        """Set this vector a fraction of the way from `start` to `end`,
        three.js's `lerpVectors`.

        Args:
            start: The vector at an `alpha` of zero.
            end: The vector at an `alpha` of one.
            alpha: How far along.
        """
        self = Vector2(
            start.x + (end.x - start.x) * alpha,
            start.y + (end.y - start.y) * alpha,
        )

    def apply_matrix3(mut self, matrix: Matrix3):
        """Transform this point by a 2D affine matrix, three.js's
        `applyMatrix3`. `Matrix3.transform_point` does the arithmetic.

        Args:
            matrix: The transform.
        """
        self = matrix.transform_point(self)

    def min(mut self, other: Self):
        """Keep the smaller of each pair of components, three.js's `min`.

        Args:
            other: The other vector.
        """
        self = Vector2(min(self.x, other.x), min(self.y, other.y))

    def max(mut self, other: Self):
        """Keep the larger of each pair of components, three.js's `max`.

        Args:
            other: The other vector.
        """
        self = Vector2(max(self.x, other.x), max(self.y, other.y))

    def clamp(mut self, low: Self, high: Self):
        """Hold each component between the two vectors' components,
        three.js's `clamp`.

        Args:
            low: The smallest value of each component.
            high: The largest. Where it is below `low`, `low` wins.
        """
        self = Vector2(
            max(low.x, min(high.x, self.x)), max(low.y, min(high.y, self.y))
        )

    def clamp_scalar(mut self, low: Float32, high: Float32):
        """Hold each component between two numbers, three.js's
        `clampScalar`.

        Args:
            low: The smallest value.
            high: The largest.
        """
        self.clamp(Vector2(low, low), Vector2(high, high))

    def clamp_length(mut self, low: Float32, high: Float32):
        """Hold this vector's length between two numbers, keeping its
        direction, three.js's `clampLength`. A zero vector stays zero.

        Args:
            low: The shortest length.
            high: The longest.
        """
        var length = self.length()
        var divisor = length if length != 0 else Float32(1)
        self = self / divisor * max(low, min(high, length))

    def multiply(mut self, other: Self):
        """Multiply each component by `other`'s, three.js's `multiply`.

        Args:
            other: The factors.
        """
        self = Vector2(self.x * other.x, self.y * other.y)

    def divide(mut self, other: Self):
        """Divide each component by `other`'s, three.js's `divide`.

        Args:
            other: The divisors.
        """
        self = Vector2(self.x / other.x, self.y / other.y)

    def floor(mut self):
        """Round each component down, three.js's `floor`."""
        self = Vector2(floor(self.x), floor(self.y))

    def ceil(mut self):
        """Round each component up, three.js's `ceil`."""
        self = Vector2(ceil(self.x), ceil(self.y))

    def round(mut self):
        """Round each component to the nearest whole number, a half up,
        three.js's `round`."""
        self = Vector2(_js_round(self.x), _js_round(self.y))

    def round_to_zero(mut self):
        """Drop each component's fraction, three.js's `roundToZero`."""
        self = Vector2(trunc(self.x), trunc(self.y))

    def rotate_around(mut self, center: Self, angle: Angle):
        """Turn this point about `center`, three.js's `rotateAround`.

        Args:
            center: The point to turn about.
            angle: How far, counterclockwise.
        """
        var c = cos(angle.value)
        var s = sin(angle.value)
        var x = self.x - center.x
        var y = self.y - center.y
        self = Vector2(x * c - y * s + center.x, x * s + y * c + center.y)

    @staticmethod
    def random(mut generator: SeededRandom) -> Vector2:
        """Return a vector with each component from zero up to one,
        three.js's `random`, drawn in x, y order.

        Args:
            generator: Where the numbers come from.

        Returns:
            The vector.
        """
        var x = Float32(generator.next())
        var y = Float32(generator.next())
        return Vector2(x, y)
