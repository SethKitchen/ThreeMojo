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

A mesh is three ids and one flag — where it is, what shape it is, what it is
made of, and whether the renderer may skip it when its bounds are out of
view — which is as small as identity gets. The ids are three *different*
types rather than three integers, because adjacent same-typed parameters are
transposable and these three used to be exactly that; see `core.object3d`.

The flag is three.js's `Object3D.frustumCulled`, and it lives here rather
than on the node because here is what is drawn: a node is a transform, and
a transform has no bounds to be out of view. It is on by default, as in
three.js, and is turned off for a mesh whose geometry the bound does not
describe -- none yet, since nothing here moves a vertex after the geometry
is built -- or to prove the culling changes nothing, which is what the
renderer's tests use it for.

Color used to live here, with a note saying a `Material` would be ceremony
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
    # Whether `Renderer.prepare` may leave this mesh out when its bounding
    # sphere, carried to world space, lies outside the camera's frustum.
    var frustum_culled: Bool

    def __init__(
        out self,
        geometry: GeometryId,
        material: MaterialId,
        node: NodeId,
        *,
        frustum_culled: Bool = True,
    ) raises:
        """Bind a stored geometry and material to a scene node.

        Whether the ids exist is not checkable here — a mesh holds none of the
        three stores — so only the obviously impossible is refused. The
        renderer has them all and raises if any id is out of range.

        Args:
            geometry: Id of the geometry to draw, from `GeometryStore.add`.
            material: Id of the material to draw it with.
            node: Index of the scene node giving its world transform.
            frustum_culled: Whether the renderer may skip this mesh when
                its bounds are out of view. On unless said otherwise, as
                three.js's `frustumCulled` is.

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
        self.frustum_culled = frustum_culled
