# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The convex hull of a set of points as a mesh, from three.js
`examples/jsm/geometries/ConvexGeometry.js`.

`math/convex_hull.mojo` finds the hull of the stored Float32 positions.
This writes its faces out, three vertices each, with the face's own normal
on all three, so the hull shades flat. There is no index and no texture
coordinate, as in three.js. Unlike three.js r180, Float64 inputs are rounded
before triangulation: rounding afterward can collapse an exact tiny face.
Use ConvexHull directly to retain original Float64 coordinates.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from math.convex_hull import ConvexHull
from std.math import isfinite
from math.vector3 import Vector3


def convex(points: List[Vector3]) raises -> BufferGeometry:
    """Return the convex hull of `points`, three.js's `ConvexGeometry`.

    Args:
        points: The points, in meters. Points inside the hull are left out.

    Returns:
        A geometry with `position` and `normal` attributes and no index.
        Each triangle owns its three vertices, in the hull's face order.

    Raises:
        Error: If there are fewer than four points, any number is not
            finite, or the points all lie on one line or one plane.
    """
    var doubles = List[SIMD[DType.float64, 4]]()
    for point in points:  # pragma: no branch
        doubles.append(
            SIMD[DType.float64, 4](
                Float64(point.x), Float64(point.y), Float64(point.z), 0
            )
        )
    return convex(doubles)


def convex(points: List[SIMD[DType.float64, 4]]) raises -> BufferGeometry:
    """Return the convex hull of points given in doubles, as three.js's
    `ConvexGeometry` takes them: the first three numbers of each. The
    geometry stores floats and builds its hull from those rounded positions.
    Use `ConvexHull` directly for the original Float64 supporting polytope.

    Args:
        points: The points, in meters.

    Returns:
        A geometry as the other `convex` returns.

    Raises:
        Error: As the other `convex` does. Also raises if a position cannot
            be stored as a finite Float32, or if the rounded positions do
            not span a solid within the hull's construction tolerance.
    """
    if len(points) < 4:
        raise Error("A convex hull needs at least four points")
    var stored = List[SIMD[DType.float64, 4]]()
    for point in points:  # pragma: no branch
        if (
            not isfinite(point[0])
            or not isfinite(point[1])
            or not isfinite(point[2])
        ):
            raise Error("A convex hull needs finite points")
        var x = Float32(point[0])
        var y = Float32(point[1])
        var z = Float32(point[2])
        if not isfinite(x) or not isfinite(y) or not isfinite(z):
            raise Error(
                "Convex geometry position exceeds Float32 storage range"
            )
        stored.append(
            SIMD[DType.float64, 4](Float64(x), Float64(y), Float64(z), 0)
        )
    try:
        var hull = ConvexHull(stored)
        var data = List[Float32]()
        var normals = List[Float32]()
        # Build the supporting polytope of the actual mesh coordinates.
        # Rounding an already triangulated Float64 hull can collapse faces.
        for face in range(hull.face_count()):  # pragma: no branch
            var normal = hull.face_normal(face)
            for corner in range(3):  # pragma: no branch
                var point = stored[hull.face_vertex(face, corner)]
                data.append(Float32(point[0]))
                data.append(Float32(point[1]))
                data.append(Float32(point[2]))
                normals.append(normal.x)
                normals.append(normal.y)
                normals.append(normal.z)
        var geometry = BufferGeometry()
        geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
        geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
        return geometry^
    except error:
        raise Error("Convex geometry Float32 storage: " + String(error))
