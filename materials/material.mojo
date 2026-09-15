# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How a surface looks, from three.js `src/materials/Material.js`.

This type was refused three times before it was written, and the refusals are
worth keeping: a material with one field would have been ceremony, and a
renderer that already knew the color had nothing to gain from wrapping it.
What changed is that three properties turned up which are plainly per-surface
and had nowhere per-surface to live:

    color   was on `Mesh`, which is otherwise pure identity
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
once — how its color is combined, and whether it writes depth — and those
have to be the same answer everywhere. They were not: three parts of the
renderer each worked it out from a different number.

`kind` is the fifth, and the first that three.js expresses as a *class*
rather than a property: `MeshBasicMaterial` shows its own color whatever the
lights do, `MeshLambertMaterial` catches light. Every other property is
shared between the two, so here they are one struct and a tag, for the reason
`Light` is -- a store has to hold one type.
"""

from render.framebuffer import Color
from render.texture_store import NO_TEXTURE, TextureId


@fieldwise_init
struct Side(Equatable, ImplicitlyCopyable, Writable):
    """Which faces of a surface are drawn, as a type rather than a bare int.

    The same argument as `core.object3d.NodeId`: three small integers that
    mean three different things should not be interchangeable, and a bare
    `Int` accepted anything. The type stops a bare integer at compile time.
    It does not stop `Side(99)`: a struct's fields are open in Mojo, so a
    wrong value in the right type is still constructible, and `Material`
    refuses one with `is_valid`. The two checks catch different mistakes,
    and for a while only the first was made.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three sides there are."""
        return self == FRONT_SIDE or self == BACK_SIDE or self == DOUBLE_SIDE


# Draw only surfaces turned towards the camera. three.js's default.
comptime FRONT_SIDE = Side(0)
# Draw only surfaces turned away: the inside of a closed mesh.
comptime BACK_SIDE = Side(1)
# Draw both, which is what any open surface needs.
comptime DOUBLE_SIDE = Side(2)


@fieldwise_init
struct Blending(Equatable, ImplicitlyCopyable, Writable):
    """Whether a surface replaces what is behind it or mixes into it.

    A type for the reason `Side` is one. Both rasterizers read this from a
    vertex, and a bare integer neither of them recognized was once read in
    opposite directions by the two -- see `render.rasterizer`. The type does
    not stop `Blending(7)`, so `check_triangle_state` asks `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `OPAQUE` or `BLEND`."""
        return self == OPAQUE or self == BLEND


# Replace whatever is behind: depth is tested and claimed.
comptime OPAQUE = Blending(0)
# Mix with whatever is behind, source-over: depth is tested but not claimed,
# so the caller owns draw order. `Renderer.prepare` sorts.
comptime BLEND = Blending(1)


@fieldwise_init
struct MaterialKind(Equatable, ImplicitlyCopyable, Writable):
    """Whether a surface is lit, as a type rather than a bare int.

    three.js has a class per answer and this has a tag, for the reason
    `Light` is one struct with a kind rather than a trait with three
    implementations: a `MaterialStore` has to hold one type.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `BASIC` or `LAMBERT`."""
        return self == BASIC or self == LAMBERT


# Unlit: the surface's own color, and its texture, reach the pixel as they
# are. three.js's `MeshBasicMaterial` -- a sky, a sprite, an overlay.
comptime BASIC = MaterialKind(0)
# Lit per fragment by every light in the scene. three.js's
# `MeshLambertMaterial`, and the default here because every example wants it.
comptime LAMBERT = MaterialKind(1)


@fieldwise_init
struct MaterialId(Equatable, ImplicitlyCopyable, Writable):
    """Which material in a `MaterialStore`, as a type rather than a bare int.

    See `core.object3d.NodeId`.
    """

    var value: Int


struct Material(ImplicitlyCopyable):
    """A color, optionally an image, and which faces to draw."""

    var color: Color
    var map: TextureId
    var side: Side
    # How much of the light reaching this surface it stops. One is opaque;
    # anything less mixes with what is behind. Separate from the texture's
    # own alpha, and multiplied by it.
    var opacity: Float32
    # `OPAQUE` or `BLEND`, decided once here and read by everything else.
    # It used to be rediscovered from a float alpha at three separate points —
    # the mesh sorter asked the material, and both rasterizers asked the
    # vertex color — and they disagreed. A material with an opaque `opacity`
    # but a translucent base color sorted as opaque and rasterized as
    # blended, so it did not write depth and whatever was submitted after it
    # painted straight over the top.
    var blending: Blending
    # `LAMBERT` or `BASIC`: whether the lights reach this surface at all.
    var kind: MaterialKind

    def __init__(
        out self,
        color: Color,
        map: TextureId = NO_TEXTURE,
        side: Side = FRONT_SIDE,
        opacity: Float32 = 1.0,
        blending: Optional[Blending] = None,
        kind: MaterialKind = LAMBERT,
    ) raises:
        """Describe a surface.

        Args:
            color: The base color, modulated by any texture and by lighting.
            map: Id of the texture to sample, or `NO_TEXTURE`.
            side: `FRONT_SIDE`, `BACK_SIDE` or `DOUBLE_SIDE`.
            opacity: One for an opaque surface, less to see through it.
            blending: `OPAQUE` or `BLEND`. Left unset it is inferred, and
                anything that can see through — an opacity below one or a base
                color with alpha — blends. Set it to say so explicitly: a
                texture's own alpha cannot be inferred from here, so a cut-out
                image needs `BLEND` even when the material looks opaque.
            kind: `LAMBERT` to be lit by the scene's lights, `BASIC` to show
                the color and texture as they are.

        Raises:
            Error: If `map` is a negative other than `NO_TEXTURE` — which
                would be an id nothing can ever hold rather than a deliberate
                absence — `opacity` is outside zero to one, or `side`,
                `blending` or `kind` holds a value that is none of its named
                constants. A bare integer in their place is a compile error;
                a wrong value inside the right type is refused here.
        """
        if map.value < 0 and map != NO_TEXTURE:
            raise Error("A material's texture id cannot be negative")
        if opacity < 0 or opacity > 1:
            raise Error("Opacity must be between zero and one")
        if not side.is_valid():
            raise Error(
                "A material's side must be FRONT_SIDE, BACK_SIDE or DOUBLE_SIDE"
            )
        if not kind.is_valid():
            raise Error("A material's kind must be BASIC or LAMBERT")
        self.color = color
        self.map = map
        self.side = side
        self.opacity = opacity
        self.kind = kind
        # Spelled as a Bool rather than testing the Optional directly, because
        # the coverage instrumenter wraps every condition in a probe that
        # takes a Bool, and an Optional does not convert to one implicitly.
        var stated = Bool(blending)
        if stated:
            var chosen = blending.value()
            if not chosen.is_valid():
                raise Error("A material's blending must be OPAQUE or BLEND")
            self.blending = chosen
        elif opacity < 1 or color.a < 255:
            self.blending = BLEND
        else:
            self.blending = OPAQUE

    def is_lit(self) -> Bool:
        """Return True if the scene's lights reach this surface."""
        return self.kind == LAMBERT

    def is_textured(self) -> Bool:
        """Return True if this material names a texture."""
        return self.map != NO_TEXTURE

    def is_transparent(self) -> Bool:
        """Return True if this surface is composited over what is behind it.

        The single answer. Everything that needs to know — the mesh sorter,
        both rasterizers — asks this rather than inspecting a color.
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
        material is a color and two integers, so copying one is cheaper than
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
