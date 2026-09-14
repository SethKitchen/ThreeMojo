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

A mesh is three ids and nothing else — where it is, what shape it is, and what
it is made of — which is as small as identity gets. They are three *different*
types rather than three integers, because adjacent same-typed parameters are
transposable and these three used to be exactly that; see `core.object3d`.

Colour used to live here, with a note saying a `Material` would be ceremony
until there was a second property to put in it. Textures were that second
property, and `side` a third; see `materials.material`.
"""

from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId


struct Mesh(ImplicitlyCopyable):
    """A geometry drawn with a given material at a given scene node."""

    var geometry: GeometryId
    var material: MaterialId
    var node: NodeId

    def __init__(
        out self, geometry: GeometryId, material: MaterialId, node: NodeId
    ) raises:
        """Bind a stored geometry and material to a scene node.

        Whether the ids exist is not checkable here — a mesh holds none of the
        three stores — so only the obviously impossible is refused. The
        renderer has them all and raises if any id is out of range.

        Args:
            geometry: Id of the geometry to draw, from `GeometryStore.add`.
            material: Id of the material to draw it with.
            node: Index of the scene node giving its world transform.

        Raises:
            Error: If any id is negative.
        """
        if node.value < 0:
            raise Error("A mesh must name a scene node")
        if geometry.value < 0:
            raise Error("A mesh must name a geometry")
        if material.value < 0:
            raise Error("A mesh must name a material")
        self.geometry = geometry
        self.material = material
        self.node = node
