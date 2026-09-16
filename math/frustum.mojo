# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The volume a camera sees, ported from three.js `src/math/Frustum.js`.

Six planes facing inward: right, left, bottom, top, far and near, in the
order three.js keeps them. A point is in view when it is in front of all
six. A sphere or a box is in view when no plane has it wholly behind.

The planes are read off a projection matrix, and this is the trick worth
knowing. After a matrix `M` a point is in view when each of its clip-space
coordinates lies between `-w` and `w`. `x <= w` says `(row 3 - row 0) . p
>= 0`, and a row of `M` dotted with a point is a plane's distance to it, so
`row 3 - row 0` *is* the right plane, and the other five are the other
sums and differences of row 3 with rows 0, 1 and 2. Given the projection
alone the planes are in camera space; given projection times view they are
in world space, which is where a mesh's bounds are, and what the renderer
asks for.

A sphere test is six dot products, and the bound it tests is one the
renderer can carry through a transform for the cost of a matrix
multiply. That is what makes culling by bounds cheaper than the clipping
it saves: a mesh with a thousand triangles that lies wholly to the left of
the view is settled by six multiplies rather than a thousand clips.
"""

from math.bounds import Box3, Plane, Sphere
from math.matrix4 import Matrix4
from math.vector3 import Vector3

# Which plane is which in `Frustum.planes`, in three.js's order.
comptime RIGHT = 0
comptime LEFT = 1
comptime BOTTOM = 2
comptime TOP = 3
comptime FAR = 4
comptime NEAR = 5


@fieldwise_init
struct Frustum(Copyable, Movable):
    """Six planes facing inward. What lies in front of all of them is in
    view.

    Copied only on request: an array of six planes is not a value the
    compiler copies behind an assignment, and a frustum is built once per
    frame and borrowed by every test it answers."""

    var planes: Array[Plane, 6]

    @staticmethod
    def from_projection_matrix(matrix: Matrix4) raises -> Frustum:
        """Return the frustum a projection matrix sees, three.js's
        `setFromProjectionMatrix` for the WebGL coordinate system.

        Each plane is a sum or difference of the matrix's bottom row with
        one of its other rows; see the module docstring. The planes are in
        whatever space the matrix takes its input from: camera space for a
        projection, world space for a projection times a view.

        Args:
            matrix: A projection, or a projection times a view.

        Returns:
            The frustum.

        Raises:
            Error: If a plane comes out with no normal, which no projection
                does: a matrix of zeros, or one whose bottom row cancels
                another, describes no volume.
        """
        ref e = matrix.elements
        var planes: Array[Plane, 6] = [
            Frustum._plane(e, 0, -1),
            Frustum._plane(e, 0, 1),
            Frustum._plane(e, 1, 1),
            Frustum._plane(e, 1, -1),
            Frustum._plane(e, 2, -1),
            Frustum._plane(e, 2, 1),
        ]
        return Frustum(planes^)

    @staticmethod
    def _plane(e: Array[Float32, 16], row: Int, sign: Float32) raises -> Plane:
        """Return the plane `row 3 + sign * row` of a column-major matrix.

        Args:
            e: The matrix's elements.
            row: Which row to combine with the bottom one: 0 for the sides,
                1 for top and bottom, 2 for near and far.
            sign: Plus one for the plane where the coordinate is at least
                `-w`, minus one for the plane where it is at most `w`.

        Returns:
            The plane, normalized.

        Raises:
            Error: If the plane has no normal.
        """
        return Plane(
            Vector3(
                e[3] + sign * e[row],
                e[7] + sign * e[4 + row],
                e[11] + sign * e[8 + row],
            ),
            e[15] + sign * e[12 + row],
        )

    def contains_point(self, point: Vector3) -> Bool:
        """Return True if `point` is in view, a point on a plane included.

        Args:
            point: The point to test.

        Returns:
            Whether it is in front of every plane.
        """
        for index in range(6):  # pragma: no branch
            if self.planes[index].distance_to_point(point) < 0:
                return False
        return True

    def intersects_sphere(self, sphere: Sphere) -> Bool:
        """Return True if any of `sphere` is in view.

        A sphere is out of view when some plane has all of it behind: its
        center further behind than its radius. A sphere that crosses a
        plane is in view as far as this test knows, even one that crosses
        two planes outside their corner; that is the usual bargain, and a
        bound that says "draw" when it need not is still a bound. An empty
        sphere holds nothing, so nothing of it is in view.

        Args:
            sphere: The sphere to test.

        Returns:
            Whether some of it is in front of every plane.
        """
        if sphere.is_empty():
            return False
        for index in range(6):  # pragma: no branch
            if self.planes[index].distance_to_point(sphere.center) < (
                -sphere.radius
            ):
                return False
        return True

    def intersects_box(self, box: Box3) -> Bool:
        """Return True if any of `box` is in view.

        For each plane the corner furthest in front is the one that decides
        it: the box is behind the plane only if that corner is. Which
        corner it is follows from the signs of the plane's normal, as in
        three.js. The same bargain as `intersects_sphere` about corners,
        and an empty box holds nothing, so nothing of it is in view.

        Args:
            box: The box to test.

        Returns:
            Whether some of it is in front of every plane.
        """
        if box.is_empty():
            return False
        for index in range(6):  # pragma: no branch
            ref plane = self.planes[index]
            var x = box.min.x
            if plane.normal.x > 0:
                x = box.max.x
            var y = box.min.y
            if plane.normal.y > 0:
                y = box.max.y
            var z = box.min.z
            if plane.normal.z > 0:
                z = box.max.z
            if plane.distance_to_point(Vector3(x, y, z)) < 0:
                return False
        return True
