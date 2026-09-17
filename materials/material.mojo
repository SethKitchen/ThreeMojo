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

`emissive` is the sixth, with an intensity and a map of its own: three.js's
`emissive`, `emissiveIntensity` and `emissiveMap` on `MeshLambertMaterial`.
It is light the surface gives off rather than reflects, so it is added after
the lights and they do not change it: a glowing surface shows in a dark
scene. `MeshBasicMaterial` has no such term, because an unlit surface
already shows its own color, and a `BASIC` material refuses one here rather
than silently adding it.

`vertex_colors` is the seventh: three.js's `vertexColors`, a flag rather
than a value, saying the geometry's `color` attribute multiplies `color` at
every vertex. It is a property of the material and not of the geometry, as
in three.js, so one geometry with colors can be drawn tinted by one material
and plain by another.

`alpha_map` and `alpha_test` are the eighth and ninth: three.js's
`alphaMap` and `alphaTest`. The map's *green* channel multiplies the
surface's alpha, as three.js's `alphamap_fragment` reads `.g` and nothing
else, and the test throws a fragment away whose alpha falls below it. Two
properties rather than one because they are useful apart: a map alone makes
a soft stencil, and a test alone makes a hard cut at the material's own
opacity. Together they make the cut-out leaf every tree in every renderer
is made of.

An alpha map holds data, not color, so it must say so twice: `LINEAR`, or
the sRGB curve would change what its bytes mean, and `IGNORED`, or
filtering would weight its green by an alpha that means nothing. The
emissive map already asks the second of those for the same reason.

