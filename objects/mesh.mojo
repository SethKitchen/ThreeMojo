# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Something drawable, from three.js `src/objects/Mesh.js`.

In three.js a `Mesh` *is* an `Object3D` — it inherits its transform. Mojo has
no inheritance, and this port's transforms already live in `core.scene`'s flat
array, so a mesh instead names the scene node it is drawn at.

That split is worth keeping even where inheritance was available. A scene node
is a position; a mesh is a thing to draw. Not every node has geometry — the
pivot a cube orbits is a node and nothing else — and one geometry can be drawn
at many nodes without being copied.

Colour lives here rather than in a `Material` for now. A material with exactly
one field would be ceremony; it earns its own type when there is a second
property to put in it.
"""

from core.buffer_geometry import BufferGeometry
from render.framebuffer import Color


struct Mesh(Movable):
    """Geometry drawn in a given colour at a given scene node."""

    var geometry: BufferGeometry
    var color: Color
    var node: Int

    def __init__(
        out self, var geometry: BufferGeometry, color: Color, node: Int
    ) raises:
        """Bind a geometry and colour to a scene node.

        Args:
            geometry: What to draw.
            color: Its base colour, before shading.
            node: Index of the scene node giving its world transform.

        Raises:
            Error: If the node index is negative.
        """
        if node < 0:
            raise Error("A mesh must name a scene node")
        self.geometry = geometry^
        self.color = color
        self.node = node
