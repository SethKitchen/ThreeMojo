# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Something drawable, from three.js `src/objects/Mesh.js`.

In three.js a `Mesh` *is* an `Object3D` holding a reference to a
`BufferGeometry` — it inherits its transform and shares its vertex data. Mojo
gives us neither inheritance nor shared references, so a mesh names both: the
scene node it is drawn at, in `core.scene`, and the geometry it draws, in
`core.geometry_store`.

That split is worth keeping even where inheritance was available. A scene node
is a position; a mesh is a thing to draw. Not every node has geometry — the
pivot a cube orbits is a node and nothing else — and one geometry can be drawn
at many nodes without being copied.

That last sentence used to be false. A mesh took its geometry by value and
moved it in, so two meshes meant two copies of the vertex array and sharing was
impossible however the comment read. Naming it by id is what made the claim
true.

A mesh is now small enough to copy freely: two indices and a colour.

Colour lives here rather than in a `Material` for now. A material with exactly
one field would be ceremony; it earns its own type when there is a second
property to put in it.
"""

from core.geometry_store import GeometryId
from render.framebuffer import Color


struct Mesh(ImplicitlyCopyable):
    """A geometry drawn in a given colour at a given scene node."""

    var geometry: GeometryId
    var color: Color
    var node: Int

    def __init__(
        out self, geometry: GeometryId, color: Color, node: Int
    ) raises:
        """Bind a stored geometry and a colour to a scene node.

        Whether the ids exist is not checkable here — a mesh does not hold the
        store or the scene — so only the obviously impossible is refused. The
        renderer has both and raises if either id is out of range.

        Args:
            geometry: Id of the geometry to draw, from `GeometryStore.add`.
            color: Its base colour, before shading.
            node: Index of the scene node giving its world transform.

        Raises:
            Error: If either id is negative.
        """
        if node < 0:
            raise Error("A mesh must name a scene node")
        if geometry < 0:
            raise Error("A mesh must name a geometry")
        self.geometry = geometry
        self.color = color
        self.node = node
