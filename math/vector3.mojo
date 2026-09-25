# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A 3D vector, ported from three.js `src/math/Vector3.js`."""

from math.euler import Euler
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.quaternion import Quaternion
from math.utils import SeededRandom
from std.math import acos, ceil, cos, floor, pi, sin, sqrt, trunc
from units.si import Angle, RADIAN


def _js_round(value: Float32) -> Float32:
    """Return `value` rounded to the nearest whole number, a half rounded
    up, as JavaScript's `Math.round` rounds: -2.5 gives -2.

    Adding a half and taking the floor rounds 0.49999997 up in Float32,
    so the fraction is compared instead. It is exact for every float.
    """
    var whole = floor(value)
    return whole + Float32(1) if value - whole >= 0.5 else whole


@fieldwise_init
struct Vector3(Equatable, ImplicitlyCopyable):
    """A point or direction in 3D space.

    Like three.js, the mutating methods change the vector in place rather than
    returning a new one. Unlike three.js, `ImplicitlyCopyable` means assignment
    makes a real copy, so there is no aliasing to worry about.

    The operators are the other half. three.js has `.clone().sub(a)`; here a
    value type makes `b - a` the natural spelling, and every "copy, then
    mutate the copy" pair in the renderer was that expression written long.
    The mutating methods stay for the port's sake and for hot loops that want
    to avoid a temporary.
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

    def sub(mut self, other: Self):
        """Subtract `other` from `self`, component-wise."""
        self.x -= other.x
        self.y -= other.y
        self.z -= other.z

    def cross(mut self, other: Self):
        """Set `self` to the cross product of `self` and `other`."""
        # One statement, so every output is calculated from the original
        # components, and so a coverage run writes one record per call and
        # not six: this runs per tap of a PMREM blur.
        self = Vector3(
            self.y * other.z - self.z * other.y,
            self.z * other.x - self.x * other.z,
            self.x * other.y - self.y * other.x,
        )

    def normalize(mut self):
        """Scale `self` to unit length, leaving a zero vector unchanged."""
        var magnitude = self.length()
        if magnitude > 0:
            self.x /= magnitude
            self.y /= magnitude
            self.z /= magnitude

    def __add__(self, other: Self) -> Self:
        """Return the component-wise sum."""
        return Vector3(self.x + other.x, self.y + other.y, self.z + other.z)

    def __sub__(self, other: Self) -> Self:
        """Return the component-wise difference."""
        return Vector3(self.x - other.x, self.y - other.y, self.z - other.z)

    def __mul__(self, factor: Float32) -> Self:
        """Return this vector scaled by a number."""
        return Vector3(self.x * factor, self.y * factor, self.z * factor)

    def __neg__(self) -> Self:
        """Return this vector pointing the other way."""
        return Vector3(-self.x, -self.y, -self.z)

    def __truediv__(self, divisor: Float32) -> Self:
        """Return this vector divided by a number, three.js's
        `divideScalar`: a multiply by the reciprocal, as there. A zero
        divisor gives infinities, as there.

        Args:
            divisor: The number to divide by.

        Returns:
            The divided vector.
        """
        return self * (1 / divisor)

    def __eq__(self, other: Self) -> Bool:
        """Return True if every component is exactly equal, three.js's
        `equals`.

        Args:
            other: The vector to compare with.

        Returns:
            Whether the two are the same vector.
        """
        return self.x == other.x and self.y == other.y and self.z == other.z

    def __ne__(self, other: Self) -> Bool:
        """Return True if any component differs.

        Args:
            other: The vector to compare with.

        Returns:
            Whether the two differ.
        """
        return not self == other

    def get_component(self, index: Int) raises -> Float32:
        """Return one component by its index, three.js's `getComponent`.

        Args:
            index: 0 for x, 1 for y, 2 for z.

        Returns:
            The component.

        Raises:
            Error: If the index is not 0, 1 or 2.
        """
        if index == 0:
            return self.x
        if index == 1:
            return self.y
        if index == 2:
            return self.z
        raise Error("A Vector3 component index is 0, 1 or 2")

    def set_component(mut self, index: Int, value: Float32) raises:
        """Set one component by its index, three.js's `setComponent`.

        Args:
            index: 0 for x, 1 for y, 2 for z.
            value: The new component.

        Raises:
            Error: If the index is not 0, 1 or 2.
        """
        if index == 0:
            self.x = value
        elif index == 1:
            self.y = value
        elif index == 2:
            self.z = value
        else:
            raise Error("A Vector3 component index is 0, 1 or 2")

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
        """Add one number to every component, three.js's `addScalar`.

        Args:
            value: The number to add.
        """
        self = Vector3(self.x + value, self.y + value, self.z + value)

    def sub_scalar(mut self, value: Float32):
        """Subtract one number from every component, three.js's
        `subScalar`.

        Args:
            value: The number to subtract.
        """
        self = Vector3(self.x - value, self.y - value, self.z - value)

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
            `|x| + |y| + |z|`.
        """
        return abs(self.x) + abs(self.y) + abs(self.z)

    def set_length(mut self, length: Float32):
        """Scale this vector to `length`, three.js's `setLength`. A zero
        vector stays zero, as `normalize` leaves it.

        Args:
            length: The new length.
        """
        self.normalize()
        self = self * length

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

    def angle_to(self, other: Self) -> Angle:
        """Return the angle between two vectors, three.js's `angleTo`.

        Args:
            other: The other vector.

        Returns:
            From zero to a half turn. A right angle if either vector is
            zero, as in three.js: a zero vector has no direction.
        """
        var denominator = sqrt(self.length_sq() * other.length_sq())
        if denominator == 0:
            return Angle(Float32(pi / 2), RADIAN)
        var theta = self.dot(other) / denominator
        return Angle(acos(max(Float32(-1), min(Float32(1), theta))), RADIAN)

    def lerp(mut self, other: Self, alpha: Float32):
        """Move this vector toward `other` by `alpha`, three.js's `lerp`.

        Args:
            other: The vector to move toward.
            alpha: Zero stays, one arrives. Values outside run on.
        """
        self.x += (other.x - self.x) * alpha
        self.y += (other.y - self.y) * alpha
        self.z += (other.z - self.z) * alpha

    def lerp_vectors(mut self, start: Self, end: Self, alpha: Float32):
        """Set this vector a fraction of the way from `start` to `end`,
        three.js's `lerpVectors`.

        Args:
            start: The vector at an `alpha` of zero.
            end: The vector at an `alpha` of one.
            alpha: How far along.
        """
        self = Vector3(
            start.x + (end.x - start.x) * alpha,
            start.y + (end.y - start.y) * alpha,
            start.z + (end.z - start.z) * alpha,
        )

    def reflect(mut self, normal: Self):
        """Reflect this vector off a plane with the given normal, three.js's
        `reflect`.

        Args:
            normal: The plane's normal. It must be unit length, as in
                three.js; it is used as given.
        """
        self = self - normal * (2 * self.dot(normal))

    def apply_matrix4(mut self, matrix: Matrix4):
        """Transform this point by `matrix` with `w = 1`, and divide by the
        `w` that comes out, three.js's `applyMatrix4`.

        `Matrix4.transform_point` does the arithmetic. A point that comes
        out with `w = 0` is left undivided; three.js divides by zero.

        Args:
            matrix: The transform.
        """
        self = matrix.transform_point(self)

    def apply_matrix3(mut self, matrix: Matrix3):
        """Multiply this vector by `matrix`, three.js's `applyMatrix3`.

        Args:
            matrix: The matrix.
        """
        self = matrix.transform(self)

    def apply_normal_matrix(mut self, matrix: Matrix3):
        """Carry this normal through a normal matrix, and make it unit
        length again, three.js's `applyNormalMatrix`.

        Args:
            matrix: The normal matrix, from `Matrix3.normal_matrix`.
        """
        self.apply_matrix3(matrix)
        self.normalize()

    def apply_quaternion(mut self, quaternion: Quaternion):
        """Turn this vector by a rotation, three.js's `applyQuaternion`.

        Args:
            quaternion: The rotation, unit length.
        """
        self = quaternion.rotate(self)

    def apply_euler(mut self, euler: Euler) raises:
        """Turn this vector by three angles, three.js's `applyEuler`.

        Args:
            euler: The rotation.

        Raises:
            Error: If the Euler order does not name three different axes.
        """
        self.apply_quaternion(euler.to_quaternion())

    def apply_axis_angle(mut self, axis: Self, angle: Angle):
        """Turn this vector about an axis, three.js's `applyAxisAngle`.

        Args:
            axis: The axis, unit length.
            angle: How far to turn, counterclockwise looking down the axis.
        """
        self.apply_quaternion(Quaternion.from_axis_angle(axis, angle))

    def transform_direction(mut self, matrix: Matrix4):
        """Turn this direction by the rotation and scale of `matrix`, and
        make it unit length, three.js's `transformDirection`.

        `Matrix4.transform_direction` does the same product and does not
        normalize.

        Args:
            matrix: The transform. Its translation is ignored.
        """
        self = matrix.transform_direction(self)
        self.normalize()

    def project(mut self, view: Matrix4, projection: Matrix4):
        """Carry this world-space point into normalized device space,
        three.js's `project`.

        three.js reads the two matrices off a camera. Here the caller
        passes them, or calls `cameras.camera.project_point`.

        Args:
            view: The camera's view matrix, three.js's
                `matrixWorldInverse`.
            projection: The camera's projection matrix.
        """
        self.apply_matrix4(view)
        self.apply_matrix4(projection)

    def unproject(mut self, view: Matrix4, projection: Matrix4):
        """Carry this point from normalized device space back into world
        space, three.js's `unproject`.

        Both matrices are inverted here. A singular one inverts to zeros,
        as in three.js, and the point collapses to the origin.

        Args:
            view: The camera's view matrix.
            projection: The camera's projection matrix.
        """
        var projection_inverse = projection
        projection_inverse.invert()
        var world = view
        world.invert()
        self.apply_matrix4(projection_inverse)
        self.apply_matrix4(world)

    def min(mut self, other: Self):
        """Keep the smaller of each pair of components, three.js's `min`.

        Args:
            other: The other vector.
        """
        self = Vector3(
            min(self.x, other.x), min(self.y, other.y), min(self.z, other.z)
        )

    def max(mut self, other: Self):
        """Keep the larger of each pair of components, three.js's `max`.

        Args:
            other: The other vector.
        """
        self = Vector3(
            max(self.x, other.x), max(self.y, other.y), max(self.z, other.z)
        )

    def clamp(mut self, low: Self, high: Self):
        """Hold each component between the two vectors' components,
        three.js's `clamp`.

        Args:
            low: The smallest value of each component.
            high: The largest. Where it is below `low`, `low` wins, as in
                three.js.
        """
        self = Vector3(
            max(low.x, min(high.x, self.x)),
            max(low.y, min(high.y, self.y)),
            max(low.z, min(high.z, self.z)),
        )

    def clamp_scalar(mut self, low: Float32, high: Float32):
        """Hold each component between two numbers, three.js's
        `clampScalar`.

        Args:
            low: The smallest value.
            high: The largest.
        """
        self.clamp(Vector3(low, low, low), Vector3(high, high, high))

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
        self = Vector3(self.x * other.x, self.y * other.y, self.z * other.z)

    def divide(mut self, other: Self):
        """Divide each component by `other`'s, three.js's `divide`. A zero
        divisor gives an infinity or a not-a-number, as there.

        Args:
            other: The divisors.
        """
        self = Vector3(self.x / other.x, self.y / other.y, self.z / other.z)

    def floor(mut self):
        """Round each component down, three.js's `floor`."""
        self = Vector3(floor(self.x), floor(self.y), floor(self.z))

    def ceil(mut self):
        """Round each component up, three.js's `ceil`."""
        self = Vector3(ceil(self.x), ceil(self.y), ceil(self.z))

    def round(mut self):
        """Round each component to the nearest whole number, a half up,
        three.js's `round`."""
        self = Vector3(_js_round(self.x), _js_round(self.y), _js_round(self.z))

    def round_to_zero(mut self):
        """Drop each component's fraction, three.js's `roundToZero`."""
        self = Vector3(trunc(self.x), trunc(self.y), trunc(self.z))

    def project_on_vector(mut self, other: Self):
        """Replace this vector by its projection onto `other`, three.js's
        `projectOnVector`.

        Args:
            other: The vector to project onto. A zero vector gives a zero
                vector, as in three.js.
        """
        var denominator = other.length_sq()
        if denominator == 0:
            self = Vector3(0, 0, 0)
            return
        self = other * (other.dot(self) / denominator)

    def project_on_plane(mut self, normal: Self):
        """Remove the part of this vector along `normal`, three.js's
        `projectOnPlane`.

        Args:
            normal: The plane's normal, any length. A zero normal leaves
                this vector unchanged.
        """
        var along = self
        along.project_on_vector(normal)
        self = self - along

    @staticmethod
    def from_matrix_position(matrix: Matrix4) -> Vector3:
        """Return the translation of a matrix, three.js's
        `setFromMatrixPosition`.

        Args:
            matrix: The matrix.

        Returns:
            Elements 12, 13 and 14.
        """
        ref e = matrix.elements
        return Vector3(e[12], e[13], e[14])

    @staticmethod
    def from_matrix_column(matrix: Matrix4, index: Int) raises -> Vector3:
        """Return the first three elements of one column of a matrix,
        three.js's `setFromMatrixColumn`.

        Args:
            matrix: The matrix.
            index: Which column, 0 to 3.

        Returns:
            The column's x, y and z.

        Raises:
            Error: If the index is not 0 to 3.
        """
        if index < 0 or index > 3:
            raise Error("A Matrix4 column index is 0 to 3")
        ref e = matrix.elements
        var start = index * 4
        return Vector3(e[start], e[start + 1], e[start + 2])

    @staticmethod
    def from_matrix3_column(matrix: Matrix3, index: Int) raises -> Vector3:
        """Return one column of a three by three matrix, three.js's
        `setFromMatrix3Column`.

        Args:
            matrix: The matrix.
            index: Which column, 0 to 2.

        Returns:
            The column.

        Raises:
            Error: If the index is not 0 to 2.
        """
        if index < 0 or index > 2:
            raise Error("A Matrix3 column index is 0 to 2")
        ref e = matrix.elements
        var start = index * 3
        return Vector3(e[start], e[start + 1], e[start + 2])

    @staticmethod
    def from_matrix_scale(matrix: Matrix4) -> Vector3:
        """Return the length of each of a matrix's three axis columns,
        three.js's `setFromMatrixScale`. Never negative: a mirror does not
        show.

        Args:
            matrix: The matrix.

        Returns:
            The scale along x, y and z.
        """
        ref e = matrix.elements
        return Vector3(
            Vector3(e[0], e[1], e[2]).length(),
            Vector3(e[4], e[5], e[6]).length(),
            Vector3(e[8], e[9], e[10]).length(),
        )

    @staticmethod
    def random(mut generator: SeededRandom) -> Vector3:
        """Return a vector with each component from zero up to one,
        three.js's `random`, drawn in x, y, z order.

        Args:
            generator: Where the numbers come from.

        Returns:
            The vector.
        """
        var x = Float32(generator.next())
        var y = Float32(generator.next())
        var z = Float32(generator.next())
        return Vector3(x, y, z)

    @staticmethod
    def random_direction(mut generator: SeededRandom) -> Vector3:
        """Return a unit vector in a direction spread evenly over the
        sphere, three.js's `randomDirection`.

        Args:
            generator: Where the numbers come from.

        Returns:
            The direction.
        """
        var theta = generator.next() * pi * 2
        var u = generator.next() * 2 - 1
        var c = sqrt(1 - u * u)
        return Vector3(
            Float32(c * cos(theta)), Float32(u), Float32(c * sin(theta))
        )
