# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Every edge of a surface as wide sticks, ported from three.js
`examples/jsm/lines/WireframeGeometry2.js`.

three.js's `WireframeGeometry2` is a `LineSegmentsGeometry` filled by
`fromWireframeGeometry( new WireframeGeometry( geometry ) )`. It is what a
`Wireframe` draws: the wireframe of a surface, with the width of a
`LineMaterial`. Here `wireframe_geometry2` returns the same pairs of
points, built by `wireframe_geometry` and laid out by
`line_segments_geometry`. A `LineSegments2` draws it. three.js's
`Wireframe` is that `LineSegments2`.
"""

from core.buffer_geometry import BufferGeometry, POSITION
from geometries.edges import wireframe_geometry
from math.vector3 import Vector3
from objects.line_segments2 import line_segments_geometry


def wireframe_geometry2(geometry: BufferGeometry) raises -> BufferGeometry:
    """Return every edge of a surface once, as a wide-line geometry,
    three.js's `new WireframeGeometry2( geometry )`.

    Args:
        geometry: The surface, which must carry positions.

    Returns:
        Two points per edge in the layout `line_segments_geometry` builds,
        for a `LineSegments2`. The edges are those `wireframe_geometry`
        finds, in its order.

    Raises:
        Error: If the geometry has no positions, or an index entry points
            past the last vertex.
    """
    var wire = wireframe_geometry(geometry)
    ref positions = wire.attribute_view(POSITION)
    var points = List[Vector3]()
    for vertex in range(positions.count()):
        points.append(positions.vector3(vertex))
    return line_segments_geometry(points)
