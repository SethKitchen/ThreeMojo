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

from math.vector3 import Vector3
from std.math import cos, sin
from units.si import Angle


struct Matrix4(ImplicitlyCopyable):
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

    def transform_point(self, point: Vector3) -> Vector3:
        """Return `point` transformed, treating it as a position (w = 1).

        The result is divided by the transformed w, which is what makes a
        perspective matrix produce perspective.
        """
        var e = self.elements.copy()
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

    def transform_direction(self, direction: Vector3) -> Vector3:
        """Return `direction` transformed, ignoring translation (w = 0).

        A direction has no position, so the translation column must not apply
        to it. The result is not renormalized.
        """
        var e = self.elements.copy()
        var x = direction.x
        var y = direction.y
        var z = direction.z
        return Vector3(
            e[0] * x + e[4] * y + e[8] * z,
            e[1] * x + e[5] * y + e[9] * z,
            e[2] * x + e[6] * y + e[10] * z,
        )


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
