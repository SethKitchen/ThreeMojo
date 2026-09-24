# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The twelve edges of a box, from three.js `src/helpers/BoxHelper.js` and
`src/helpers/Box3Helper.js`.

three.js has two helpers here. `BoxHelper` takes an object, measures its
world-space bounds and draws them. `Box3Helper` takes a `Box3`. Both draw
the same twelve edges, and here they are one builder that takes the box:
a geometry's own bounds come from `BufferGeometry.bounding_box`, and a
mesh's world bounds from carrying them through `Scene.world_matrix` with
`Box3.apply_matrix4`, which is what `Box3.setFromObject` does.

The edges are the twelve three.js indexes, in its order and from its
eight corners, written out as twenty-four points, because a line
geometry here carries no index. See `objects.line`.

The helper is drawn where its points are, so a `Line` holding it belongs
on a node at the origin, as three.js's `BoxHelper` sets `matrixAutoUpdate`
off and leaves its matrix the identity. three.js draws it yellow.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from math.bounds import Box3
from math.vector3 import Vector3
from render.framebuffer import Color

# three.js's default `BoxHelper` color, `0xffff00`.
comptime DEFAULT_BOX_COLOR = Color(255, 255, 0)


def box_helper(box: Box3) raises -> BufferGeometry:
    """Return the twelve edges of `box`, for a `Line` in `SEGMENTS` mode.

    Args:
        box: The box to outline. Must hold at least one point.

    Returns:
        Twenty-four points, two per edge: the far square, the near
        square, then the four edges joining them, in three.js's order.
        No `color` attribute: the material colors it.

    Raises:
        Error: If the box is empty, which has no corners to join.
    """
    if box.is_empty():
        raise Error("A box helper needs a box that holds something")
    var positions = List[Float32]()
    append_box_edges(positions, box)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    return geometry^


def append_box_edges(mut positions: List[Float32], box: Box3):
    """Append the twelve edges of `box` to `positions`, as twenty-four
    points of three floats: the far square, the near square, then the four
    edges joining them, in three.js's order.

    `box_helper` and `helpers.octree.octree_helper` both draw boxes so.

    Args:
        positions: The floats to append to.
        box: The box. Its corners are read as they are, empty or not.
    """
    var lower = box.min
    var upper = box.max
    # three.js's eight corners, in its numbering.
    var corners: List[Vector3] = [
        Vector3(upper.x, upper.y, upper.z),
        Vector3(lower.x, upper.y, upper.z),
        Vector3(lower.x, lower.y, upper.z),
        Vector3(upper.x, lower.y, upper.z),
        Vector3(upper.x, upper.y, lower.z),
        Vector3(lower.x, upper.y, lower.z),
        Vector3(lower.x, lower.y, lower.z),
        Vector3(upper.x, lower.y, lower.z),
    ]
    # And its twelve edges, as pairs of corner numbers.
    var edges: List[Int] = [
        0,
        1,
        1,
        2,
        2,
        3,
        3,
        0,
        4,
        5,
        5,
        6,
        6,
        7,
        7,
        4,
        0,
        4,
        1,
        5,
        2,
        6,
        3,
        7,
    ]
    for index in range(len(edges)):  # pragma: no branch
        var corner = corners[edges[index]]
        positions.append(corner.x)
        positions.append(corner.y)
        positions.append(corner.z)