Two more kinds show *data* rather than light: `NORMALS` writes the
view-space normal as a color, three.js's `MeshNormalMaterial`, and `DEPTH`
writes how far away the surface is, near white and far black, three.js's
`MeshDepthMaterial`. Neither has a color, an emissive term or vertex
colors, because neither shader reads them, and a material of either kind
refuses them here rather than silently ignoring them. What they write is
bytes, not light: the rasterizers keep it out of the fog and the tone
mapping, as they keep the uv debug view out of them.
"""

from render.framebuffer import Color, FloatColor
from render.texture_store import NO_TEXTURE, TextureId
from std.math import isfinite


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
        """Return True if this is `BASIC`, `LAMBERT`, `NORMALS` or `DEPTH`."""
        return (
            self == BASIC or self == LAMBERT or self == NORMALS or self == DEPTH
        )

    def is_data(self) -> Bool:
        """Return True if a material of this kind shows data rather than
        light: `NORMALS` or `DEPTH`.

        What such a surface writes is bytes the display must show as they
        are. Both rasterizers keep those fragments out of the lights, the
        emissive term, the fog and the tone mapping, as they keep the uv
        debug view out of them.
        """
        return self == NORMALS or self == DEPTH


# Unlit: the surface's own color, and its texture, reach the pixel as they
# are. three.js's `MeshBasicMaterial` -- a sky, a sprite, an overlay.
comptime BASIC = MaterialKind(0)
# Lit per fragment by every light in the scene. three.js's
# `MeshLambertMaterial`, and the default here because every example wants it.
comptime LAMBERT = MaterialKind(1)
# The view-space normal, written as a color: a surface square-on to the
# camera is (128, 128, 255). three.js's `MeshNormalMaterial`. Named for what
# it shows rather than `NORMAL`, which is the geometry attribute.
comptime NORMALS = MaterialKind(2)
# The depth, near white and far black: one minus the window-space depth in
# every channel, three.js's `MeshDepthMaterial` under `BasicDepthPacking`.
comptime DEPTH = MaterialKind(3)


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
    # Light the surface gives off, as authored, scaled by the intensity and
    # multiplied per texel by the map. Added after the lights and untouched
    # by them; see `emissive_light`. Black by default, so a material that
    # says nothing about it glows not at all.
    var emissive: Color
    var emissive_intensity: Float32
    var emissive_map: TextureId
    # Whether the geometry's `color` attribute multiplies `color` at every
    # vertex, three.js's `vertexColors`. Off by default, as there.
    var vertex_colors: Bool
    # A texture whose green channel multiplies this surface's alpha,
    # three.js's `alphaMap`. Sampled at the same coordinate as `map`, so
    # their transforms must agree. Data rather than color: it must be
    # `LINEAR` and `IGNORED`, which the renderer checks.
    var alpha_map: TextureId
    # The alpha a fragment must reach to be drawn at all, three.js's
    # `alphaTest`. Zero, the default, draws every fragment; anything above
    # throws away whatever falls below it, color and depth alike, which is
    # what cuts a shape out of a rectangle.
    var alpha_test: Float32

    def __init__(
        out self,
        color: Color,
        map: TextureId = NO_TEXTURE,
        side: Side = FRONT_SIDE,
        opacity: Float32 = 1.0,
        blending: Optional[Blending] = None,
        kind: MaterialKind = LAMBERT,
        emissive: Color = Color(0, 0, 0),
        emissive_intensity: Float32 = 1.0,
        emissive_map: TextureId = NO_TEXTURE,
        vertex_colors: Bool = False,
        alpha_map: TextureId = NO_TEXTURE,
        alpha_test: Float32 = 0.0,
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
                the color and texture as they are, `NORMALS` to show the
                view-space normal as a color, or `DEPTH` to show how far
                away the surface is. The last two show data rather than
                light: they take only `side`, `opacity` and `blending`, and
                `DEPTH` a `map` whose alpha cuts the surface out; `color`
                must be opaque white. `normal_material` and
                `depth_material` build them.
            emissive: Light the surface gives off, as authored in sRGB.
                Black, the default, gives off none.
            emissive_intensity: What `emissive` is scaled by. One leaves it
                as authored.
            emissive_map: Id of a texture that multiplies the emissive per
                texel, or `NO_TEXTURE`. It multiplies `emissive`, so on its
                own, over black, it adds nothing -- as in three.js.
            vertex_colors: Whether the geometry's `color` attribute, three
                or four linear floats per vertex, multiplies `color` at each
                vertex. The renderer refuses a geometry that has none when
                this is set.
            alpha_map: Id of a texture whose green channel multiplies this
                surface's alpha, or `NO_TEXTURE`. It must be built
                `LINEAR` and `alpha=IGNORED`: it holds data, not color.
                Sampled at the same coordinate as `map`, so a material
                naming both must give them one transform.
            alpha_test: The alpha a fragment must reach to be drawn, from
                zero to one. Zero draws every fragment, as in three.js.
                Above zero, a fragment below it is thrown away and claims
                no depth, so what is behind shows through the hole.

        Raises:
            Error: If `map` or `emissive_map` is a negative other than
                `NO_TEXTURE` — which would be an id nothing can ever hold
                rather than a deliberate absence — `opacity` is outside zero
                to one, `emissive_intensity` is negative, `side`, `blending`
                or `kind` holds a value that is none of its named constants,
                or `kind` is `BASIC` and any emissive term was given, which
                three.js's `MeshBasicMaterial` has no place for. A `NORMALS`
                or `DEPTH` material refuses a color that is not opaque
                white, any emissive term and vertex colors, and `NORMALS`
                refuses a map as well: neither shader reads them. A bare
                integer in their place is a compile error; a wrong value
                inside the right type is refused here. An `alpha_map` that
                is a negative other than `NO_TEXTURE`, an `alpha_test`
                outside zero to one or not finite, and an `alpha_map` on a
                `NORMALS` material are all refused too.
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
            raise Error(
                "A material's kind must be BASIC, LAMBERT, NORMALS or DEPTH"
            )
        if emissive_map.value < 0 and emissive_map != NO_TEXTURE:
            raise Error("A material's emissive map id cannot be negative")
        if alpha_map.value < 0 and alpha_map != NO_TEXTURE:
            raise Error("A material's alpha map id cannot be negative")
        if not isfinite(alpha_test) or alpha_test < 0 or alpha_test > 1:
            raise Error("An alpha test must be between zero and one")
        if emissive_intensity < 0:
            raise Error("An emissive intensity cannot be negative")
        if kind == BASIC and (
            emissive_map != NO_TEXTURE
            or _gives_off_light(emissive, emissive_intensity)
        ):
            raise Error(
                "A basic material has no emissive term: its color already"
                " shows whatever the lights do"
            )
        if kind.is_data():
            # Neither shader reads a color, an emissive term or the vertex
            # colors, so a value there is a mistake rather than a choice.
            if not _is_opaque_white(color):
                raise Error(
                    "A normal or depth material has no color: pass opaque"
                    " white, or build it with normal_material or"
                    " depth_material"
                )
            if emissive_map != NO_TEXTURE or _gives_off_light(
                emissive, emissive_intensity
            ):
                raise Error(
                    "A normal or depth material has no emissive term: it"
                    " shows data, not light"
                )
            if vertex_colors:
                raise Error(
                    "A normal or depth material has no vertex colors: it"
                    " shows data, not light"
                )
            if kind == NORMALS and (
                map != NO_TEXTURE or alpha_map != NO_TEXTURE
            ):
                raise Error(
                    "A normal material has no map: it shows the normal, not"
                    " an image"
                )
        self.color = color
        self.map = map
        self.side = side
        self.opacity = opacity
        self.kind = kind
        self.emissive = emissive
        self.emissive_intensity = emissive_intensity
        self.emissive_map = emissive_map
        self.vertex_colors = vertex_colors
        self.alpha_map = alpha_map
        self.alpha_test = alpha_test
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

    def is_data(self) -> Bool:
        """Return True if this surface shows data rather than light: a
        `NORMALS` or `DEPTH` material. See `MaterialKind.is_data`."""
        return self.kind.is_data()

    def has_alpha_map(self) -> Bool:
        """Return True if this material names a texture that thins it."""
        return self.alpha_map != NO_TEXTURE

    def is_alpha_tested(self) -> Bool:
        """Return True if a fragment of this surface can be thrown away for
        being too transparent, three.js's `alphaTest` above zero."""
        return self.alpha_test > 0

    def is_textured(self) -> Bool:
        """Return True if this material names a texture."""
        return self.map != NO_TEXTURE

    def is_transparent(self) -> Bool:
        """Return True if this surface is composited over what is behind it.

        The single answer. Everything that needs to know — the mesh sorter,
        both rasterizers — asks this rather than inspecting a color.
        """
        return self.blending == BLEND

    def is_emissive(self) -> Bool:
        """Return True if this surface gives off light of its own.

        A map alone does not count: it multiplies the emissive color, and
        black times anything is black, as in three.js.
        """
        return _gives_off_light(self.emissive, self.emissive_intensity)

    def emissive_light(self) -> FloatColor:
        """Return the light this surface gives off, linear, before its map.

        The authored color decoded from sRGB, as `Lighting.shade` decodes a
        base color, then scaled by the intensity. Alpha is not light and is
        left at one: the term never touches a fragment's alpha.
        """
        var glow = FloatColor(srgb=self.emissive)
        return FloatColor(
            glow.r * self.emissive_intensity,
            glow.g * self.emissive_intensity,
            glow.b * self.emissive_intensity,
            1.0,
        )


