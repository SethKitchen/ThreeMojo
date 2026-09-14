# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How a surface looks, from three.js `src/materials/Material.js`.

This type was refused three times before it was written, and the refusals are
worth keeping: a material with one field would have been ceremony, and a
renderer that already knew the colour had nothing to gain from wrapping it.
What changed is that three properties turned up which are plainly per-surface
and had nowhere per-surface to live:

    colour   was on `Mesh`, which is otherwise pure identity
    map      was on `Renderer`, so a scene could have exactly one texture
    side     was a Bool on `Renderer`, so a scene could not mix them

The middle one was the forcing move. Adding textures made "one image for the
entire scene" the rule, and two meshes with different textures impossible —
which is the first thing anyone would try.

`side` also stops being a flag and becomes what three.js has: `FRONT_SIDE`
draws surfaces facing the camera, `BACK_SIDE` only those facing away, and
`DOUBLE_SIDE` both. A Bool could express the first and the last; the middle one
is a third state, and a third state needs somewhere that can hold three values.

A material names its texture by id, into a `TextureStore`, for the reason
`Mesh` names its geometry by id: so two materials can share one image without
copying it.

`blending` is the fourth property, and the one that had to become explicit
rather than inferred. Whether a surface is composited decides two things at
once — how its colour is combined, and whether it writes depth — and those
have to be the same answer everywhere. They were not: three parts of the
renderer each worked it out from a different number.
"""

from render.framebuffer import Color
from render.texture_store import NO_TEXTURE, TextureId

# Draw only surfaces turned towards the camera. three.js's default.
comptime FRONT_SIDE = 0
# Draw only surfaces turned away: the inside of a closed mesh.
comptime BACK_SIDE = 1
# Draw both, which is what any open surface needs.
comptime DOUBLE_SIDE = 2

# Replace whatever is behind: depth is tested and claimed.
comptime OPAQUE = 0
# Mix with whatever is behind, source-over: depth is tested but not claimed,
# so the caller owns draw order. `Renderer.prepare` sorts.
comptime BLEND = 1


@fieldwise_init
struct MaterialId(Equatable, ImplicitlyCopyable, Writable):
    """Which material in a `MaterialStore`, as a type rather than a bare int.

    See `core.object3d.NodeId`.
    """

    var value: Int


struct Material(ImplicitlyCopyable):
    """A colour, optionally an image, and which faces to draw."""

    var color: Color
    var map: TextureId
    var side: Int
    # How much of the light reaching this surface it stops. One is opaque;
    # anything less mixes with what is behind. Separate from the texture's
    # own alpha, and multiplied by it.
    var opacity: Float32
    # `OPAQUE` or `BLEND`, decided once here and read by everything else.
    # It used to be rediscovered from a float alpha at three separate points —
    # the mesh sorter asked the material, and both rasterizers asked the
    # vertex colour — and they disagreed. A material with an opaque `opacity`
    # but a translucent base colour sorted as opaque and rasterized as
    # blended, so it did not write depth and whatever was submitted after it
    # painted straight over the top.
    var blending: Int

    def __init__(
        out self,
        color: Color,
        map: TextureId = NO_TEXTURE,
        side: Int = FRONT_SIDE,
        opacity: Float32 = 1.0,
        blending: Int = -1,
    ) raises:
        """Describe a surface.

        Args:
            color: The base colour, modulated by any texture and by lighting.
            map: Id of the texture to sample, or `NO_TEXTURE`.
            side: `FRONT_SIDE`, `BACK_SIDE` or `DOUBLE_SIDE`.
            opacity: One for an opaque surface, less to see through it.
            blending: `OPAQUE` or `BLEND`. Left unset it is inferred, and
                anything that can see through — an opacity below one or a base
                colour with alpha — blends. Set it to say so explicitly: a
                texture's own alpha cannot be inferred from here, so a cut-out
                image needs `BLEND` even when the material looks opaque.

        Raises:
            Error: If `side` is not one of the three, or `map` is a negative
                other than `NO_TEXTURE` — which would be an id nothing can
                ever hold rather than a deliberate absence, `opacity` is
                outside zero to one, or `blending` is not one of the two.
        """
        if side != FRONT_SIDE and side != BACK_SIDE and side != DOUBLE_SIDE:
            raise Error("Unknown material side")
        if map.value < 0 and map != NO_TEXTURE:
            raise Error("A material's texture id cannot be negative")
        if opacity < 0 or opacity > 1:
            raise Error("Opacity must be between zero and one")
        if blending != -1 and blending != OPAQUE and blending != BLEND:
            raise Error("Unknown material blending")
        self.color = color
        self.map = map
        self.side = side
        self.opacity = opacity
        if blending != -1:
            self.blending = blending
        elif opacity < 1 or color.a < 255:
            self.blending = BLEND
        else:
            self.blending = OPAQUE

    def is_textured(self) -> Bool:
        """Return True if this material names a texture."""
        return self.map != NO_TEXTURE

    def is_transparent(self) -> Bool:
        """Return True if this surface is composited over what is behind it.

        The single answer. Everything that needs to know — the mesh sorter,
        both rasterizers — asks this rather than inspecting a colour.
        """
        return self.blending == BLEND


struct MaterialStore(Movable):
    """Owns materials and hands out ids naming them.

    The same append-only shape as `GeometryStore`, for the same reason: many
    meshes share one material, so exactly one thing owns it and everything
    else names it.
    """

    var materials: List[Material]

    def __init__(out self):
        """Create an empty store."""
        self.materials = List[Material]()

    def count(self) -> Int:
        """Return how many materials the store holds."""
        return len(self.materials)

    def add(mut self, material: Material) -> MaterialId:
        """Store `material` and return the id naming it.

        Args:
            material: The material to store.

        Returns:
            Its id, valid for the life of the store.
        """
        self.materials.append(material)
        return MaterialId(len(self.materials) - 1)

    def get(self, id: MaterialId) raises -> Material:
        """Return the material with that id.

        A copy rather than a reference, unlike geometry and textures: a
        material is a colour and two integers, so copying one is cheaper than
        the borrow that would avoid it.

        Args:
            id: Which material to read.

        Returns:
            That material.

        Raises:
            Error: If no material has that id.
        """
        if id.value < 0 or id.value >= len(self.materials):
            raise Error("No material has that id")
        return self.materials[id.value]
