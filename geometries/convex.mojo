# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The convex hull of a set of points as a mesh, from three.js
`examples/jsm/geometries/ConvexGeometry.js`.

`math/convex_hull.mojo` finds the hull. This writes its faces out, three
vertices each, with the face's own normal on all three, so the hull shades
flat. There is no index and no texture coordinate, as in three.js.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from math.convex_hull import ConvexHull
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
    var hull = ConvexHull(points)
    var data = List[Float32]()
    var normals = List[Float32]()
    # A hull has four faces at least, so this loop cannot run zero times.
    for face in range(hull.face_count()):  # pragma: no branch
        var normal = hull.face_normal(face)
        for corner in range(3):  # pragma: no branch
            var point = points[hull.face_vertex(face, corner)]
            data.append(point.x)
            data.append(point.y)
            data.append(point.z)
            normals.append(normal.x)
            normals.append(normal.y)
            normals.append(normal.z)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    return geometry^