def _is_opaque_white(color: Color) -> Bool:
    """Return True if `color` is white with full alpha, the one color a
    material that shows data accepts."""
    return (
        color.r == 255
        and color.g == 255
        and color.b == 255
        and (color.a == 255)
    )


def normal_material(
    side: Side = FRONT_SIDE,
    opacity: Float32 = 1.0,
    blending: Optional[Blending] = None,
    alpha_test: Float32 = 0.0,
) raises -> Material:
    """Return a material that shows the view-space normal as a color,
    three.js's `MeshNormalMaterial`.

    A surface square-on to the camera is (128, 128, 255); one turned to the
    camera's right is redder, one turned up greener. The normal is the
    camera's view of it, so turning the camera turns the colors with it. A
    face seen from behind shows its normal flipped, as it is lit flipped.

    Args:
        side: `FRONT_SIDE`, `BACK_SIDE` or `DOUBLE_SIDE`.
        opacity: One for an opaque surface, less to see through it.
        blending: `OPAQUE` or `BLEND`, or unset to infer it from the
            opacity.
        alpha_test: The alpha a fragment must reach to be drawn. A normal
            material has no map, so this cuts by the opacity alone.

    Returns:
        The material, of kind `NORMALS`.

    Raises:
        Error: If `opacity` or `alpha_test` is outside zero to one, or
            `side` or `blending` holds a value that is none of its named
            constants.
    """
    return Material(
        Color(255, 255, 255),
        side=side,
        opacity=opacity,
        blending=blending,
        kind=NORMALS,
        alpha_test=alpha_test,
    )


def depth_material(
    map: TextureId = NO_TEXTURE,
    side: Side = FRONT_SIDE,
    opacity: Float32 = 1.0,
    blending: Optional[Blending] = None,
    alpha_map: TextureId = NO_TEXTURE,
    alpha_test: Float32 = 0.0,
) raises -> Material:
    """Return a material that shows how far away the surface is, near white
    and far black: three.js's `MeshDepthMaterial` under `BasicDepthPacking`.

    Every channel holds one minus the window-space depth, which runs from
    zero at the near plane to one at the far plane. A map's alpha multiplies
    the opacity, as three.js's does, so a cut-out image cuts the depth out
    too; its color is not read. The other packings are not ported.

    Args:
        map: Id of a texture whose alpha cuts the surface out, or
            `NO_TEXTURE`.
        side: `FRONT_SIDE`, `BACK_SIDE` or `DOUBLE_SIDE`.
        opacity: One for an opaque surface, less to see through it.
        blending: `OPAQUE` or `BLEND`, or unset to infer it from the
            opacity. A map's own alpha cannot be inferred from here, so a
            cut-out image needs `BLEND` to blend.
        alpha_map: Id of a texture whose green channel thins the surface,
            or `NO_TEXTURE`. three.js's `MeshDepthMaterial` has one.
        alpha_test: The alpha a fragment must reach to be drawn.

    Returns:
        The material, of kind `DEPTH`.

    Raises:
        Error: If `map` or `alpha_map` is a negative other than
            `NO_TEXTURE`, `opacity` or `alpha_test` is outside zero to one,
            or `side` or `blending` holds a value that is none of its named
            constants.
    """
    return Material(
        Color(255, 255, 255),
        map=map,
        side=side,
        opacity=opacity,
        blending=blending,
        kind=DEPTH,
        alpha_map=alpha_map,
        alpha_test=alpha_test,
    )


def _gives_off_light(emissive: Color, intensity: Float32) -> Bool:
    """Return True if an emissive color at an intensity adds any light: not
    black, and not scaled to nothing."""
    var colored = emissive.r > 0 or emissive.g > 0 or emissive.b > 0
    return colored and intensity > 0


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
