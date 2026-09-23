# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A 3x3 matrix, ported from three.js `src/math/Matrix3.js`.

The two jobs a 3x3 has in three.js are the two it has here. It is the
rotation and scale part of a `Matrix4`, which is what a normal is
transformed by: `normal_matrix` is three.js's `getNormalMatrix`, the
inverse transpose of that part. And it is a 2D affine transform in
homogeneous coordinates, which is what a texture's repeat, offset and
rotation come to: `uv_transform` is three.js's `setUvTransform`, and
`scale`, `rotate` and `translate` are the pieces it is built from.

Storage is **column-major**, as `Matrix4` is: element (row, col) lives at
index `col * 3 + row`, so the nine elements laid out as they appear in
memory are

    e[0]  e[3]  e[6]
    e[1]  e[4]  e[7]
    e[2]  e[5]  e[8]

and `set()` takes its arguments in **row-major** order, as three.js's does,
so a matrix written in source reads the way it would on paper. See
`math.matrix4` for why that asymmetry is kept.

Like `Matrix4`, this is not unit-tagged. A rotation angle is an `Angle`,
so degrees cannot be passed where radians are meant.
"""

from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import cos, sin
from units.si import Angle


struct Matrix3(Equatable, ImplicitlyCopyable):
    """A 3x3 matrix in column-major order."""

    var elements: Array[Float32, 9]

    def __init__(out self):
        """Create the identity matrix, as three.js's constructor does."""
        self.elements = Array[Float32, 9](fill=0.0)
        self.elements[0] = 1.0
        self.elements[4] = 1.0
        self.elements[8] = 1.0

    def __init__(out self, *, copy: Self):
        """Copy another matrix.

        Args:
            copy: The matrix to copy.
        """
        self.elements = copy.elements.copy()

    def __eq__(self, other: Self) -> Bool:
        """Return True if every element is equal, three.js's `equals`.

        Exact, as three.js's is: two transforms built the same way are
        equal, and two built differently that happen to agree to within
        rounding are not. A texture's transform is compared this way
        against another's, and both were built by `uv_transform` from
        their fields.

        Args:
            other: The matrix to compare with.

        Returns:
            Whether the nine elements match.
        """
        for index in range(9):  # pragma: no branch
            if self.elements[index] != other.elements[index]:
                return False
        return True

    def __ne__(self, other: Self) -> Bool:
        """Return True if any element differs.

        Args:
            other: The matrix to compare with.

        Returns:
            Whether the two are not equal.
        """
        return not (self == other)

    @staticmethod
    def from_matrix4(matrix: Matrix4) -> Matrix3:
        """Return the upper-left 3x3 of a `Matrix4`, three.js's
        `setFromMatrix4`: its rotation, scale and shear, without its
        translation and without its projective row.

        Args:
            matrix: The 4x4 to take the corner of.

        Returns:
            The 3x3.
        """
        ref e = matrix.elements
        var out = Matrix3()
        for column in range(3):  # pragma: no branch
            for row in range(3):  # pragma: no branch
                out.elements[column * 3 + row] = e[column * 4 + row]
        return out^

    @staticmethod
    def normal_matrix(matrix: Matrix4) raises -> Matrix3:
        """Return the matrix that carries normals through `matrix`,
        three.js's `getNormalMatrix`: the inverse transpose of its
        upper-left 3x3.

        `Matrix4.normal_matrix` is the same answer as a 4x4 with an empty
        translation column, and says why a normal needs one; this is the
        answer at its own size.

        Args:
            matrix: The transform the surface goes through.

        Returns:
            The inverse transpose of its rotation and scale part.

        Raises:
            Error: If the 3x3 is singular -- a zero scale on some axis, say
                -- which leaves the surface with no direction to be
                perpendicular to and no inverse to build the answer from.
                `invert` would answer with zeros, as three.js does; a normal
                matrix of zeros would light every surface black without a
                word, so it is refused instead.
        """
        var out = Matrix3.from_matrix4(matrix)
        if out.determinant() == 0:
            raise Error(
                "A transform that collapses a dimension has no normal matrix"
            )
        out.invert()
        out.transpose()
        return out^

    @staticmethod
    def translation(x: Float32, y: Float32) -> Matrix3:
        """Return the 2D transform that moves a point by (x, y), three.js's
        `makeTranslation`.

        Args:
            x: How far along x.
            y: How far along y.

        Returns:
            The matrix.
        """
        var out = Matrix3()
        out.set(1, 0, x, 0, 1, y, 0, 0, 1)
        return out^

    @staticmethod
    def scaling(x: Float32, y: Float32) -> Matrix3:
        """Return the 2D transform that scales by (x, y) about the origin,
        three.js's `makeScale`.

        Args:
            x: The factor along x.
            y: The factor along y.

        Returns:
            The matrix.
        """
        var out = Matrix3()
        out.set(x, 0, 0, 0, y, 0, 0, 0, 1)
        return out^

    @staticmethod
    def rotation(angle: Angle) -> Matrix3:
        """Return the 2D transform that turns a point counter-clockwise by
        `angle` about the origin, three.js's `makeRotation`.

        Args:
            angle: How far to turn.

        Returns:
            The matrix.
        """
        var c = cos(angle.value)
        var s = sin(angle.value)
        var out = Matrix3()
        out.set(c, -s, 0, s, c, 0, 0, 0, 1)
        return out^

    @staticmethod
    def uv_transform(
        offset: Vector2,
        repeat: Vector2,
        rotation: Angle,
        center: Vector2,
    ) -> Matrix3:
        """Return the transform a texture applies to its coordinates,
        three.js's `setUvTransform`.

        The coordinates are moved so that `center` is at the origin, turned
        by `-rotation`, scaled by `repeat`, and moved back by `center` plus
        `offset`: the turn comes before the scale, so a nonuniform `repeat`
        stretches the turned image along its own axes rather than turning
        a stretched one. The turn is the negative of the angle asked for
        so that the *image* appears turned counter-clockwise by `rotation`:
        turning the coordinates one way turns what they sample the other.
        Every part of this matrix is three.js's, term for term.

        Args:
            offset: How far the coordinates are moved, after the rest.
            repeat: How many times the texture fits across each axis: the
                scale on the coordinates, applied after the turn.
            rotation: How far the image is turned, counter-clockwise.
            center: The point the turn and the scale are about.

        Returns:
            The matrix.
        """
        var c = cos(rotation.value)
        var s = sin(rotation.value)
        var sx = repeat.x
        var sy = repeat.y
        var cx = center.x
        var cy = center.y
        var out = Matrix3()
        out.set(
            sx * c,
            sx * s,
            -sx * (c * cx + s * cy) + cx + offset.x,
            -sy * s,
            sy * c,
            -sy * (-s * cx + c * cy) + cy + offset.y,
            0,
            0,
            1,
        )
        return out^

    def get(self, row: Int, column: Int) raises -> Float32:
        """Return the element at `row`, `column`, both zero-based.

        Args:
            row: The row, 0 to 2.
            column: The column, 0 to 2.

        Returns:
            The element.

        Raises:
            Error: If either index is outside 0 to 2.
        """
        if row < 0 or row > 2 or column < 0 or column > 2:
            raise Error("Matrix3 index out of range")
        return self.elements[column * 3 + row]

    def put(mut self, row: Int, column: Int, value: Float32) raises:
        """Write `value` at `row`, `column`, both zero-based.

        Args:
            row: The row, 0 to 2.
            column: The column, 0 to 2.
            value: What to write there.

        Raises:
            Error: If either index is outside 0 to 2.
        """
        if row < 0 or row > 2 or column < 0 or column > 2:
            raise Error("Matrix3 index out of range")
        self.elements[column * 3 + row] = value

    def set(
        mut self,
        n11: Float32,
        n12: Float32,
        n13: Float32,
        n21: Float32,
        n22: Float32,
        n23: Float32,
        n31: Float32,
        n32: Float32,
        n33: Float32,
    ):
        """Set every element, taking arguments in row-major order.

        `nRC` is row R, column C, counting from one, so the call reads like
        the matrix written on paper. The values land transposed in memory.

        Args:
            n11: Row 1, column 1.
            n12: Row 1, column 2.
            n13: Row 1, column 3.
            n21: Row 2, column 1.
            n22: Row 2, column 2.
            n23: Row 2, column 3.
            n31: Row 3, column 1.
            n32: Row 3, column 2.
            n33: Row 3, column 3.
        """
        self.elements[0] = n11
        self.elements[3] = n12
        self.elements[6] = n13
        self.elements[1] = n21
        self.elements[4] = n22
        self.elements[7] = n23
        self.elements[2] = n31
        self.elements[5] = n32
        self.elements[8] = n33

    def identity(mut self):
        """Reset this matrix to the identity."""
        self.set(1, 0, 0, 0, 1, 0, 0, 0, 1)

    def transpose(mut self):
        """Swap this matrix's rows and columns in place."""
        for row in range(3):  # pragma: no branch
            for column in range(row + 1, 3):
                var high = self.elements[column * 3 + row]
                self.elements[column * 3 + row] = self.elements[
                    row * 3 + column
                ]
                self.elements[row * 3 + column] = high

    def multiply(mut self, other: Self):
        """Post-multiply by `other`, giving `self * other`.

        Order matters: the right-hand matrix is applied to a point first.

        Args:
            other: The matrix to apply first.
        """
        var result = Array[Float32, 9](fill=0.0)
        # Fixed 3x3, so none of these can run zero times.
        for row in range(3):  # pragma: no branch
            for column in range(3):  # pragma: no branch
                var total = Float32(0)
                for k in range(3):  # pragma: no branch
                    total += (
                        self.elements[k * 3 + row]
                        * other.elements[column * 3 + k]
                    )
                result[column * 3 + row] = total
        self.elements = result^

    def premultiply(mut self, other: Self):
        """Pre-multiply by `other`, giving `other * self`.

        Args:
            other: The matrix to apply last.
        """
        var left = Matrix3(copy=other)
        left.multiply(self)
        self.elements = left.elements.copy()

    def __mul__(self, other: Self) -> Self:
        """Return `self * other`, three.js's `multiplyMatrices`.

        Args:
            other: The matrix applied to a vector first.

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
        for index in range(9):  # pragma: no branch
            self.elements[index] *= factor

    def extract_basis(
        self, mut x_axis: Vector3, mut y_axis: Vector3, mut z_axis: Vector3
    ):
        """Write the three columns into three vectors, three.js's
        `extractBasis`.

        Args:
            x_axis: Receives the first column.
            y_axis: Receives the second column.
            z_axis: Receives the third column.
        """
        ref e = self.elements
        x_axis = Vector3(e[0], e[1], e[2])
        y_axis = Vector3(e[3], e[4], e[5])
        z_axis = Vector3(e[6], e[7], e[8])

    def determinant(self) -> Float32:
        """Return this matrix's determinant."""
        ref e = self.elements
        var a = e[0]
        var b = e[1]
        var c = e[2]
        var d = e[3]
        var f = e[4]
        var g = e[5]
        var h = e[6]
        var i = e[7]
        var j = e[8]
        return (
            a * f * j
            - a * g * i
            - b * d * j
            + b * g * h
            + c * d * i
            - c * f * h
        )

    def invert(mut self):
        """Invert this matrix in place.

        A singular matrix is set to all zeros, which is what three.js does
        and what `Matrix4.invert` does: a deliberately conspicuous result,
        rather than one that quietly comes back unchanged.
        """
        ref e = self.elements
        var n11 = e[0]
        var n21 = e[1]
        var n31 = e[2]
        var n12 = e[3]
        var n22 = e[4]
        var n32 = e[5]
        var n13 = e[6]
        var n23 = e[7]
        var n33 = e[8]

        var t11 = n33 * n22 - n32 * n23
        var t12 = n32 * n13 - n33 * n12
        var t13 = n23 * n12 - n22 * n13

        var det = n11 * t11 + n21 * t12 + n31 * t13
        if det == 0:
            self.elements = Array[Float32, 9](fill=0.0)
            return

        var inv = Float32(1) / det
        var out = Array[Float32, 9](fill=0.0)
        out[0] = t11 * inv
        out[1] = (n31 * n23 - n33 * n21) * inv
        out[2] = (n32 * n21 - n31 * n22) * inv
        out[3] = t12 * inv
        out[4] = (n33 * n11 - n31 * n13) * inv
        out[5] = (n31 * n12 - n32 * n11) * inv
        out[6] = t13 * inv
        out[7] = (n21 * n13 - n23 * n11) * inv
        out[8] = (n22 * n11 - n21 * n12) * inv
        self.elements = out^

    def transform(self, vector: Vector3) -> Vector3:
        """Return `vector` transformed by this matrix, three.js's
        `Vector3.applyMatrix3`.

        Args:
            vector: The vector to transform.

        Returns:
            The product.
        """
        ref e = self.elements
        var x = vector.x
        var y = vector.y
        var z = vector.z
        return Vector3(
            e[0] * x + e[3] * y + e[6] * z,
            e[1] * x + e[4] * y + e[7] * z,
            e[2] * x + e[5] * y + e[8] * z,
        )

    def transform_point(self, point: Vector2) -> Vector2:
        """Return a 2D point transformed by this matrix as a 2D affine
        transform, three.js's `Vector2.applyMatrix3`: the point is taken
        with a third coordinate of one, so the last column moves it.

        Args:
            point: The point to transform.

        Returns:
            The moved point.
        """
        ref e = self.elements
        var x = point.x
        var y = point.y
        return Vector2(e[0] * x + e[3] * y + e[6], e[1] * x + e[4] * y + e[7])

    def scale(mut self, x: Float32, y: Float32):
        """Scale what this 2D transform produces by (x, y), three.js's
        `scale`: a scaling is applied after it.

        Args:
            x: The factor along x.
            y: The factor along y.
        """
        self.premultiply(Matrix3.scaling(x, y))

    def rotate(mut self, angle: Angle):
        """Turn what this 2D transform produces by `-angle`, three.js's
        `rotate`.

        The sign is three.js's: `Matrix3.rotate` exists to build a texture
        transform, and there a turn of the coordinates one way shows the
        image turned the other, so `rotate(angle)` turns the *image*
        counter-clockwise by `angle`. `Matrix3.rotation` turns the
        coordinates themselves, without the sign.

        Args:
            angle: How far to turn the image.
        """
        self.premultiply(Matrix3.rotation(-angle))

    def translate(mut self, x: Float32, y: Float32):
        """Move what this 2D transform produces by (x, y), three.js's
        `translate`: a translation is applied after it.

        Args:
            x: How far along x.
            y: How far along y.
        """
        self.premultiply(Matrix3.translation(x, y))

    def as_matrix4(self) -> Matrix4:
        """Return this matrix in the upper-left of a `Matrix4` with no
        translation, three.js's `Matrix4.setFromMatrix3`.

        Returns:
            The 4x4.
        """
        ref e = self.elements
        var out = Matrix4()
        for column in range(3):  # pragma: no branch
            for row in range(3):  # pragma: no branch
                out.elements[column * 4 + row] = e[column * 3 + row]
        return out^
