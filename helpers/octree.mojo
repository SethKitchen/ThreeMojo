# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The boxes of an octree, from three.js
`examples/jsm/helpers/OctreeHelper.js`.

The twelve edges of every box below the root, each box in turn and the
boxes below it after it, as three.js's `update` walks `subTrees`. The root
box itself is not drawn, as three.js does not draw it. Each box is written
as `helpers.box.box_helper` writes one: twenty-four points in three.js's
corner order.

three.js's helper is a `LineSegments` with a yellow `LineBasicMaterial`.
Here the geometry carries no `color` attribute, and a `BASIC` material of
`DEFAULT_OCTREE_COLOR` colors it, as `box_helper`'s does. Its points are
where the triangles are, so the `Line` belongs on a node at the origin.
Build it again after the octree changes, as three.js calls `update`.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from helpers.box import append_box_edges
from math.octree import Octree
from render.framebuffer import Color

# three.js's default `OctreeHelper` color, `0xffff00`.
comptime DEFAULT_OCTREE_COLOR = Color(255, 255, 0)


def octree_helper(octree: Octree) raises -> BufferGeometry:
    """Return the edges of every box below an octree's root, for a `Line`
    in `SEGMENTS` mode.

    Args:
        octree: The octree, built.

    Returns:
        Twenty-four points for each box of `Octree.boxes`, in its order.
        No point for an octree that is not built or holds no triangle,
        as three.js's helper is empty then too. No `color` attribute.

    Raises:
        Error: If the attribute cannot be built.
    """
    var positions = List[Float32]()
    for box in octree.boxes():
        append_box_edges(positions, box)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    return geometry^
