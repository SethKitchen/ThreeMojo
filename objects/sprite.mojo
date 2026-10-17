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
`frustum_culled=False` on one that is left out wrongly. The draw and
the raycast both build that square with `sprite_span` and `sprite_place`.
"""

from core.object3d import NodeId
from core.ordinal import require_non_negative
from materials.material import MaterialId
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from math.finite import require_finite_group
from std.math import cos, sin
from units.si import Angle, RADIAN

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
        require_non_negative(node.value, "A sprite must name a scene node")
        require_non_negative(material.value, "A sprite must name a material")
        require_finite_group(
            center.is_finite(),
            "A sprite's center must be finite",
        )
        self.material = material
        self.node = node
        self.center = center
        self.frustum_culled = frustum_culled


def sprite_span(
    world: Matrix4,
    center: Vector3,
    size_attenuation: Bool,
    perspective: Bool,
    rotation: Angle,
) -> Tuple[Float32, Float32, Float32, Float32]:
    """Return a sprite's camera-space width, height, and turn.

    The width and height are the world matrix's x and y column lengths.
    With attenuation off under a perspective camera, both are multiplied
    by the camera-space depth, which the perspective divide is about to
    divide by. The last two numbers are the cosine and the sine of the
    material's rotation about the line of sight.

    Error: Never.

    Args:
        world: The node's world matrix.
        center: The node's origin in camera space.
        size_attenuation: Whether the sprite shrinks with distance.
        perspective: Whether the camera divides by depth.
        rotation: The material's rotation about the line of sight.

    Returns:
        The width, the height, the cosine, and the sine.

    """
    var scale_x = world.column_length(0)
    var scale_y = world.column_length(1)
    if not size_attenuation and perspective:
        scale_x *= -center.z
        scale_y *= -center.z
    var turn = rotation.to(RADIAN)
    return scale_x, scale_y, cos(turn), sin(turn)


def sprite_place(
    center: Vector3,
    anchor: Vector2,
    unit_x: Float32,
    unit_y: Float32,
    scale_x: Float32,
    scale_y: Float32,
    turned_x: Float32,
    turned_y: Float32,
) -> Vector3:
    """Return one corner of a sprite's square in camera space.

    The corner starts on the unit square, moves so `anchor` sits on the
    node, scales, and turns about the line of sight.

    Error: Never.

    Args:
        center: The node's origin in camera space.
        anchor: Which point of the square sits on the node.
        unit_x: The corner's x on the unit square, from minus a half to a
            half.
        unit_y: The corner's y on the unit square, from minus a half to a
            half.
        scale_x: The camera-space width from `sprite_span`.
        scale_y: The camera-space height from `sprite_span`.
        turned_x: The cosine from `sprite_span`.
        turned_y: The sine from `sprite_span`.

    Returns:
        The corner, in camera space.

    """
    var aligned_x = (unit_x - (anchor.x - 0.5)) * scale_x
    var aligned_y = (unit_y - (anchor.y - 0.5)) * scale_y
    return Vector3(
        center.x + turned_x * aligned_x - turned_y * aligned_y,
        center.y + turned_y * aligned_x + turned_x * aligned_y,
        center.z,
    )
