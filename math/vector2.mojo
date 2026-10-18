# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A 2D vector, ported from three.js `src/math/Vector2.js`."""

from math.matrix3 import Matrix3
from math.polyline import (
    PolylineVertex,
    add_scaled,
    angle_between,
    clamp_to_length,
    distance_between,
    distance_between_squared,
    lerp_between,
    lerp_in_place,
    scale_to_length,
)
from math.utils import SeededRandom, clamp, js_round
from math.norm import dot2, length2, normalized2
from std.math import (
    atan2,
    ceil,
    copysign,
    cos,
    floor,
    isfinite,
    pi,
    sin,
    trunc,
)
from units.si import Angle, RADIAN


@fieldwise_init
struct Vector2(Equatable, ImplicitlyCopyable, PolylineVertex):
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
        return dot2[DType.float32](self.x, self.y, other.x, other.y)

    def cross(self, other: Self) -> Float32:
        """Return the z component of the cross product, which is the only
        one two vectors in a plane have. It is positive when `other` lies
        to the left of `self`, and zero when the two are parallel."""
        return self.x * other.y - self.y * other.x

    def length(self) -> Float32:
        """Return the Euclidean length of the vector."""
        return length2(self.x, self.y)

    def is_finite(self) -> Bool:
        """Return True if every component is finite.

        Returns:
            True when `x` and `y` are both finite.
        """
        return isfinite(self.x) and isfinite(self.y)

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
        var components = normalized2(self.x, self.y)
        self.x = components[0]
        self.y = components[1]

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
        add_scaled(self, other, factor)

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
        scale_to_length(self, length)

    def angle(self) -> Angle:
        """Return the angle this vector makes with +x, three.js's `angle`.

        Returns:
            From zero to a whole turn, counterclockwise. A whole turn is
            possible: a tiny negative y, or (+0, -0), rounds `atan2` to pi.
            Positive zero components give zero. Signed zeros follow the
            IEEE `atan2` table on every platform.
        """
        if self.x == 0 and self.y == 0:
            # Apple's atan2f returns one ulp less than pi for two zeros, so
            # read the IEEE table here. A negative-zero x gives a half turn.
            if copysign(Float32(1), self.x) < 0:
                return Angle(Float32(pi), RADIAN)
            return Angle(copysign(Float32(pi), -self.y) + Float32(pi), RADIAN)
        return Angle(atan2(-self.y, -self.x) + Float32(pi), RADIAN)

    def angle_to(self, other: Self) -> Angle:
        """Return the angle between two vectors, three.js's `angleTo`.

        Args:
            other: The other vector.

        Returns:
            From zero to a half turn. A right angle if either vector is
            zero, as in three.js.
        """
        return angle_between(self, other)

    def distance_to(self, other: Self) -> Float32:
        """Return the distance between two points, three.js's `distanceTo`.

        Args:
            other: The other point.

        Returns:
            The Euclidean distance.
        """
        return distance_between(self, other)

    def distance_to_squared(self, other: Self) -> Float32:
        """Return the squared distance between two points, three.js's
        `distanceToSquared`.

        Args:
            other: The other point.

        Returns:
            The squared Euclidean distance.
        """
        return distance_between_squared(self, other)

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
        lerp_in_place(self, other, alpha)

    def lerp_vectors(mut self, start: Self, end: Self, alpha: Float32):
        """Set this vector a fraction of the way from `start` to `end`,
        three.js's `lerpVectors`.

        Args:
            start: The vector at an `alpha` of zero.
            end: The vector at an `alpha` of one.
            alpha: How far along.
        """
        lerp_between(self, start, end, alpha)

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
        self = component_min(self, other)

    def max(mut self, other: Self):
        """Keep the larger of each pair of components, three.js's `max`.

        Args:
            other: The other vector.
        """
        self = component_max(self, other)

    def clamp(mut self, low: Self, high: Self):
        """Hold each component between the two vectors' components,
        three.js's `clamp`.

        Args:
            low: The smallest value of each component.
            high: The largest. Where it is below `low`, `low` wins.
        """
        self = Vector2(
            clamp(self.x, low.x, high.x), clamp(self.y, low.y, high.y)
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
        clamp_to_length(self, low, high)

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
        self = Vector2(js_round(self.x), js_round(self.y))

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
        """Return a vector with each component in `[0, 1)`,
        three.js's `random`, drawn in x, y order.

        Args:
            generator: Where the numbers come from.

        Returns:
            The vector.
        """
        var x = generator.float_in(0, 1)
        var y = generator.float_in(0, 1)
        return Vector2(x, y)


def component_min(a: Vector2, b: Vector2) -> Vector2:
    """Return the smaller of each component, three.js's `min`.

    Args:
        a: One vector.
        b: The other vector.

    Returns:
        The smaller components.
    """
    return Vector2(min(a.x, b.x), min(a.y, b.y))


def component_max(a: Vector2, b: Vector2) -> Vector2:
    """Return the larger of each component, three.js's `max`.

    Args:
        a: One vector.
        b: The other vector.

    Returns:
        The larger components.
    """
    return Vector2(max(a.x, b.x), max(a.y, b.y))


def weighted_sum2(
    a: Vector2,
    b: Vector2,
    c: Vector2,
    weight_a: Float32,
    weight_b: Float32,
    weight_c: Float32,
) -> Vector2:
    """Return three pairs mixed by their weights.

    Each product is formed, then added, in `a`, `b`, `c` order.

    Args:
        a: The first pair.
        b: The second pair.
        c: The third pair.
        weight_a: The first weight.
        weight_b: The second weight.
        weight_c: The third weight.

    Returns:
        `a * weight_a + b * weight_b + c * weight_c`.
    """
    return a * weight_a + b * weight_b + c * weight_c


def vector2_from_float64(x: Float64, y: Float64) -> Vector2:
    """Return a `Vector2` from two `Float64` components.

    Each component is rounded to `Float32`.

    Args:
        x: The first component.
        y: The second component.

    Returns:
        The rounded vector.

    Raises:
        Error: Never.
    """
    return Vector2(Float32(x), Float32(y))


def append_vector2(mut values: List[Float32], point: Vector2):
    """Append `point`'s two components.

    Args:
        values: The list that receives x and y.
        point: The vector.

    Returns:
        Nothing. Two numbers are appended.

    Raises:
        Error: Never.
    """
    values.append(point.x)
    values.append(point.y)
