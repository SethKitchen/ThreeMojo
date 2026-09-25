# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A 4x4 transform, ported from three.js `src/math/Matrix4.js`.

Storage is **column-major**, as three.js and OpenGL both are: element (row,
col) lives at index `col * 4 + row`. So the sixteen elements laid out as they
appear in memory are

    e[0]  e[4]  e[8]   e[12]
    e[1]  e[5]  e[9]   e[13]
    e[2]  e[6]  e[10]  e[14]
    e[3]  e[7]  e[11]  e[15]

with the translation living in e[12], e[13], e[14].

`set()` nevertheless takes its arguments in **row-major** order, which is the
one genuinely confusing thing about three.js's matrix API and is kept here
deliberately. It means a matrix written out in source reads the way it would
on paper, while the memory it lands in is transposed from that. There are
tests asserting exactly this, because it is the sort of thing that silently
transposes a scene.

Matrices are not unit-tagged. A transform mixes dimensions by nature — the
rotation part is dimensionless while the translation column is a length — and
expressing that honestly needs a per-element dimension system rather than a
per-value one. Rotation *angles* are `Angle` quantities, so degrees cannot be
passed where radians are meant.
"""

from math.euler import Euler
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import cos, isfinite, sin, sqrt
from units.si import Angle

# How far a frame can be from a rotation before `is_rotation` says it is not
# one: the cosine between two of its axes, or the relative error in an
# axis's length. Float32 rounding leaves errors near 1e-7 even down a long
# chain of products; a real shear or scale is thousands of times past this.
comptime FRAME_TOLERANCE = Float32(1e-4)


struct Matrix4(Equatable, ImplicitlyCopyable):
    """A 4x4 matrix in column-major order."""

    var elements: Array[Float32, 16]

    def __init__(out self):
        """Create the identity matrix, as three.js's constructor does."""
        self.elements = Array[Float32, 16](fill=0.0)
        self.elements[0] = 1.0
        self.elements[5] = 1.0
        self.elements[10] = 1.0
        self.elements[15] = 1.0

    def __init__(out self, *, copy: Self):
        """Copy another matrix."""
        self.elements = copy.elements.copy()

    def get(self, row: Int, column: Int) raises -> Float32:
        """Return the element at `row`, `column`, both zero-based."""
        if row < 0 or row > 3 or column < 0 or column > 3:
            raise Error("Matrix4 index out of range")
        return self.elements[column * 4 + row]

    def put(mut self, row: Int, column: Int, value: Float32) raises:
        """Write `value` at `row`, `column`, both zero-based."""
        if row < 0 or row > 3 or column < 0 or column > 3:
            raise Error("Matrix4 index out of range")
        self.elements[column * 4 + row] = value

    def set(
        mut self,
        n11: Float32,
        n12: Float32,
        n13: Float32,
        n14: Float32,
        n21: Float32,
        n22: Float32,
        n23: Float32,
        n24: Float32,
        n31: Float32,
        n32: Float32,
        n33: Float32,
        n34: Float32,
        n41: Float32,
        n42: Float32,
        n43: Float32,
        n44: Float32,
    ):
        """Set every element, taking arguments in row-major order.

        `nRC` is row R, column C, counting from one, so the call reads like
        the matrix written on paper. The values land transposed in memory.
        """
        self.elements[0] = n11
        self.elements[4] = n12
        self.elements[8] = n13
        self.elements[12] = n14
        self.elements[1] = n21
        self.elements[5] = n22
        self.elements[9] = n23
        self.elements[13] = n24
        self.elements[2] = n31
        self.elements[6] = n32
        self.elements[10] = n33
        self.elements[14] = n34
        self.elements[3] = n41
        self.elements[7] = n42
        self.elements[11] = n43
        self.elements[15] = n44

    def identity(mut self):
        """Reset this matrix to the identity."""
        self.set(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)

    def transpose(mut self):
        """Swap this matrix's rows and columns in place."""
        for row in range(4):  # pragma: no branch
            for column in range(row + 1, 4):
                var high = self.elements[column * 4 + row]
                self.elements[column * 4 + row] = self.elements[
                    row * 4 + column
                ]
                self.elements[row * 4 + column] = high

    def multiply(mut self, other: Self):
        """Post-multiply by `other`, giving `self * other`.

        Order matters: the right-hand matrix is applied to a point first.
        """
        var result = Array[Float32, 16](fill=0.0)
        # Fixed 4x4, so none of these can run zero times.
        for row in range(4):  # pragma: no branch
            for column in range(4):  # pragma: no branch
                var total = Float32(0)
                for k in range(4):  # pragma: no branch
                    total += (
                        self.elements[k * 4 + row]
                        * other.elements[column * 4 + k]
                    )
                result[column * 4 + row] = total
        self.elements = result^

    def premultiply(mut self, other: Self):
        """Pre-multiply by `other`, giving `other * self`."""
        var left = Matrix4(copy=other)
        left.multiply(self)
        self.elements = left.elements.copy()

    def determinant(self) -> Float32:
        """Return this matrix's determinant."""
        # Read in place: a copy of sixteen floats per call was the whole
        # cost of asking a matrix a question.
        ref e = self.elements
        var n11 = e[0]
        var n21 = e[1]
        var n31 = e[2]
        var n41 = e[3]
        var n12 = e[4]
        var n22 = e[5]
        var n32 = e[6]
        var n42 = e[7]
        var n13 = e[8]
        var n23 = e[9]
        var n33 = e[10]
        var n43 = e[11]
        var n14 = e[12]
        var n24 = e[13]
        var n34 = e[14]
        var n44 = e[15]

        return (
            n41
            * (
                n14 * n23 * n32
                - n13 * n24 * n32
                - n14 * n22 * n33
                + n12 * n24 * n33
                + n13 * n22 * n34
                - n12 * n23 * n34
            )
            + n42
            * (
                n11 * n23 * n34
                - n11 * n24 * n33
                + n14 * n21 * n33
                - n13 * n21 * n34
                + n13 * n24 * n31
                - n14 * n23 * n31
            )
            + n43
            * (
                n11 * n24 * n32
                - n11 * n22 * n34
                - n14 * n21 * n32
                + n12 * n21 * n34
                + n14 * n22 * n31
                - n12 * n24 * n31
            )
            + n44
            * (
                -n13 * n22 * n31
                - n11 * n23 * n32
                + n11 * n22 * n33
                + n13 * n21 * n32
                - n12 * n21 * n33
                + n12 * n23 * n31
            )
        )

    def invert(mut self):
        """Invert this matrix in place.

        A singular matrix is set to all zeros, which is what three.js does.
        It is a deliberately conspicuous result: anything transformed by it
        collapses to the origin rather than quietly coming back unchanged.
        """
        var e = self.elements.copy()
        var n11 = e[0]
        var n21 = e[1]
        var n31 = e[2]
        var n41 = e[3]
        var n12 = e[4]
        var n22 = e[5]
        var n32 = e[6]
        var n42 = e[7]
        var n13 = e[8]
        var n23 = e[9]
        var n33 = e[10]
        var n43 = e[11]
        var n14 = e[12]
        var n24 = e[13]
        var n34 = e[14]
        var n44 = e[15]

        var t11 = (
            n23 * n34 * n42
            - n24 * n33 * n42
            + n24 * n32 * n43
            - n22 * n34 * n43
            - n23 * n32 * n44
            + n22 * n33 * n44
        )
        var t12 = (
            n14 * n33 * n42
            - n13 * n34 * n42
            - n14 * n32 * n43
            + n12 * n34 * n43
            + n13 * n32 * n44
            - n12 * n33 * n44
        )
        var t13 = (
            n13 * n24 * n42
            - n14 * n23 * n42
            + n14 * n22 * n43
            - n12 * n24 * n43
            - n13 * n22 * n44
            + n12 * n23 * n44
        )
        var t14 = (
            n14 * n23 * n32
            - n13 * n24 * n32
            - n14 * n22 * n33
            + n12 * n24 * n33
            + n13 * n22 * n34
            - n12 * n23 * n34
        )

        var det = n11 * t11 + n21 * t12 + n31 * t13 + n41 * t14
        if det == 0:
            self.elements = Array[Float32, 16](fill=0.0)
            return

        var inv = Float32(1) / det
        e[0] = t11 * inv
        e[1] = (
            n24 * n33 * n41
            - n23 * n34 * n41
            - n24 * n31 * n43
            + n21 * n34 * n43
            + n23 * n31 * n44
            - n21 * n33 * n44
        ) * inv
        e[2] = (
            n22 * n34 * n41
            - n24 * n32 * n41
            + n24 * n31 * n42
            - n21 * n34 * n42
            - n22 * n31 * n44
            + n21 * n32 * n44
        ) * inv
        e[3] = (
            n23 * n32 * n41
            - n22 * n33 * n41
            - n23 * n31 * n42
            + n21 * n33 * n42
            + n22 * n31 * n43
            - n21 * n32 * n43
        ) * inv
        e[4] = t12 * inv
        e[5] = (
            n13 * n34 * n41
            - n14 * n33 * n41
            + n14 * n31 * n43
            - n11 * n34 * n43
            - n13 * n31 * n44
            + n11 * n33 * n44
        ) * inv
        e[6] = (
            n14 * n32 * n41
            - n12 * n34 * n41
            - n14 * n31 * n42
            + n11 * n34 * n42
            + n12 * n31 * n44
            - n11 * n32 * n44
        ) * inv
        e[7] = (
            n12 * n33 * n41
            - n13 * n32 * n41
            + n13 * n31 * n42
            - n11 * n33 * n42
            - n12 * n31 * n43
            + n11 * n32 * n43
        ) * inv
        e[8] = t13 * inv
        e[9] = (
            n14 * n23 * n41
            - n13 * n24 * n41
            - n14 * n21 * n43
            + n11 * n24 * n43
            + n13 * n21 * n44
            - n11 * n23 * n44
        ) * inv
        e[10] = (
            n12 * n24 * n41
            - n14 * n22 * n41
            + n14 * n21 * n42
            - n11 * n24 * n42
            - n12 * n21 * n44
            + n11 * n22 * n44
        ) * inv
        e[11] = (
            n13 * n22 * n41
            - n12 * n23 * n41
            - n13 * n21 * n42
            + n11 * n23 * n42
            + n12 * n21 * n43
            - n11 * n22 * n43
        ) * inv
        e[12] = t14 * inv
        e[13] = (
            n13 * n24 * n31
            - n14 * n23 * n31
            + n14 * n21 * n33
            - n11 * n24 * n33
            - n13 * n21 * n34
            + n11 * n23 * n34
        ) * inv
        e[14] = (
            n14 * n22 * n31
            - n12 * n24 * n31
            - n14 * n21 * n32
            + n11 * n24 * n32
            + n12 * n21 * n34
            - n11 * n22 * n34
        ) * inv
        e[15] = (
            n12 * n23 * n31
            - n13 * n22 * n31
            + n13 * n21 * n32
            - n11 * n23 * n32
            - n12 * n21 * n33
            + n11 * n22 * n33
        ) * inv
        self.elements = e^

    def normal_matrix(self) raises -> Self:
        """Return the matrix that transforms normals through this transform.

        A normal is perpendicular to a surface, and perpendicularity is not
        preserved by an arbitrary transform. Scaling a plane by two in x and
        one in y tilts the surface one way and the naive normal the other, so
        a normal carried by the transform itself stops being perpendicular to
        the surface it belongs to, and the lighting goes quietly wrong.

        The matrix that does preserve it is the inverse transpose of the
        upper-left 3x3, which is three.js's `Matrix3.getNormalMatrix`. For a
        rotation it is the rotation back again, and for a uniform scale it is
        the same rotation scaled — which is why ignoring all this works until
        the moment a scale is not uniform.

        Returned as a 4x4 with an empty translation column, so the result can
        be handed straight to `transform_direction`. The result is not
        normalized: it scales as well as rotates, and the caller normalizes.

        Returns:
            The inverse transpose of the rotation and scale part.

        Raises:
            Error: If the 3x3 is singular — a zero scale on some axis, say —
                which leaves the surface with no direction to be perpendicular
                to and no inverse to build the answer from.
        """
        ref e = self.elements
        # Rows of the upper-left 3x3, remembering storage is column-major.
        var a = e[0]
        var b = e[4]
        var c = e[8]
        var d = e[1]
        var f = e[5]
        var g = e[9]
        var h = e[2]
        var i = e[6]
        var j = e[10]

        # The cofactor matrix. inverse = adjugate / det = cofactor^T / det, so
        # the inverse *transpose* is the cofactor matrix over the determinant
        # — no separate transpose step is needed.
        var c11 = f * j - g * i
        var c12 = -(d * j - g * h)
        var c13 = d * i - f * h
        var c21 = -(b * j - c * i)
        var c22 = a * j - c * h
        var c23 = -(a * i - b * h)
        var c31 = b * g - c * f
        var c32 = -(a * g - c * d)
        var c33 = a * f - b * d

        # Expanding along the first row reuses the cofactors just computed.
        var det = a * c11 + b * c12 + c * c13
        if det == 0:
            raise Error(
                "A transform that collapses a dimension has no normal matrix"
            )

        var inv = Float32(1) / det
        var matrix = Matrix4()
        matrix.set(
            c11 * inv,
            c12 * inv,
            c13 * inv,
            0,
            c21 * inv,
            c22 * inv,
            c23 * inv,
            0,
            c31 * inv,
            c32 * inv,
            c33 * inv,
            0,
            0,
            0,
            0,
            1,
        )
        return matrix^

    def transform_point(self, point: Vector3) -> Vector3:
        """Return `point` transformed, treating it as a position (w = 1).

        The result is divided by the transformed w, which is what makes a
        perspective matrix produce perspective.
        """
        ref e = self.elements
        var x = point.x
        var y = point.y
        var z = point.z
        var w = e[3] * x + e[7] * y + e[11] * z + e[15]
        var inv = Float32(1)
        if w != 0:
            inv = Float32(1) / w
        return Vector3(
            (e[0] * x + e[4] * y + e[8] * z + e[12]) * inv,
            (e[1] * x + e[5] * y + e[9] * z + e[13]) * inv,
            (e[2] * x + e[6] * y + e[10] * z + e[14]) * inv,
        )

    def transform_w(self, point: Vector3) -> Float32:
        """Return the w that `transform_point` would divide this point by.

        For a projection matrix this is the clip-space w — the camera-space
        depth, up to sign — and its reciprocal is what makes an interpolated
        vertex attribute perspective correct. `transform_point` computes it,
        divides by it and discards it, which is everything a *position* needs
        and not enough for anything carried alongside one.

        Args:
            point: The point to transform, treated as a position (w = 1).

        Returns:
            The transformed w. One for an affine transform, which is what
            makes the perspective correction a no-op when there is no
            perspective.
        """
        ref e = self.elements
        return e[3] * point.x + e[7] * point.y + e[11] * point.z + e[15]

    def transform_direction(self, direction: Vector3) -> Vector3:
        """Return `direction` transformed, ignoring translation (w = 0).

        A direction has no position, so the translation column must not apply
        to it. The result is not renormalized.
        """
        ref e = self.elements
        var x = direction.x
        var y = direction.y
        var z = direction.z
        return Vector3(
            e[0] * x + e[4] * y + e[8] * z,
            e[1] * x + e[5] * y + e[9] * z,
            e[2] * x + e[6] * y + e[10] * z,
        )

    def extract_rotation(self) raises -> Matrix4:
        """Return the rotation this matrix applies, with scale and translation
        removed.

        three.js's `extractRotation`: each of the three axis columns is scaled
        back to unit length and the translation column is dropped. What is
        left is a pure rotation if this was a rotation times a positive scale.
        Shear is not undone, and a reflection stays one: the result then has
        unit axes that are not at right angles, or a left-handed set, and
        `is_rotation` on it says so. A caller that needs a rotation asks.

        Returns:
            The rotation matrix.

        Raises:
            Error: If an axis column has zero length -- a scale of zero on
                that axis -- which leaves no direction to normalize.
        """
        ref e = self.elements
        var out = Matrix4()
        for axis in range(3):  # pragma: no branch
            var start = axis * 4
            var length = self._axis_length(axis)
            if length == 0:
                raise Error(
                    "A transform with no extent along an axis has no rotation"
                    " to extract"
                )
            out.elements[start] = e[start] / length
            out.elements[start + 1] = e[start + 1] / length
            out.elements[start + 2] = e[start + 2] / length
        return out^

    def is_rotation(self, tolerance: Float32 = FRAME_TOLERANCE) -> Bool:
        """Return True if the upper-left three by three is a rotation.

        Three unit axes, each at right angles to the other two, in a
        right-handed set. `extract_rotation` returns one of these when it was
        given a rotation times a positive scale, and something else from a
        sheared transform such as a nonuniform scale above a turn: unit axes
        that are not at right angles. A camera that inverts the result as
        its view asks this first, because a sheared view skews the image.

        Args:
            tolerance: How far an axis can be from unit length, and the
                cosine between two axes from zero. The default allows
                Float32 rounding and refuses any real shear or scale.

        Returns:
            True for a rotation, within `tolerance`. Translation is not
            looked at.
        """
        var unit = abs(self._axis_length(0) - 1) <= tolerance
        return unit and self.is_scaled_rotation(tolerance)

    def is_scaled_rotation(self, tolerance: Float32 = FRAME_TOLERANCE) -> Bool:
        """Return True if the upper-left three by three is a rotation times
        a positive uniform scale.

        Those are the transforms that carry every direction faithfully: a
        vector goes in and comes out turned and longer, at the same angle to
        every other vector as before. A nonuniform scale bends any direction
        that is not along one of its axes, a shear bends every direction,
        and a mirror turns the frame inside out, so all three fail.
        `Scene.look_at` asks this of a parent, because it builds a facing in
        the world and carries it into the parent's frame.

        Args:
            tolerance: How far the axes can be from equal length, relative
                to the first, and the cosine between two of them from zero.
                The default allows Float32 rounding and refuses any real
                shear or nonuniform scale.

        Returns:
            True for three axes of one positive length at right angles to
            each other, in a right-handed set. Translation is not looked at.
        """
        var first = self._axis_length(0)
        for axis in range(1, 3):  # pragma: no branch
            if abs(self._axis_length(axis) - first) > tolerance * first:
                return False
        return (
            self._axes_are_perpendicular(tolerance) and self.determinant() > 0
        )

    def max_scale(self) -> Float32:
        """Return the longest of this matrix's three axis columns.

        three.js's `getMaxScaleOnAxis`. It is the most any direction is
        stretched only when the axes are at right angles; a nonuniform
        scale above a turn stretches a diagonal more than any axis, and a
        bound that grew by this would fall short. `max_stretch` is the
        answer that never does.

        Returns:
            The largest axis length. Zero for a transform that flattens
            everything.
        """
        var longest = self._axis_length(0)
        for axis in range(1, 3):  # pragma: no branch
            var length = self._axis_length(axis)
            if length > longest:
                longest = length
        return longest

    def max_stretch(self) -> Float32:
        """Return a bound on the most this matrix stretches any direction.

        The most any direction is stretched is the largest singular value
        of the upper-left three by three, which no axis length gives once
        the axes are off right angles. This needs no decomposition: the
        largest eigenvalue of the Gram matrix, the axes dotted with each
        other, is at most its largest row of absolute values summed, so the
        root of that row is at least the largest singular value. With the
        axes at right angles the off-diagonal dots vanish and it is the
        longest axis exactly. Worked in Float64 and nudged up by a part in
        a million before it is narrowed, so rounding never brings it under.

        Returns:
            A stretch no direction exceeds. Zero for a transform that
            flattens everything.
        """
        # The Gram entries are worked in Float64 from the start: squaring a
        # Float32 axis first underflows at a scale of 1e-25 and overflows at
        # 1e20, both finite scales a bound has to survive.
        ref e = self.elements
        var largest = Float64(0)
        for row in range(3):  # pragma: no branch
            var total = Float64(0)
            for column in range(3):  # pragma: no branch
                var dot = Float64(0)
                for lane in range(3):  # pragma: no branch
                    dot += Float64(e[row * 4 + lane]) * Float64(
                        e[column * 4 + lane]
                    )
                total += abs(dot)
            if total > largest:
                largest = total
        return Float32(sqrt(largest) * (1 + 1e-6))

    def is_affine(self) -> Bool:
        """Return True if the bottom row is (0, 0, 0, 1).

        Such a matrix moves, turns, scales or shears, and keeps `w` at one;
        a projection does not, and the bounds that transform by carrying
        corners across refuse one, because a corner crossing `w = 0` has no
        finite image to bound.

        Returns:
            Whether the matrix is affine.
        """
        ref e = self.elements
        return e[3] == 0 and e[7] == 0 and e[11] == 0 and e[15] == 1

    def is_finite(self) -> Bool:
        """Return True if every element is a finite number.

        A matrix with an infinity or a not-a-number in it places nothing
        anywhere, and the arithmetic downstream would carry the value into
        every bound, corner and normal without a word. An instance matrix
        is asked this at the boundary that takes it.

        Returns:
            Whether no element is infinite or not a number.
        """
        for index in range(16):  # pragma: no branch
            if not isfinite(self.elements[index]):
                return False
        return True

    def __eq__(self, other: Self) -> Bool:
        """Return True if every element is exactly equal, three.js's
        `equals`.

        Args:
            other: The matrix to compare with.

        Returns:
            Whether the sixteen elements match.
        """
        for index in range(16):  # pragma: no branch
            if self.elements[index] != other.elements[index]:
                return False
        return True

    def __ne__(self, other: Self) -> Bool:
        """Return True if any element differs.

        Args:
            other: The matrix to compare with.

        Returns:
            Whether the two differ.
        """
        return not self == other

    def __mul__(self, other: Self) -> Self:
        """Return `self * other`, three.js's `multiplyMatrices`.

        Args:
            other: The matrix applied to a point first.

        Returns:
            The product.
        """
        var product = self
        product.multiply(other)
        return product

    def multiply_scalar(mut self, factor: Float32):
        """Multiply every element by a number, three.js's `multiplyScalar`.

        Args:
            factor: The number.
        """
        for index in range(16):  # pragma: no branch
            self.elements[index] *= factor

    def scale(mut self, factors: Vector3):
        """Scale the first three columns by the three factors, three.js's
        `scale`: a scaling applied before this transform.

        Args:
            factors: The scale along x, y and z.
        """
        for row in range(4):  # pragma: no branch
            self.elements[row] *= factors.x
            self.elements[4 + row] *= factors.y
            self.elements[8 + row] *= factors.z

    def set_position(mut self, position: Vector3):
        """Set the translation column, three.js's `setPosition`. Nothing
        else changes.

        Args:
            position: The new translation.
        """
        self.elements[12] = position.x
        self.elements[13] = position.y
        self.elements[14] = position.z

    def copy_position(mut self, other: Self):
        """Copy another matrix's translation column into this one,
        three.js's `copyPosition`.

        Args:
            other: The matrix to copy from.
        """
        self.set_position(Vector3.from_matrix_position(other))

    def set_from_matrix3(mut self, matrix: Matrix3):
        """Set this matrix to a 3x3 in its upper left, three.js's
        `setFromMatrix3`: no translation, and a bottom row of (0, 0, 0, 1).
        The same as `Matrix3.as_matrix4`.

        Args:
            matrix: The 3x3.
        """
        self = matrix.as_matrix4()

    def extract_basis(
        self, mut x_axis: Vector3, mut y_axis: Vector3, mut z_axis: Vector3
    ):
        """Write the first three columns into three vectors, three.js's
        `extractBasis`.

        Args:
            x_axis: Receives the first column.
            y_axis: Receives the second column.
            z_axis: Receives the third column.
        """
        ref e = self.elements
        x_axis = Vector3(e[0], e[1], e[2])
        y_axis = Vector3(e[4], e[5], e[6])
        z_axis = Vector3(e[8], e[9], e[10])

    def look_at(mut self, eye: Vector3, target: Vector3, up: Vector3):
        """Set the rotation part so that +z points from `target` to `eye`,
        three.js's `lookAt`. The translation and the bottom row are kept.

        This is an object's orientation, the inverse of a view matrix's
        turn. `math.projection.look_at` builds the view matrix.

        An eye on the target looks down -z. An up vector along the view
        direction is nudged off it by a ten-thousandth, as in three.js.

        Args:
            eye: Where the object is.
            target: What it faces away from, along +z.
            up: Which way is up, any length but zero.
        """
        var z = eye - target
        if z.length_sq() == 0:
            z.z = 1
        z.normalize()
        var x = up
        x.cross(z)
        if x.length_sq() == 0:
            if abs(up.z) == 1:
                z.x += 0.0001
            else:
                z.z += 0.0001
            z.normalize()
            x = up
            x.cross(z)
        x.normalize()
        var y = z
        y.cross(x)
        self.elements[0] = x.x
        self.elements[1] = x.y
        self.elements[2] = x.z
        self.elements[4] = y.x
        self.elements[5] = y.y
        self.elements[6] = y.z
        self.elements[8] = z.x
        self.elements[9] = z.y
        self.elements[10] = z.z

    def decompose(
        self,
        mut position: Vector3,
        mut quaternion: Quaternion,
        mut scale: Vector3,
    ) raises:
        """Split this transform into a translation, a rotation and a scale,
        three.js's `decompose`.

        A mirror comes out as a negative x scale, as in three.js. A shear
        has no exact answer: the rotation is read from axes that are not at
        right angles, as three.js reads it.

        Args:
            position: Receives the translation.
            quaternion: Receives the rotation.
            scale: Receives the scale along each axis.

        Raises:
            Error: If an axis has zero length. three.js divides by zero
                and writes not-a-number into the rotation.
        """
        var sx = self._axis_length(0)
        var sy = self._axis_length(1)
        var sz = self._axis_length(2)
        if sx == 0 or sy == 0 or sz == 0:
            raise Error(
                "A transform with no extent along an axis has no rotation"
                " to decompose"
            )
        if self.determinant() < 0:
            sx = -sx
        position = Vector3.from_matrix_position(self)
        var rotation = self
        rotation.scale(Vector3(1 / sx, 1 / sy, 1 / sz))
        quaternion = Quaternion.from_matrix(rotation)
        scale = Vector3(sx, sy, sz)

    def _axis_length(self, axis: Int) -> Float32:
        """Return the length of one axis column: the scale along that axis."""
        ref e = self.elements
        var start = axis * 4
        return sqrt(
            e[start] * e[start]
            + e[start + 1] * e[start + 1]
            + e[start + 2] * e[start + 2]
        )

    def _axes_dot(self, a: Int, b: Int) -> Float32:
        """Return the dot product of two axis columns."""
        ref e = self.elements
        var i = a * 4
        var j = b * 4
        return e[i] * e[j] + e[i + 1] * e[j + 1] + e[i + 2] * e[j + 2]

    def _axes_are_perpendicular(self, tolerance: Float32) -> Bool:
        """Return True if each axis column is at right angles to the other
        two, within `tolerance` on the cosine between them. An axis of zero
        length has no direction, so it fails."""
        for axis in range(3):  # pragma: no branch
            var other = (axis + 1) % 3
            var lengths = self._axis_length(axis) * self._axis_length(other)
            if lengths == 0:
                return False
            if abs(self._axes_dot(axis, other) / lengths) > tolerance:
                return False
        return True


