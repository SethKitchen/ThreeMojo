# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A quad that always faces the camera, from three.js `src/objects/Sprite.js`.

A sprite is a unit square with its own image, turned to face the camera
whichever way the camera looks: a label, a particle, a billboard. It
names a material and a node and nothing else. It has no geometry of its
own to name, because every sprite has the same one -- a square from
minus a half to a half with the image across it -- and three.js builds
that square once and shares it.

## Where a sprite is drawn

At its node's world position, `scale.x` meters wide and `scale.y` tall
where the scale is read off the node's world matrix, as three.js's
`sprite_vert` reads `modelMatrix`. The square is built in camera space,
so it lies flat to the image whatever the node is turned to: a node's
rotation does nothing to a sprite. The material's `rotation` turns it
about the line of sight instead, counterclockwise, as three.js's does.

`center` says which point of the square sits on the node: three.js's
`Sprite.center`, in the square's own coordinates, so the default of a
half and a half puts the node in the middle, and zero and zero puts it at
the bottom left. `Renderer.prepare` refuses a center that is not finite.

With the material's `size_attenuation` off, the square keeps its size on
the image as the node recedes, as three.js's does: the scale is
multiplied by the camera-space depth, which is what the perspective
divide is about to divide it by. Under a parallel projection nothing
shrinks with distance anyway, and the flag changes nothing.

## What a sprite is drawn with

`SpriteMaterial` in three.js, which `sprite_material` builds: a `BASIC`
material here, with a `rotation`. A sprite is unlit, as three.js's is,
and `Renderer.prepare` refuses a lit kind. Its map, its alpha map, its
alpha test, its opacity and its blending all work as they do on a mesh,
and its map's own transform is applied as a mesh's is. A wireframe is
refused: a sprite is a picture, and its edges say nothing.

## How a sprite is drawn

As two triangles, through the pipeline every other triangle goes
through: clipped, projected, filled by the triangle rule on either
backend and sorted among the meshes by its depth. That is what three.js
does too, and it is why a sprite needs no rule of its own where a point
does. A sprite is never culled for its facing: a negative scale turns it
inside out, and both sides are drawn.

## Culling

A sprite's bound is the sphere around its square, carried by its world
matrix, as three.js's `Sprite` carries its geometry's bounding sphere. It
is measured in the scene, so a sprite whose size is held on the image is
culled by where its square would be with the attenuation on. Set
`frustum_culled=False` on one that is left out wrongly.
"""

from core.object3d import NodeId
from materials.material import MaterialId
from math.vector2 import Vector2
from std.math import isfinite

# The bounding sphere of the unit square, three.js's `Sprite` geometry
# bound: half the square's diagonal.
comptime SPRITE_RADIUS = Float32(0.7071067811865476)


struct Sprite(ImplicitlyCopyable):
    """A camera-facing square with its own material, at a scene node."""

    var material: MaterialId
    var node: NodeId
    # Which point of the square sits on the node, in the square's own
    # coordinates from zero to one along each axis: three.js's `center`.
    # A half and a half, the default, is the middle.
    var center: Vector2
    # Whether `Renderer.prepare` may leave this sprite out when its bound
    # lies outside the camera frustum. On by default, as three.js's is.
    var frustum_culled: Bool

    def __init__(
        out self,
        material: MaterialId,
        node: NodeId,
        *,
        center: Vector2 = Vector2(0.5, 0.5),
        frustum_culled: Bool = True,
    ) raises:
        """Bind a stored material to a scene node.

        Whether the ids exist is not checkable here, for the reason
        `objects.mesh.Mesh` gives: a sprite holds no store. The renderer
        has them all and raises if either id is out of range.

        Args:
            material: Id of the material to draw with. It must be `BASIC`
                and not a wireframe, and `sprite_material` builds one.
                The renderer checks that, where it can see the store.
            node: Index of the scene node giving its position and scale.
            center: Which point of the square sits on the node. The
                middle unless said otherwise, as three.js's is.
            frustum_culled: Whether the renderer can skip this sprite when
                its bound is out of view.

        Raises:
            Error: If either id is negative, or the center is not finite.
        """
        if node.value < 0:
            raise Error("A sprite must name a scene node")
        if material.value < 0:
            raise Error("A sprite must name a material")
        if not isfinite(center.x) or not isfinite(center.y):
            raise Error("A sprite's center must be finite")
        self.material = material
        self.node = node
        self.center = center
        self.frustum_culled = frustum_culled
