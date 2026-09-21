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
three.js, and is turned off to prove the culling changes nothing, which is
what the renderer's tests use it for.

It used to say here that nothing moved a vertex after the geometry was
built, so a bound always described what it bounded. Morph targets are the
thing that moves one. A mesh whose weights are not all zero is left in
whatever its bound says, because the bound describes the face the mesh is
no longer wearing; see `Renderer.prepare`.

## Morph target influences

`morph_influences` is three.js's `morphTargetInfluences`: how much of each
of the geometry's morph targets this mesh wears. The geometry holds the
targets and the mesh holds the numbers, which is what lets two meshes share
one head and pull different faces.

They are a fixed row of eight rather than a list, because eight is
three.js's own ceiling and because a row of numbers leaves a `Mesh`
implicitly copyable -- a scene adds one by value, and a list field would
have made every `add_mesh` call consume its argument instead. The influence
of a target the geometry does not have is simply never read.

Color used to live here, with a note saying a `Material` would be ceremony
until there was a second property to put in it. Textures were that second
property, and `side` a third; see `materials.material`.
"""

from core.buffer_geometry import MAX_MORPH_TARGETS
from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId
from std.math import isfinite


struct Mesh(ImplicitlyCopyable):
    """A geometry drawn with a given material at a given scene node."""

    var geometry: GeometryId
    var material: MaterialId
    var node: NodeId
    # Whether `Renderer.prepare` may leave this mesh out when its bounding
    # sphere, carried to world space, lies outside the camera's frustum.
    var frustum_culled: Bool
    # How much of each of the geometry's morph targets this mesh wears:
    # three.js's `morphTargetInfluences`. See the module docstring.
    var morph_influences: SIMD[DType.float32, MAX_MORPH_TARGETS]
    # Whether this mesh is drawn into the shadow maps of the lights that
    # cast, and whether the lights' shadows fall on it: three.js's
    # `castShadow` and `receiveShadow`, both off by default as there.
    # See `lights.shadow`.
    var cast_shadow: Bool
    var receive_shadow: Bool

    def __init__(
        out self,
        geometry: GeometryId,
        material: MaterialId,
        node: NodeId,
        *,
        frustum_culled: Bool = True,
        cast_shadow: Bool = False,
        receive_shadow: Bool = False,
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
            cast_shadow: Whether this mesh is drawn into the shadow maps,
                three.js's `castShadow`. Off unless said otherwise.
            receive_shadow: Whether the shadows fall on this mesh,
                three.js's `receiveShadow`. Off unless said otherwise.

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
        self.morph_influences = SIMD[DType.float32, MAX_MORPH_TARGETS](0)
        self.cast_shadow = cast_shadow
        self.receive_shadow = receive_shadow

    def set_morph_influence(mut self, target: Int, weight: Float32) raises:
        """Set how much of one morph target this mesh wears.

        Args:
            target: Which of the geometry's targets, from zero.
            weight: How much of it. One wears the target outright, zero
                leaves the base shape, and the numbers between mix. Values
                outside that range are allowed, as three.js allows them:
                they overshoot, which is how a smile becomes a grin.

        Raises:
            Error: If there is no such target, or the weight is not a
                number.
        """
        if target < 0 or target >= MAX_MORPH_TARGETS:
            raise Error("A mesh has eight morph target influences")
        if not isfinite(weight):
            raise Error("A morph influence must be a number")
        self.morph_influences[target] = weight

    def morph_influence(self, target: Int) raises -> Float32:
        """Return how much of one morph target this mesh wears.

        Args:
            target: Which of the geometry's targets, from zero.

        Returns:
            Its weight.

        Raises:
            Error: If there is no such target.
        """
        if target < 0 or target >= MAX_MORPH_TARGETS:
            raise Error("A mesh has eight morph target influences")
        return self.morph_influences[target]

    def is_morphed(self) -> Bool:
        """Return True if any morph target is worn at all.

        The renderer asks before it culls: a mesh wearing a target is not
        where its geometry's bound says it is.
        """
        for target in range(MAX_MORPH_TARGETS):  # pragma: no branch
            if self.morph_influences[target] != 0:
                return True
        return False