def translation(x: Float32, y: Float32, z: Float32) -> Matrix4:
    """Return a matrix that moves a point by (x, y, z)."""
    var matrix = Matrix4()
    matrix.set(1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z, 0, 0, 0, 1)
    return matrix^


def scaling(x: Float32, y: Float32, z: Float32) -> Matrix4:
    """Return a matrix that scales by (x, y, z) about the origin."""
    var matrix = Matrix4()
    matrix.set(x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1)
    return matrix^


def rotation_x(angle: Angle) -> Matrix4:
    """Return a matrix rotating about the x axis by `angle`."""
    var c = cos(angle.value)
    var s = sin(angle.value)
    var matrix = Matrix4()
    matrix.set(1, 0, 0, 0, 0, c, -s, 0, 0, s, c, 0, 0, 0, 0, 1)
    return matrix^


def rotation_y(angle: Angle) -> Matrix4:
    """Return a matrix rotating about the y axis by `angle`."""
    var c = cos(angle.value)
    var s = sin(angle.value)
    var matrix = Matrix4()
    matrix.set(c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0, 0, 0, 0, 1)
    return matrix^


def rotation_z(angle: Angle) -> Matrix4:
    """Return a matrix rotating about the z axis by `angle`."""
    var c = cos(angle.value)
    var s = sin(angle.value)
    var matrix = Matrix4()
    matrix.set(c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    return matrix^


def rotation_axis(axis: Vector3, angle: Angle) -> Matrix4:
    """Return a matrix rotating about `axis` by `angle`, three.js's
    `makeRotationAxis`.

    Args:
        axis: The axis. It must be unit length, as in three.js; it is used
            as given.
        angle: How far to turn, counterclockwise looking down the axis.

    Returns:
        The rotation.
    """
    var c = cos(angle.value)
    var s = sin(angle.value)
    var t = 1 - c
    var x = axis.x
    var y = axis.y
    var z = axis.z
    var tx = t * x
    var ty = t * y
    var matrix = Matrix4()
    matrix.set(
        tx * x + c,
        tx * y - s * z,
        tx * z + s * y,
        0,
        tx * y + s * z,
        ty * y + c,
        ty * z - s * x,
        0,
        tx * z - s * y,
        ty * z + s * x,
        t * z * z + c,
        0,
        0,
        0,
        0,
        1,
    )
    return matrix^


def shear(
    xy: Float32, xz: Float32, yx: Float32, yz: Float32, zx: Float32, zy: Float32
) -> Matrix4:
    """Return a shear, three.js's `makeShear`.

    Args:
        xy: How much y moves per unit of x.
        xz: How much z moves per unit of x.
        yx: How much x moves per unit of y.
        yz: How much z moves per unit of y.
        zx: How much x moves per unit of z.
        zy: How much y moves per unit of z.

    Returns:
        The shear.
    """
    var matrix = Matrix4()
    matrix.set(1, yx, zx, 0, xy, 1, zy, 0, xz, yz, 1, 0, 0, 0, 0, 1)
    return matrix^


def basis(x_axis: Vector3, y_axis: Vector3, z_axis: Vector3) -> Matrix4:
    """Return the matrix whose first three columns are the three axes,
    three.js's `makeBasis`.

    Args:
        x_axis: The first column.
        y_axis: The second column.
        z_axis: The third column.

    Returns:
        The matrix, with no translation.
    """
    var matrix = Matrix4()
    matrix.set(
        x_axis.x,
        y_axis.x,
        z_axis.x,
        0,
        x_axis.y,
        y_axis.y,
        z_axis.y,
        0,
        x_axis.z,
        y_axis.z,
        z_axis.z,
        0,
        0,
        0,
        0,
        1,
    )
    return matrix^


def rotation_from_quaternion(quaternion: Quaternion) -> Matrix4:
    """Return the rotation a quaternion describes, three.js's
    `makeRotationFromQuaternion`. `Quaternion.to_matrix` does the
    arithmetic.

    Args:
        quaternion: The rotation, unit length.

    Returns:
        The matrix, with no translation.
    """
    return quaternion.to_matrix()


def rotation_from_euler(euler: Euler) raises -> Matrix4:
    """Return the rotation three angles describe, three.js's
    `makeRotationFromEuler`. `Euler.to_matrix` does the arithmetic.

    Args:
        euler: The angles and their order.

    Returns:
        The matrix, with no translation.

    Raises:
        Error: If the order does not name three different axes.
    """
    return euler.to_matrix()


def compose(
    position: Vector3, quaternion: Quaternion, scale: Vector3
) -> Matrix4:
    """Return the transform that scales, then turns, then moves, three.js's
    `compose`.

    Args:
        position: The translation.
        quaternion: The rotation, unit length.
        scale: The scale along each axis.

    Returns:
        The transform.
    """
    var x = quaternion.x
    var y = quaternion.y
    var z = quaternion.z
    var w = quaternion.w
    var x2 = x + x
    var y2 = y + y
    var z2 = z + z
    var xx = x * x2
    var xy = x * y2
    var xz = x * z2
    var yy = y * y2
    var yz = y * z2
    var zz = z * z2
    var wx = w * x2
    var wy = w * y2
    var wz = w * z2
    var sx = scale.x
    var sy = scale.y
    var sz = scale.z
    var matrix = Matrix4()
    matrix.set(
        (1 - (yy + zz)) * sx,
        (xy - wz) * sy,
        (xz + wy) * sz,
        position.x,
        (xy + wz) * sx,
        (1 - (xx + zz)) * sy,
        (yz - wx) * sz,
        position.y,
        (xz - wy) * sx,
        (yz + wx) * sy,
        (1 - (xx + yy)) * sz,
        position.z,
        0,
        0,
        0,
        1,
    )
    return matrix^
