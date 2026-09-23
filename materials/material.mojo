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

`specular` and `shininess` are the tenth and eleventh, and they belong to
one more kind: `PHONG`, three.js's `MeshPhongMaterial`. A Lambert surface
scatters light equally in every direction, so it looks the same from
anywhere; a Phong surface also sends a highlight toward the camera, which
moves as the camera does. The highlight is tinted by `specular` and not by
`color`, which is why a red plastic ball has a white spot on it. A material
of any other kind refuses both, because no other shader here reads them.

`specular` is a *base* reflectance and not a switch. three.js's Fresnel
term, `F_Schlick`, rises toward one at a grazing angle whatever the surface
reflects head on, so a `PHONG` material with a black specular still catches
a rim where the light and the camera are both far off the normal. It is a
dim rim -- a few levels at a shininess of zero -- but it is not nothing,
and `has_highlight` says so: it asks the kind, not the color.

`gradient_map` is the twelfth, and it belongs to one more lit kind:
`TOON`, three.js's `MeshToonMaterial`. A Lambert surface fades smoothly
from lit to unlit, and a toon surface steps. The cosine each light makes
with the surface picks a tone off a ramp, and the ramp is what a cartoon
looks like: two or three flat tones with hard edges between them.

The ramp is a texture, three.js's `gradientMap`, read as a lookup table
rather than as a picture. Its top row alone is read, left to right, with
no filtering and the ends clamped. So it holds data, and must say so the
way an alpha map does: `LINEAR`, or the sRGB curve would change what its
bytes mean, and `IGNORED`, or its own alpha would weight them. A material
with no ramp gets three.js's fallback, two tones with the edge at 0.7.

A toon surface is lit but never fades to black. three.js's ramp is read
at `dot(N, L) * 0.5 + 0.5`, so a surface turned away from a lamp reads
the ramp's left end rather than zero. The fallback's left end is 0.7, so
the shaded side of a default toon surface is seven tenths lit. That is
three.js's own arithmetic, and it is what makes the look.

`matcap` is the thirteenth, and the last kind: `MATCAP`, three.js's
`MeshMatcapMaterial`. A matcap is a photograph of a sphere lit however
the artist liked, and the shader looks a surface up in it by which way
the surface is turned. So a whole lighting rig, a material and its
highlights arrive as one image, and the scene's own lights are not
consulted at all.

Which way "turned" means is measured in the camera's own frame: across
its right and up its own up axis. Turn the camera and the sphere turns
with it, which is what makes the trick work and what stops it working
for anything that has to stay put in the world.

A matcap material is unlit, like `BASIC`, and refuses an emissive term
for the same reason: the image already holds every bit of light the
surface shows. With no image, three.js falls back to a gray gradient,
dark at the bottom and pale at the top, which is a sphere lit from above.

Two more kinds show *data* rather than light: `NORMALS` writes the
view-space normal as a color, three.js's `MeshNormalMaterial`, and `DEPTH`
writes how far away the surface is, near white and far black, three.js's
`MeshDepthMaterial`. Neither has a color, an emissive term or vertex
colors, because neither shader reads them, and a material of either kind
refuses them here rather than silently ignoring them. What they write is
bytes, not light: the rasterizers keep it out of the fog and the tone
mapping, as they keep the uv debug view out of them.

`point_size` and `size_attenuation` are the fourteenth and fifteenth, and
`rotation` the sixteenth: three.js's `PointsMaterial.size` and
`sizeAttenuation`, and `SpriteMaterial.rotation` and `sizeAttenuation`.
three.js has a class for each, and both are unlit, so here they are a
`BASIC` material with three more fields, as `LineBasicMaterial` is a
`BASIC` material with none and `LineDashedMaterial` one with three. Only a
point reads the size, only a sprite reads the rotation, and both read the
attenuation, so a value on any other kind is refused: `points_material`
and `sprite_material` build them at three.js's defaults.

`env_map`, `reflectivity` and `combine` are the seventeenth through the
nineteenth: three.js's `envMap`, `reflectivity` and `combine` on
`MeshBasicMaterial`, `MeshLambertMaterial` and `MeshPhongMaterial`, the
three kinds three.js gives an environment to. The map is a `CubeTexture`,
six images sampled by direction, and the direction is the camera's view
turned back through the surface: what a mirror shows. `combine` says how
what the mirror shows joins the surface's own light, and `reflectivity`
how much of it. three.js's default is `MultiplyOperation` at a
reflectivity of one, which tints the reflection by the surface, and so
are these. A material can name `SCENE_ENVIRONMENT` instead of a cube
texture of its own, and reflect whatever the scene's `environment` names.
A toon, matcap or data material refuses all three: three.js's shaders for
them read none.
"""

from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    SCENE_ENVIRONMENT,
    CubeTextureId,
)
from render.blend import (
    ADD_EQUATION,
    BlendEquation,
    BlendFactor,
    is_valid_custom,
    pack_custom,
)
from render.framebuffer import Color, FloatColor
from render.texture_store import NO_TEXTURE, TextureId
from math.bounds import Plane
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import isfinite, min
from units.si import Angle, Length, METER, RADIAN

# No dash and no gap: a solid line, and what a material says unless asked.
comptime NO_DASH = Length(0.0, METER)
# three.js's `LineDashedMaterial` defaults, in the line's own units.
comptime DEFAULT_DASH_SIZE = Length(3.0, METER)
comptime DEFAULT_GAP_SIZE = Length(1.0, METER)
# A sprite drawn as its image is: three.js's `SpriteMaterial.rotation`.
comptime NO_ROTATION = Angle(0.0, RADIAN)
# A normal map read as authored: three.js's `normalScale` default.
comptime UNIT_NORMAL_SCALE = Vector2(1, 1)
# What glass and most plastics refract at: three.js's `ior` default, and
# the index a `STANDARD` surface's reflectance of 0.04 corresponds to.
comptime DEFAULT_IOR = Float32(1.5)
# The narrowest and widest index three.js accepts.
comptime MIN_IOR = Float32(1.0)
comptime MAX_IOR = Float32(2.333)
# How many clipping planes one material holds. three.js has no limit; the
# planes live inline here so that a material stays a plain value.
comptime MAX_CLIPPING_PLANES = 8
# What a dielectric reflects head on: three.js's `vec3(0.04)`.
comptime DIELECTRIC_REFLECTANCE = Float32(0.04)
comptime _WHITE = Color(255, 255, 255)


@fieldwise_init
struct PointSize(Equatable, ImplicitlyCopyable, Writable):
    """How big a point is drawn, in pixels, as a type rather than a bare
    float.

    A length in the scene is a `Length`, and this is not one: it is
    measured on the image, in pixels, as three.js's `PointsMaterial.size`
    is. It is a type for the reason `Side` is, so a bare float cannot stand
    in for it and a scene length cannot be handed over as a pixel count.
    `Material` refuses one that is not a positive number with `is_valid`.

    With `size_attenuation` on, a point is this many pixels across when
    it is as many meters from the camera as half the image is pixels
    tall; nearer it grows and further it shrinks. See
    `render.pointrule.attenuated_size`.
    """

    var pixels: Float32

    def is_valid(self) -> Bool:
        """Return True if this is a finite size above zero."""
        return isfinite(self.pixels) and self.pixels > 0


# One pixel across: three.js's `PointsMaterial` default.
comptime DEFAULT_POINT_SIZE = PointSize(1.0)


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
        """Return True if this is `OPAQUE`, one of the four named modes, or
        a custom mode `custom_blending` built."""
        return (self.value >= 0 and self.value <= 4) or is_valid_custom(
            self.value
        )

    def mixes(self) -> Bool:
        """Return True if a fragment mixes into the pixel rather than
        replacing it.

        Every mode but `OPAQUE` mixes. A mixing surface tests depth but
        does not claim it, and is drawn in the translucent pass.

        Returns:
            Whether this is anything but `OPAQUE`.
        """
        return self != OPAQUE


# Replace whatever is behind: depth is tested and claimed.
comptime OPAQUE = Blending(0)
# Mix with whatever is behind, source-over: depth is tested but not claimed,
# so the caller owns draw order. `Renderer.prepare` sorts. three.js's
# `NormalBlending`.
comptime BLEND = Blending(1)
# Add the fragment's light, weighed by its alpha. three.js's
# `AdditiveBlending`.
comptime ADDITIVE = Blending(2)
# Darken what is behind by the fragment's color. three.js's
# `SubtractiveBlending`.
comptime SUBTRACTIVE = Blending(3)
# Multiply what is behind by the fragment's color. three.js's
# `MultiplyBlending`.
comptime MULTIPLY = Blending(4)


def custom_blending(
    src: BlendFactor,
    dst: BlendFactor,
    equation: BlendEquation = ADD_EQUATION,
    src_alpha: Optional[BlendFactor] = None,
    dst_alpha: Optional[BlendFactor] = None,
    equation_alpha: Optional[BlendEquation] = None,
) raises -> Blending:
    """Return a custom blending mode. three.js's `CustomBlending` with
    `blendSrc`, `blendDst`, `blendEquation` and their alpha forms.

    Args:
        src: The source color's factor.
        dst: The destination color's factor.
        equation: How the color terms join.
        src_alpha: The source alpha's factor; the color's when unset.
        dst_alpha: The destination alpha's factor; the color's when unset.
        equation_alpha: How the alpha terms join; the color's when unset.

    Returns:
        The mode.

    Raises:
        Error: If a factor or an equation is not one there is.
    """
    var alpha_src = src_alpha.value() if Bool(src_alpha) else src
    var alpha_dst = dst_alpha.value() if Bool(dst_alpha) else dst
    var alpha_equation = equation_alpha.value() if Bool(
        equation_alpha
    ) else equation
    var mode = Blending(
        pack_custom(src, dst, equation, alpha_src, alpha_dst, alpha_equation)
    )
    if not mode.is_valid():
        raise Error(
            "A custom blending names a factor or an equation that is not one"
        )
    return mode


@fieldwise_init
struct Combine(Equatable, ImplicitlyCopyable, Writable):
    """How a reflected environment joins a surface's own light, as a type
    rather than a bare int: three.js's `combine`.

    A type for the reason `Blending` is one. Both rasterizers read this
    from a corner, and a bare integer neither recognized would be read one
    way by one and another way by the other. The type does not stop
    `Combine(7)`, so `Material` and `check_triangle_state` ask `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three operations there are."""
        return (
            self == MULTIPLY_OPERATION
            or self == MIX_OPERATION
            or self == ADD_OPERATION
        )


# The surface's light times the reflection, faded in by the reflectivity:
# a tinted mirror. three.js's `MultiplyOperation`, and its default.
comptime MULTIPLY_OPERATION = Combine(0)
# The surface's light faded toward the reflection by the reflectivity: a
# reflection laid over the surface. three.js's `MixOperation`.
comptime MIX_OPERATION = Combine(1)
# The reflection times the reflectivity, added to the surface's light: a
# gloss on top. three.js's `AddOperation`.
comptime ADD_OPERATION = Combine(2)


def combine_light(
    outgoing: FloatColor,
    reflection: FloatColor,
    reflectivity: Float32,
    combine: Combine,
) -> FloatColor:
    """Return a surface's light with its reflection joined to it, three.js's
    `envmap_fragment`.

        MULTIPLY  mix(outgoing, outgoing * reflection, reflectivity)
        MIX       mix(outgoing, reflection, reflectivity)
        ADD       outgoing + reflection * reflectivity

    Applied after the lights, the highlight and the emissive term and
    before the fog, exactly where three.js applies it. Alpha is coverage
    rather than light and is left as it was: three.js reads the
    reflection's `.xyz` and no more. Shared by both rasterizers, as
    `fog_mix` is, so the one arithmetic lives in one place. A `combine`
    that is none of the three is treated as `MULTIPLY_OPERATION`, which
    neither backend can reach: both refuse it before a fragment is shaded.

    Args:
        outgoing: The surface's light so far, linear.
        reflection: What the environment shows in the reflected direction,
            linear.
        reflectivity: How much of the reflection joins, from zero to one.
        combine: Which of the three operations.

    Returns:
        The combined light, with `outgoing`'s alpha.
    """
    if combine == ADD_OPERATION:
        return FloatColor(
            outgoing.r + reflection.r * reflectivity,
            outgoing.g + reflection.g * reflectivity,
            outgoing.b + reflection.b * reflectivity,
            outgoing.a,
        )
    var toward = reflection
    if combine != MIX_OPERATION:
        toward = FloatColor(
            outgoing.r * reflection.r,
            outgoing.g * reflection.g,
            outgoing.b * reflection.b,
            1.0,
        )
    # `a + (b - a) * t` and `a * (1 - t) + b * t` are one number in exact
    # arithmetic and two in Float32. A reflection is the one place here
    # where the two sides can be decades apart -- an HDR sky beside a dim
    # surface -- and the difference of two such numbers carries the larger
    # one's exponent, so adding the smaller back rounds it away. The
    # weighted sum scales each side before it adds, and keeps it.
    var keep = 1 - reflectivity
    return FloatColor(
        outgoing.r * keep + toward.r * reflectivity,
        outgoing.g * keep + toward.g * reflectivity,
        outgoing.b * keep + toward.b * reflectivity,
        outgoing.a,
    )


@fieldwise_init
struct MaterialKind(Equatable, ImplicitlyCopyable, Writable):
    """Whether a surface is lit, as a type rather than a bare int.

    three.js has a class per answer and this has a tag, for the reason
    `Light` is one struct with a kind rather than a trait with three
    implementations: a `MaterialStore` has to hold one type.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the ten kinds there are."""
        return (
            self == BASIC
            or self == LAMBERT
            or self == NORMALS
            or self == DEPTH
            or self == PHONG
            or self == TOON
            or self == MATCAP
            or self == STANDARD
            or self == PHYSICAL
            or self == SHADOW
        )

    def is_unlit(self) -> Bool:
        """Return True if the scene's lights leave a surface of this kind
        alone and it shows light of its own: `BASIC`, `MATCAP` or `SHADOW`.

        None has an emissive term, because none needs one. A basic
        surface already shows its own color whatever the lights do, a
        matcap surface shows an image that is light already, and a shadow
        surface shows its color only where the lights do not reach.
        """
        return self == BASIC or self == MATCAP or self == SHADOW

    def is_lit(self) -> Bool:
        """Return True if the scene's lights reach a surface of this kind:
        `LAMBERT`, `PHONG`, `TOON`, `STANDARD` or `PHYSICAL`.

        Both rasterizers ask this before they evaluate a light, so a kind
        that is lit in one place and not the other is not expressible.
        """
        return (
            self == LAMBERT
            or self == PHONG
            or self == TOON
            or self == STANDARD
            or self == PHYSICAL
        )

    def is_physical(self) -> Bool:
        """Return True if a surface of this kind is shaded by a metalness
        and a roughness rather than by a color and a highlight: `STANDARD`
        or `PHYSICAL`.

        Both rasterizers ask this to pick the shader, so a kind that is
        physical in one place and not the other is not expressible.
        """
        return self == STANDARD or self == PHYSICAL

    def has_normal(self) -> Bool:
        """Return True if a surface of this kind reads its normal in the
        world's frame, and so can carry a normal map or a bump map: every
        lit kind, and `MATCAP`.

        A basic surface shows its own color whatever way it is turned, and
        a depth surface shows how far away it is; neither shader reads a
        normal, so neither has anything for a map to perturb. A normal
        material reads one, but in the camera's frame, and the frame a
        map perturbs is measured in the world's, so it refuses one too.
        """
        return self.is_lit() or self == MATCAP

    def is_data(self) -> Bool:
        """Return True if a material of this kind shows data rather than
        light: `NORMALS` or `DEPTH`.

        What such a surface writes is bytes the display must show as they
        are. Both rasterizers keep those fragments out of the lights, the
        emissive term, the fog and the tone mapping, as they keep the uv
        debug view out of them.
        """
        return self == NORMALS or self == DEPTH

    def reflects(self) -> Bool:
        """Return True if a material of this kind can carry an environment
        map: `BASIC`, `LAMBERT`, `PHONG`, `STANDARD` or `PHYSICAL`.

        The five kinds three.js gives an `envMap`. A toon surface steps
        through a ramp and a matcap surface is an image already, and the
        data kinds show no light at all, so none of them has anywhere for
        a reflection to go. Both rasterizers ask this before they reflect.
        The first three join the reflection by `combine`; the physical two
        reflect by their roughness and metalness instead, and refuse a
        `reflectivity` or a `combine`.
        """
        return (
            self == BASIC
            or self == LAMBERT
            or self == PHONG
            or self == STANDARD
            or self == PHYSICAL
        )


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
# Lit per fragment like `LAMBERT`, plus a highlight that follows the camera:
# three.js's `MeshPhongMaterial`, with Blinn's half vector as three.js uses.
comptime PHONG = MaterialKind(4)
# Lit per fragment, then stepped through a ramp rather than faded smoothly:
# three.js's `MeshToonMaterial`. The ramp is `gradient_map`, or three.js's
# two-tone fallback when there is none.
comptime TOON = MaterialKind(5)
# Unlit, and looked up in an image by which way the surface is turned in
# the camera's frame: three.js's `MeshMatcapMaterial`. The image is
# `matcap`, or three.js's gray gradient when there is none.
comptime MATCAP = MaterialKind(6)
# Lit per fragment by a metalness and a roughness, with a GGX lobe and an
# environment reflected by the split sum: three.js's `MeshStandardMaterial`.
comptime STANDARD = MaterialKind(7)
# `STANDARD` with an index of refraction, a specular color and intensity,
# and a clear coat: three.js's `MeshPhysicalMaterial`, in part. Its
# transmission, sheen, iridescence and anisotropy are not ported.
comptime PHYSICAL = MaterialKind(8)
# Unlit and transparent everywhere but where a shadow falls, where it shows
# its color by how much of the light is blocked: three.js's
# `ShadowMaterial`, the surface that catches a shadow on nothing.
comptime SHADOW = MaterialKind(9)


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
    # The image a `MATCAP` surface is looked up in, three.js's `matcap`.
    # Sampled at a coordinate the surface's own normal decides rather than
    # at its texture coordinates, so its transform is never applied and it
    # never has to agree with the material's other maps.
    var matcap: TextureId
    # The ramp a `TOON` surface steps through, three.js's `gradientMap`.
    # Its top row is a lookup table read at `dot(N, L) * 0.5 + 0.5`, not a
    # picture: nearest, ends clamped, and sampled at no surface coordinate,
    # so its own transform is never applied. Data rather than color, so it
    # must be `LINEAR` and `IGNORED`, which the renderer checks.
    var gradient_map: TextureId
    # How much light this surface sends toward the camera rather than
    # scattering, three.js's `MeshPhongMaterial.specular`, as authored.
    # Black by default, so a material that says nothing about it has no
    # highlight. Only a `PHONG` material reads it.
    var specular: Color
    # How tight that highlight is, three.js's `shininess`. Zero spreads it
    # over the whole lit side; thirty is three.js's default and is what
    # `phong_material` passes.
    var shininess: Float32
    # Whether a surface of this material is drawn as the lines of its
    # triangles rather than filled, three.js's `wireframe`. It is drawn by
    # the line pass, so it is refused on anything a line cannot draw: the
    # kind must be `BASIC` and there must be no map. See `objects.line`
    # and `Renderer.prepare_lines`.
    var wireframe: Bool
    # How long each dash of a line drawn with this material is, and how
    # long the gap after it: three.js's `LineDashedMaterial.dashSize` and
    # `gapSize`, measured along the line in the geometry's own units. A
    # gap of zero, the default, is a solid line. Only a line reads them,
    # so they are refused on anything but a `BASIC` material, and on a
    # wireframe, whose edges carry no distance along them.
    var dash_size: Length
    var gap_size: Length
    # What the distance along the line is multiplied by before the dashes
    # are measured against it: three.js's `scale`. One leaves it alone.
    var dash_scale: Float32
    # Whether the surface is composited over what is behind it: three.js's
    # `transparent`. Off, the default, an opacity below one and a texture's
    # alpha change nothing but the alpha test, and every fragment is written
    # with an alpha of one, as three.js's `opaque_fragment` writes it. On,
    # the surface blends by its alpha. `blending` is the resolved policy.
    var transparent: Bool
    # How big a point drawn with this material is, three.js's
    # `PointsMaterial.size`, and whether a point or a sprite shrinks with
    # distance, three.js's `sizeAttenuation` on both. Only a point reads
    # the size and only a point or a sprite reads the attenuation, so a
    # value that is not the default is refused on anything but a `BASIC`
    # material. See `objects.points` and `objects.sprite`.
    var point_size: PointSize
    var size_attenuation: Bool
    # How far a sprite drawn with this material is turned about the line of
    # sight, counterclockwise, three.js's `SpriteMaterial.rotation`. Only a
    # sprite reads it, so a turn is refused on anything but a `BASIC`
    # material.
    var rotation: Angle
    # The cube texture this surface reflects, three.js's `envMap`, or
    # `NO_CUBE_TEXTURE` for none, or `SCENE_ENVIRONMENT` to reflect whatever
    # the scene's `environment` names. Only a `BASIC`, `LAMBERT` or `PHONG`
    # material carries one; see `MaterialKind.reflects`.
    var env_map: CubeTextureId
    # How much of the reflection joins the surface's light, from zero to
    # one, three.js's `reflectivity`. One, the default, is three.js's.
    var reflectivity: Float32
    # How the reflection joins the surface's light, three.js's `combine`.
    # `MULTIPLY_OPERATION` by default, as there. See `combine_light`.
    var combine: Combine
    # How rough a `STANDARD` or `PHYSICAL` surface is, from zero for a
    # mirror to one for chalk, three.js's `roughness`, and how much of a
    # metal it is, three.js's `metalness`. One and zero by default, as
    # there: a rough dielectric. A map for each multiplies the number per
    # texel: the roughness map's *green* channel and the metalness map's
    # *blue*, as three.js reads them, so one image can carry both. Data
    # rather than color, so each must be `LINEAR` and `IGNORED`.
    var roughness: Float32
    var metalness: Float32
    var roughness_map: TextureId
    var metalness_map: TextureId
    # What a physical surface's environment is multiplied by, three.js's
    # `envMapIntensity`. One by default, as there.
    var env_map_intensity: Float32
    # A texture whose texels are tangent-space normals, three.js's
    # `normalMap`, and what its x and y are scaled by, three.js's
    # `normalScale`. Or a texture whose red channel is a height, three.js's
    # `bumpMap`, and what that height is scaled by, three.js's `bumpScale`.
    # Either perturbs the normal every lit shader reads, so any kind that
    # reads a normal can carry one, and a kind that reads none refuses
    # both. Data rather than color, so each must be `LINEAR` and `IGNORED`.
    var normal_map: TextureId
    var normal_scale: Vector2
    var bump_map: TextureId
    var bump_scale: Float32
    # A `PHYSICAL` surface's index of refraction, three.js's `ior`, and
    # what its reflectance head on is tinted and scaled by, three.js's
    # `specularColor` and `specularIntensity`. Together they replace the
    # `STANDARD` reflectance of 0.04; see `base_reflectance`.
    var ior: Float32
    var specular_color: Color
    var specular_intensity: Float32
    # How much clear coat lies over a `PHYSICAL` surface, from zero to
    # one, three.js's `clearcoat`, and how rough that coat is, three.js's
    # `clearcoatRoughness`. Zero and zero by default, as there.
    var clearcoat: Float32
    var clearcoat_roughness: Float32
    # The material's own clipping planes, three.js's `clippingPlanes`, at
    # most `MAX_CLIPPING_PLANES`, each a unit normal and a constant packed
    # four floats apart so that a material stays a plain value. Read with
    # `clipping_planes`, set with `set_clipping_planes`.
    var _clip_planes: SIMD[DType.float32, 4 * MAX_CLIPPING_PLANES]
    var clip_plane_count: Int
    # True to cut away only what lies behind every plane rather than
    # behind any one, three.js's `clipIntersection`.
    var clip_intersection: Bool
    # True to cut the material's shadow with its planes too, three.js's
    # `clipShadows`.
    var clip_shadows: Bool

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
        specular: Color = Color(0, 0, 0),
        shininess: Float32 = 0.0,
        gradient_map: TextureId = NO_TEXTURE,
        matcap: TextureId = NO_TEXTURE,
        wireframe: Bool = False,
        transparent: Bool = False,
        dash_size: Length = NO_DASH,
        gap_size: Length = NO_DASH,
        dash_scale: Float32 = 1.0,
        point_size: PointSize = DEFAULT_POINT_SIZE,
        size_attenuation: Bool = True,
        rotation: Angle = NO_ROTATION,
        env_map: CubeTextureId = NO_CUBE_TEXTURE,
        reflectivity: Float32 = 1.0,
        combine: Combine = MULTIPLY_OPERATION,
        roughness: Float32 = 1.0,
        metalness: Float32 = 0.0,
        roughness_map: TextureId = NO_TEXTURE,
        metalness_map: TextureId = NO_TEXTURE,
        env_map_intensity: Float32 = 1.0,
        normal_map: TextureId = NO_TEXTURE,
        normal_scale: Vector2 = UNIT_NORMAL_SCALE,
        bump_map: TextureId = NO_TEXTURE,
        bump_scale: Float32 = 1.0,
        ior: Float32 = DEFAULT_IOR,
        specular_color: Color = _WHITE,
        specular_intensity: Float32 = 1.0,
        clearcoat: Float32 = 0.0,
        clearcoat_roughness: Float32 = 0.0,
    ) raises:
        """Describe a surface.

        Args:
            color: The base color, modulated by any texture and by lighting.
            map: Id of the texture to sample, or `NO_TEXTURE`.
            side: `FRONT_SIDE`, `BACK_SIDE` or `DOUBLE_SIDE`.
            opacity: One for an opaque surface, less to see through it.
                Read only by a `transparent` material and by the alpha
                test, as in three.js.
            blending: `OPAQUE` or `BLEND`. Left unset it follows
                `transparent`. Set it to say so explicitly.
            kind: `LAMBERT` to be lit by the scene's lights, `PHONG` to be
                lit and to carry a highlight as well, `BASIC` to show
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
            specular: How much light the surface sends toward the camera,
                as authored in sRGB. Black, the default, gives no
                highlight. Only a `PHONG` material has one, and any other
                kind refuses a color here. `phong_material` passes
                three.js's own default.
            shininess: How tight the highlight is; must not be negative.
                Zero spreads it over the whole lit side, as three.js
                allows. Only a `PHONG` material reads it.
            gradient_map: Id of the ramp a `TOON` surface steps through,
                or `NO_TEXTURE` for three.js's two-tone fallback. Only a
                `TOON` material reads it.
            matcap: Id of the image a `MATCAP` surface is looked up in, or
                `NO_TEXTURE` for three.js's gray gradient. Only a `MATCAP`
                material reads it.
            wireframe: Whether to draw the lines of the triangles rather
                than fill them, three.js's `wireframe`. The lines are
                drawn by the line pass, so the kind must be `BASIC` and
                there must be no map.
            transparent: Whether the surface blends over what is behind
                it, three.js's `transparent`. Off, the default, it is drawn
                opaque with an alpha of one whatever its opacity or its
                texture's alpha say, which only the alpha test reads.
            dash_size: How long each dash of a line is, along the line,
                three.js's `dashSize`. Read with `gap_size`, and only by
                a line: `line_dashed_material` passes three.js's defaults.
            gap_size: How long the gap after each dash is, three.js's
                `gapSize`. Zero, the default, is a solid line.
            dash_scale: What the distance along the line is multiplied by
                before the dashes are measured, three.js's `scale`.
            point_size: How big a point drawn with this material is, in
                pixels, three.js's `PointsMaterial.size`. One pixel by
                default, as there. Only a point reads it.
            size_attenuation: Whether a point or a sprite shrinks with its
                distance from the camera, three.js's `sizeAttenuation`.
                On by default, as there. Only a point or a sprite reads it.
            rotation: How far a sprite is turned about the line of sight,
                counterclockwise, three.js's `SpriteMaterial.rotation`.
                Zero by default. Only a sprite reads it.
            env_map: Id of the cube texture the surface reflects, three.js's
                `envMap`, or `NO_CUBE_TEXTURE` for none, or
                `SCENE_ENVIRONMENT` to reflect the scene's `environment`.
                Only a `BASIC`, `LAMBERT` or `PHONG` material reflects.
            reflectivity: How much of the reflection joins the surface's
                light, from zero to one, three.js's `reflectivity`. One
                by default, as there.
            combine: How the reflection joins, three.js's `combine`:
                `MULTIPLY_OPERATION`, the default, `MIX_OPERATION` or
                `ADD_OPERATION`. See `combine_light`. A `STANDARD` or
                `PHYSICAL` material reflects by its roughness instead and
                refuses both this and `reflectivity`.
            roughness: How rough a `STANDARD` or `PHYSICAL` surface is,
                from zero to one, three.js's `roughness`. One by default.
            metalness: How much of a metal it is, from zero to one,
                three.js's `metalness`. Zero by default.
            roughness_map: Id of a texture whose green channel multiplies
                the roughness, or `NO_TEXTURE`. Data: `LINEAR`, `IGNORED`.
            metalness_map: Id of a texture whose blue channel multiplies
                the metalness, or `NO_TEXTURE`. Data: `LINEAR`, `IGNORED`.
            env_map_intensity: What a physical surface's environment is
                multiplied by, three.js's `envMapIntensity`. One by default.
            normal_map: Id of a texture of tangent-space normals, or
                `NO_TEXTURE`. Data: `LINEAR`, `IGNORED`. Sampled at the
                same coordinate as `map`, so their transforms must agree.
            normal_scale: What the map's x and y are scaled by, three.js's
                `normalScale`. One and one by default.
            bump_map: Id of a texture whose red channel is a height, or
                `NO_TEXTURE`. Data: `LINEAR`, `IGNORED`. A material names
                a normal map or a bump map, not both.
            bump_scale: What that height is scaled by, three.js's
                `bumpScale`. One by default.
            ior: A `PHYSICAL` surface's index of refraction, from one to
                2.333, three.js's `ior`. One and a half by default.
            specular_color: What its reflectance head on is tinted by, as
                authored in sRGB, three.js's `specularColor`. White.
            specular_intensity: What that reflectance is scaled by, from
                zero to one, three.js's `specularIntensity`. One.
            clearcoat: How much clear coat lies over a `PHYSICAL` surface,
                from zero to one. Zero by default.
            clearcoat_roughness: How rough the coat is, from zero to one.
                Zero by default.

        Raises:
            Error: If `map` or `emissive_map` is a negative other than
                `NO_TEXTURE` — which would be an id nothing can ever hold
                rather than a deliberate absence — `opacity` is outside zero
                to one, `emissive_intensity` is negative, `side`, `blending`
                or `kind` holds a value that is none of its named constants,
                or a `gradient_map` is given on a kind that is not `TOON`,
                or a `matcap` on a kind that is not `MATCAP`, or either id
                is a negative other than `NO_TEXTURE`,
                or `kind` is unlit -- `BASIC` or `MATCAP` -- and any
                emissive term was given, which neither of three.js's two
                has a place for. A `NORMALS`
                or `DEPTH` material refuses a color that is not opaque
                white, any emissive term and vertex colors, and `NORMALS`
                refuses a map as well: neither shader reads them. A bare
                integer in their place is a compile error; a wrong value
                inside the right type is refused here. An `alpha_map` that
                is a negative other than `NO_TEXTURE`, an `alpha_test`
                outside zero to one or not finite, and an `alpha_map` on a
                `NORMALS` material are all refused too. A `shininess`
                that is negative or not finite is refused, and so is any
                highlight -- a `specular` that is not black, or a positive
                `shininess` -- on a kind that is not `PHONG`. A `NORMALS`
                or `DEPTH` material whose blending resolves to `BLEND`,
                whether stated or taken from `transparent`, is
                refused as well. A `wireframe` on a kind that is not
                `BASIC`, or beside a map or an alpha map, is refused: a
                line has no normal for a light to reach and no surface
                coordinate to sample a map with. A `dash_size` or
                `gap_size` that is negative or not finite is refused, as
                is a `dash_scale` that is not finite, a gap with no dash
                before it, which would draw nothing, and any dash on a
                kind that is not `BASIC` or on a wireframe. A `point_size`
                that is not a positive number, a `rotation` that is not
                finite, and any of the three -- a size that is not the
                default, attenuation off, or a turn -- on a kind that is
                not `BASIC` are refused: only a point or a sprite reads
                them, and both are drawn unlit. An `env_map` that is a
                negative other than `NO_CUBE_TEXTURE` or
                `SCENE_ENVIRONMENT`, a `reflectivity` outside zero to one
                or not finite, a `combine` that is none of the three, and
                any of the three set on a kind that does not reflect -- an
                env map at all, a reflectivity that is not one, or a
                combine that is not `MULTIPLY_OPERATION` on a `TOON`,
                `MATCAP`, `NORMALS` or `DEPTH` material -- are refused,
                as is an env map on a wireframe, which has no surface to
                reflect from. A `roughness`, `metalness`, `clearcoat`,
                `clearcoat_roughness` or `specular_intensity` outside
                zero to one or not finite, an `ior` outside one to 2.333
                or not finite, an `env_map_intensity` that is negative or
                not finite, a `normal_scale` or `bump_scale` that is not
                finite, and any map id that is a negative other than
                `NO_TEXTURE` are refused. A roughness that is not one, a
                metalness that is not zero, a roughness or metalness map,
                or an env map intensity that is not one on a kind that is
                not `STANDARD` or `PHYSICAL` is refused, and so is a
                `reflectivity` that is not one or a `combine` that is not
                the default on one that is: a physical surface reflects by
                its roughness. An `ior` that is not the default, a
                `specular_color` that is not white, a `specular_intensity`
                that is not one, or any clear coat on a kind that is not
                `PHYSICAL` is refused. A normal map or a bump map on a
                `BASIC`, `DEPTH` or `NORMALS` material is refused, which
                refuses one on a wireframe too, as are both on one
                material, a `normal_scale` that is not one and one with no
                normal map, and a `bump_scale` that is not one with no
                bump map.
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
                "A material's kind must be BASIC, LAMBERT, NORMALS, DEPTH,"
                " PHONG, TOON, MATCAP, STANDARD, PHYSICAL or SHADOW"
            )
        if gradient_map.value < 0 and gradient_map != NO_TEXTURE:
            raise Error("A material's gradient map id cannot be negative")
        if kind != TOON and gradient_map != NO_TEXTURE:
            raise Error(
                "Only a toon material steps through a ramp: give it"
                " kind=TOON, or build it with toon_material"
            )
        if matcap.value < 0 and matcap != NO_TEXTURE:
            raise Error("A material's matcap id cannot be negative")
        if kind != MATCAP and matcap != NO_TEXTURE:
            raise Error(
                "Only a matcap material is looked up in an image: give it"
                " kind=MATCAP, or build it with matcap_material"
            )
        if emissive_map.value < 0 and emissive_map != NO_TEXTURE:
            raise Error("A material's emissive map id cannot be negative")
        if alpha_map.value < 0 and alpha_map != NO_TEXTURE:
            raise Error("A material's alpha map id cannot be negative")
        if not isfinite(alpha_test) or alpha_test < 0 or alpha_test > 1:
            raise Error("An alpha test must be between zero and one")
        if not isfinite(shininess) or shininess < 0:
            raise Error("A shininess cannot be negative")
        if kind != PHONG and (_gives_off_light(specular, 1.0) or shininess > 0):
            raise Error(
                "Only a phong material has a highlight: give it kind=PHONG,"
                " or build it with phong_material"
            )
        if emissive_intensity < 0:
            raise Error("An emissive intensity cannot be negative")
        if kind.is_unlit() and (
            emissive_map != NO_TEXTURE
            or _gives_off_light(emissive, emissive_intensity)
        ):
            raise Error(
                "An unlit material has no emissive term: a basic one shows"
                " its color whatever the lights do, and a matcap one shows"
                " an image that is light already"
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
        self.specular = specular
        self.shininess = shininess
        self.gradient_map = gradient_map
        self.matcap = matcap
        # Refused here rather than shaded differently at the far end. A
        # wireframe is drawn by the line pass, and that pass reads no
        # light and samples no image; see `render.rasterizer.rasterize_line`.
        if wireframe and kind != BASIC:
            raise Error(
                "Only a basic material can be a wireframe: a line has no"
                " surface, so it has no normal for a light to reach"
            )
        if wireframe and (map != NO_TEXTURE or alpha_map != NO_TEXTURE):
            raise Error(
                "A wireframe material has no map: a line has no surface"
                " coordinates to sample one with"
            )
        self.wireframe = wireframe
        self.transparent = transparent
        var dash = dash_size.to(METER)
        var gap = gap_size.to(METER)
        if not isfinite(dash) or dash < 0:
            raise Error("A dash size cannot be negative")
        if not isfinite(gap) or gap < 0:
            raise Error("A gap size cannot be negative")
        if not isfinite(dash_scale):
            raise Error("A dash scale must be finite")
        if gap > 0 and dash == 0:
            raise Error(
                "A dashed line needs a dash: a gap with no dash before it"
                " draws nothing"
            )
        # Refused for the reason a wireframe is refused on a lit kind: only
        # the line pass measures a distance along what it draws. A
        # wireframe is drawn by that pass, but its edges are paired from a
        # surface and carry no distance along them.
        if gap > 0 and kind != BASIC:
            raise Error(
                "Only a basic material can be dashed: dashes are measured"
                " along a line, and only a line has a length to measure"
            )
        if gap > 0 and wireframe:
            raise Error(
                "A wireframe cannot be dashed: its edges are paired from a"
                " surface and carry no distance along them"
            )
        self.dash_size = dash_size
        self.gap_size = gap_size
        self.dash_scale = dash_scale
        # Refused for the reason a dash is refused on a lit kind: only a
        # point reads a size and only a sprite reads a turn, and both are
        # drawn unlit. The default size and attenuation are what every
        # other material carries without reading, so only a change is a
        # mistake.
        if not point_size.is_valid():
            raise Error("A point size must be a positive number of pixels")
        if not isfinite(rotation.to(RADIAN)):
            raise Error("A sprite rotation must be finite")
        if kind != BASIC and (
            point_size != DEFAULT_POINT_SIZE or not size_attenuation
        ):
            raise Error(
                "Only a basic material draws points or sprites: a point has"
                " no surface for a light to reach, so only it reads a size"
                " or an attenuation"
            )
        if kind != BASIC and rotation != NO_ROTATION:
            raise Error(
                "Only a basic material draws a sprite: a sprite is unlit, so"
                " only it reads a rotation"
            )
        self.point_size = point_size
        self.size_attenuation = size_attenuation
        self.rotation = rotation
        # The environment, refused where nothing reads it: three.js's toon,
        # matcap, normal and depth shaders have no envmap chunk, so a value
        # there is a mistake rather than a choice, and a wireframe is drawn
        # by the line pass, which reads no normal to reflect from.
        if (
            env_map.value < 0
            and env_map != NO_CUBE_TEXTURE
            and env_map != SCENE_ENVIRONMENT
        ):
            raise Error("A material's env map id cannot be negative")
        if not isfinite(reflectivity) or reflectivity < 0 or reflectivity > 1:
            raise Error("A reflectivity must be between zero and one")
        if not combine.is_valid():
            raise Error(
                "A material's combine must be MULTIPLY_OPERATION,"
                " MIX_OPERATION or ADD_OPERATION"
            )
        if not kind.reflects() and (
            env_map != NO_CUBE_TEXTURE
            or reflectivity != 1
            or combine != MULTIPLY_OPERATION
        ):
            raise Error(
                "Only a basic, lambert or phong material reflects an"
                " environment: no other shader reads an env map"
            )
        if wireframe and env_map != NO_CUBE_TEXTURE:
            raise Error(
                "A wireframe material has no env map: a line has no surface"
                " to reflect from"
            )
        self.env_map = env_map
        self.reflectivity = reflectivity
        self.combine = combine
        # The physical terms, refused where nothing reads them: only the
        # two physical shaders read a roughness or a metalness, and only
        # the physical one an index, a specular color or a clear coat.
        if not _is_unit_fraction(roughness):
            raise Error("A roughness must be between zero and one")
        if not _is_unit_fraction(metalness):
            raise Error("A metalness must be between zero and one")
        if roughness_map.value < 0 and roughness_map != NO_TEXTURE:
            raise Error("A material's roughness map id cannot be negative")
        if metalness_map.value < 0 and metalness_map != NO_TEXTURE:
            raise Error("A material's metalness map id cannot be negative")
        if not isfinite(env_map_intensity) or env_map_intensity < 0:
            raise Error("An env map intensity cannot be negative")
        if not kind.is_physical() and (
            roughness != 1
            or metalness != 0
            or roughness_map != NO_TEXTURE
            or metalness_map != NO_TEXTURE
            or env_map_intensity != 1
        ):
            raise Error(
                "Only a standard or physical material has a roughness and a"
                " metalness: give it kind=STANDARD, or build it with"
                " standard_material"
            )
        if kind.is_physical() and (
            reflectivity != 1 or combine != MULTIPLY_OPERATION
        ):
            raise Error(
                "A standard or physical material reflects by its roughness"
                " and metalness: it reads no reflectivity and no combine"
            )
        if not isfinite(ior) or ior < MIN_IOR or ior > MAX_IOR:
            raise Error("An index of refraction must be between one and 2.333")
        if not _is_unit_fraction(specular_intensity):
            raise Error("A specular intensity must be between zero and one")
        if not _is_unit_fraction(clearcoat):
            raise Error("A clearcoat must be between zero and one")
        if not _is_unit_fraction(clearcoat_roughness):
            raise Error("A clearcoat roughness must be between zero and one")
        if kind != PHYSICAL and (
            ior != DEFAULT_IOR
            or not _is_opaque_white(specular_color)
            or specular_intensity != 1
            or clearcoat != 0
            or clearcoat_roughness != 0
        ):
            raise Error(
                "Only a physical material has an index of refraction, a"
                " specular color or a clear coat: give it kind=PHYSICAL, or"
                " build it with physical_material"
            )
        self.roughness = roughness
        self.metalness = metalness
        self.roughness_map = roughness_map
        self.metalness_map = metalness_map
        self.env_map_intensity = env_map_intensity
        self.ior = ior
        self.specular_color = specular_color
        self.specular_intensity = specular_intensity
        self.clearcoat = clearcoat
        self.clearcoat_roughness = clearcoat_roughness
        self._clip_planes = SIMD[DType.float32, 4 * MAX_CLIPPING_PLANES](0)
        self.clip_plane_count = 0
        self.clip_intersection = False
        self.clip_shadows = False
        # The normal and bump maps, refused where no normal is read: a
        # basic or depth shader consults none. A wireframe is `BASIC`, so
        # the same rule refuses a map on one, and the line pass never
        # sees a normal to perturb.
        if normal_map.value < 0 and normal_map != NO_TEXTURE:
            raise Error("A material's normal map id cannot be negative")
        if bump_map.value < 0 and bump_map != NO_TEXTURE:
            raise Error("A material's bump map id cannot be negative")
        if not isfinite(normal_scale.x) or not isfinite(normal_scale.y):
            raise Error("A normal scale must be finite")
        if not isfinite(bump_scale):
            raise Error("A bump scale must be finite")
        if normal_map != NO_TEXTURE and bump_map != NO_TEXTURE:
            raise Error(
                "A material names a normal map or a bump map, not both:"
                " three.js reads the normal map and ignores the bump map"
            )
        if not kind.has_normal() and (
            normal_map != NO_TEXTURE or bump_map != NO_TEXTURE
        ):
            raise Error(
                "Only a lit or matcap material has a normal map: no other"
                " shader reads a normal in the frame a map perturbs"
            )
        if normal_map == NO_TEXTURE and (
            normal_scale.x != 1 or normal_scale.y != 1
        ):
            raise Error("A normal scale needs a normal map to scale")
        if bump_map == NO_TEXTURE and bump_scale != 1:
            raise Error("A bump scale needs a bump map to scale")
        self.normal_map = normal_map
        self.normal_scale = normal_scale
        self.bump_map = bump_map
        self.bump_scale = bump_scale
        # Spelled as a Bool rather than testing the Optional directly, because
        # the coverage instrumenter wraps every condition in a probe that
        # takes a Bool, and an Optional does not convert to one implicitly.
        var stated = Bool(blending)
        if stated:
            var chosen = blending.value()
            if not chosen.is_valid():
                raise Error(
                    "A material's blending must be OPAQUE, one of the four"
                    " named modes, or a custom one"
                )
            self.blending = chosen
        elif transparent or kind == SHADOW:
            # A shadow material is transparent wherever no shadow falls,
            # which is what it is for: three.js's is built `transparent`.
            self.blending = BLEND
        else:
            self.blending = OPAQUE
        if kind == SHADOW:
            if self.blending != BLEND:
                raise Error(
                    "A shadow material blends: it is transparent wherever"
                    " no shadow falls, and an opaque one would hide the"
                    " floor it catches a shadow on"
                )
            if (
                map != NO_TEXTURE
                or alpha_map != NO_TEXTURE
                or vertex_colors
                or wireframe
            ):
                raise Error(
                    "A shadow material shows its shadow and nothing else: no"
                    " map, no alpha map, no vertex colors and no wireframe"
                )
        # A surface that shows data cannot be mixed into one that shows
        # light: the pixel would hold part of each and resolve as neither.
        # Asked of the *resolved* policy, so an opacity below one is
        # refused along with a policy stated outright -- see
        # `render.target`. A map's own alpha is another matter: an opaque
        # write keeps it, and the bytes come back exact.
        if kind.is_data() and self.blending.mixes():
            raise Error(
                "A normal or depth material cannot blend: a pixel holds its"
                " bytes or the scene's light, not a mixture of the two"
            )

    def is_lit(self) -> Bool:
        """Return True if the scene's lights reach this surface."""
        return self.kind.is_lit()

    def has_highlight(self) -> Bool:
        """Return True if this surface reflects a highlight at all, which is
        to say whether it is a `PHONG` material.

        Not "whether `specular` is set". A black specular is a base
        reflectance of zero, not a term switched off: three.js's Fresnel
        factor still rises toward one at a grazing angle, so such a surface
        catches a dim rim where a `LAMBERT` one catches nothing. Reporting
        that as "no highlight" would be a promise the shader does not keep.

        `specular` and `shininess` say how strong and how tight the
        highlight is. Nothing here switches it off; use `LAMBERT` for a
        surface that reflects none.
        """
        return self.kind == PHONG

    def specular_light(self) -> FloatColor:
        """Return how much light this surface sends toward the camera,
        linear, as `emissive_light` returns what it gives off.

        The authored color decoded from sRGB. Alpha is not light and is
        left at one: the highlight never touches a fragment's alpha.
        """
        var sheen = FloatColor(srgb=self.specular)
        return FloatColor(sheen.r, sheen.g, sheen.b, 1.0)

    def is_data(self) -> Bool:
        """Return True if this surface shows data rather than light: a
        `NORMALS` or `DEPTH` material. See `MaterialKind.is_data`."""
        return self.kind.is_data()

    def has_matcap(self) -> Bool:
        """Return True if this material names an image of its own.

        A `MATCAP` material with none is not unlookupable. It falls back
        to three.js's gray gradient instead; see
        `render.rasterizer.matcap_fallback`.
        """
        return self.matcap != NO_TEXTURE

    def has_gradient_map(self) -> Bool:
        """Return True if this material names a ramp of its own.

        A `TOON` material with no ramp is not unramped. It steps through
        three.js's two-tone fallback instead; see `lights.lighting.toon_step`.
        """
        return self.gradient_map != NO_TEXTURE

    def has_alpha_map(self) -> Bool:
        """Return True if this material names a texture that thins it."""
        return self.alpha_map != NO_TEXTURE

    def has_env_map(self) -> Bool:
        """Return True if this material reflects an environment: a cube
        texture of its own, or the scene's.

        The scene's environment counts, though the scene may name none:
        the renderer settles that when it prepares the frame, and a
        material that asked for the scene's environment in a scene without
        one reflects nothing, as three.js's does.
        """
        return self.env_map != NO_CUBE_TEXTURE

    def is_alpha_tested(self) -> Bool:
        """Return True if a fragment of this surface can be thrown away for
        being too transparent, three.js's `alphaTest` above zero."""
        return self.alpha_test > 0

    def is_physical(self) -> Bool:
        """Return True if this surface is shaded by a metalness and a
        roughness: a `STANDARD` or `PHYSICAL` material. See
        `MaterialKind.is_physical`."""
        return self.kind.is_physical()

    def has_normal_map(self) -> Bool:
        """Return True if this material names a texture of normals."""
        return self.normal_map != NO_TEXTURE

    def has_bump_map(self) -> Bool:
        """Return True if this material names a texture of heights."""
        return self.bump_map != NO_TEXTURE

    def has_clearcoat(self) -> Bool:
        """Return True if a clear coat lies over this surface at all."""
        return self.clearcoat > 0

    def base_reflectance(self) -> FloatColor:
        """Return how much of the light arriving head on this surface
        reflects, per channel, linear: the `f0` of three.js's `F_Schlick`.

        A `PHONG` material's is its `specular`, decoded. A `STANDARD`
        material's is three.js's `vec3(0.04)`, a dielectric's. A
        `PHYSICAL` material's is worked out from its index of refraction,
        `((ior - 1) / (ior + 1))^2`, tinted by its specular color, capped
        at one per channel and scaled by its specular intensity, exactly
        as `lights_physical_fragment` works it out before the metalness
        mixes the base color in. Every other kind reflects nothing.

        Alpha is not light and is left at one.
        """
        if self.kind == PHONG:
            return self.specular_light()
        if self.kind == STANDARD:
            return FloatColor(
                DIELECTRIC_REFLECTANCE,
                DIELECTRIC_REFLECTANCE,
                DIELECTRIC_REFLECTANCE,
                1.0,
            )
        if self.kind == PHYSICAL:
            var ratio = (self.ior - 1) / (self.ior + 1)
            var head_on = ratio * ratio
            var tint = FloatColor(srgb=self.specular_color)
            return FloatColor(
                min(head_on * tint.r, Float32(1)) * self.specular_intensity,
                min(head_on * tint.g, Float32(1)) * self.specular_intensity,
                min(head_on * tint.b, Float32(1)) * self.specular_intensity,
                1.0,
            )
        return FloatColor(0.0, 0.0, 0.0, 1.0)

    def is_textured(self) -> Bool:
        """Return True if this material names a texture."""
        return self.map != NO_TEXTURE

    def is_dashed(self) -> Bool:
        """Return True if a line drawn with this material has gaps in it.

        A gap of zero is a solid line whatever the dash size says, as in
        three.js, where a distance folded into a period of the dash alone
        never passes the dash's end.
        """
        return self.gap_size > NO_DASH

    def set_clipping_planes(
        mut self,
        planes: List[Plane],
        intersection: Bool = False,
        shadows: Bool = False,
    ) raises:
        """Give the material its own clipping planes, three.js's
        `clippingPlanes`, `clipIntersection` and `clipShadows`.

        A point behind a plane is cut away, in world space. The renderer
        reads these only when its `local_clipping_enabled` is set, as
        three.js reads them only under `localClippingEnabled`.

        Args:
            planes: The planes, facing the kept side. None clears them.
            intersection: True to cut away only what is behind every
                plane; False, the default, to cut what is behind any one.
            shadows: True to cut the material's shadow as well.

        Raises:
            Error: If there are more than `MAX_CLIPPING_PLANES`.
        """
        if len(planes) > MAX_CLIPPING_PLANES:
            raise Error(
                "A material holds at most ",
                MAX_CLIPPING_PLANES,
                " clipping planes, got ",
                len(planes),
            )
        self._clip_planes = SIMD[DType.float32, 4 * MAX_CLIPPING_PLANES](0)
        for index in range(len(planes)):
            ref plane = planes[index]
            self._clip_planes[index * 4] = plane.normal.x
            self._clip_planes[index * 4 + 1] = plane.normal.y
            self._clip_planes[index * 4 + 2] = plane.normal.z
            self._clip_planes[index * 4 + 3] = plane.constant
        self.clip_plane_count = len(planes)
        self.clip_intersection = intersection
        self.clip_shadows = shadows

    def clipping_planes(self) raises -> List[Plane]:
        """Return the material's clipping planes.

        Returns:
            The planes `set_clipping_planes` was given, in order.

        Raises:
            Error: Never for planes that were set: each was a plane.
        """
        var planes = List[Plane]()
        for index in range(self.clip_plane_count):
            planes.append(
                Plane(
                    Vector3(
                        self._clip_planes[index * 4],
                        self._clip_planes[index * 4 + 1],
                        self._clip_planes[index * 4 + 2],
                    ),
                    self._clip_planes[index * 4 + 3],
                )
            )
        return planes^

    def is_transparent(self) -> Bool:
        """Return True if this surface is composited over what is behind it.

        The single answer: the resolved `blending`, which follows
        `transparent` unless a policy was stated. Everything that needs to
        know — the mesh sorter, both rasterizers — asks this rather than
        inspecting a color.
        """
        return self.blending.mixes()

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


def phong_material(
    color: Color,
    map: TextureId = NO_TEXTURE,
    specular: Color = Color(17, 17, 17),
    shininess: Float32 = 30.0,
    side: Side = FRONT_SIDE,
    opacity: Float32 = 1.0,
    blending: Optional[Blending] = None,
    transparent: Bool = False,
) raises -> Material:
    """Return a lit material with a highlight, three.js's
    `MeshPhongMaterial` at three.js's defaults.

    The defaults are three.js's own: a specular of `0x111111` and a
    shininess of thirty. `Material(color, kind=PHONG)` is the same surface
    with a base reflectance of zero, because this project's defaults are
    neutral and three.js's are not. That is not a Lambert surface: the
    Fresnel term still catches a dim rim at a grazing angle. See
    `has_highlight`.

    three.js's `specularMap`, which would vary the highlight per texel, is
    not ported.

    Args:
        color: The base color, as authored in sRGB.
        map: Id of the texture that multiplies the color, or `NO_TEXTURE`.
            It does not tint the highlight.
        specular: How much light the surface sends toward the camera.
        shininess: How tight the highlight is.
        side: `FRONT_SIDE`, `BACK_SIDE` or `DOUBLE_SIDE`.
        opacity: One for an opaque surface, less to see through it.
        blending: `OPAQUE` or `BLEND`, or unset to follow `transparent`.
        transparent: Whether the surface blends over what is behind it.

    Returns:
        The material, of kind `PHONG`.

    Raises:
        Error: If `map` is a negative other than `NO_TEXTURE`, `opacity` is
            outside zero to one, `shininess` is negative or not finite, or
            `side` or `blending` holds a value that is none of its named
            constants.
    """
    return Material(
        color,
        map=map,
        side=side,
        opacity=opacity,
        blending=blending,
        transparent=transparent,
        kind=PHONG,
        specular=specular,
        shininess=shininess,
    )


def standard_material(
    color: Color,
    map: TextureId = NO_TEXTURE,
    roughness: Float32 = 1.0,
    metalness: Float32 = 0.0,
    side: Side = FRONT_SIDE,
    opacity: Float32 = 1.0,
    blending: Optional[Blending] = None,
    transparent: Bool = False,
    env_map: CubeTextureId = NO_CUBE_TEXTURE,
    env_map_intensity: Float32 = 1.0,
    roughness_map: TextureId = NO_TEXTURE,
    metalness_map: TextureId = NO_TEXTURE,
    normal_map: TextureId = NO_TEXTURE,
    normal_scale: Vector2 = UNIT_NORMAL_SCALE,
    bump_map: TextureId = NO_TEXTURE,
    bump_scale: Float32 = 1.0,
    emissive: Color = Color(0, 0, 0),
    emissive_intensity: Float32 = 1.0,
    emissive_map: TextureId = NO_TEXTURE,
) raises -> Material:
    """Return a physically shaded material, three.js's
    `MeshStandardMaterial` at three.js's defaults.

    A metalness of zero and a roughness of one: a chalky dielectric, which
    reflects four percent of the light arriving head on. Its diffuse term
    is Lambert's, its lobe is GGX with Smith's correlated visibility, and
    an environment reflects through the split sum with multiple scattering,
    all as three.js shades them. See `lights.lighting.ggx`.

    Args:
        color: The base color, as authored in sRGB.
        map: Id of the texture that multiplies the color, or `NO_TEXTURE`.
        roughness: How rough the surface is, from zero to one.
        metalness: How much of a metal it is, from zero to one.
        side: `FRONT_SIDE`, `BACK_SIDE` or `DOUBLE_SIDE`.
        opacity: One for an opaque surface, less to see through it.
        blending: `OPAQUE` or `BLEND`, or unset to follow `transparent`.
        transparent: Whether the surface blends over what is behind it.
        env_map: Id of the cube texture the surface reflects, or
            `NO_CUBE_TEXTURE`, or `SCENE_ENVIRONMENT`.
        env_map_intensity: What the environment is multiplied by.
        roughness_map: Id of a texture whose green channel multiplies the
            roughness, or `NO_TEXTURE`.
        metalness_map: Id of a texture whose blue channel multiplies the
            metalness, or `NO_TEXTURE`.
        normal_map: Id of a texture of tangent-space normals, or
            `NO_TEXTURE`.
        normal_scale: What the normal map's x and y are scaled by.
        bump_map: Id of a texture whose red channel is a height, or
            `NO_TEXTURE`.
        bump_scale: What that height is scaled by.
        emissive: Light the surface gives off, as authored in sRGB.
        emissive_intensity: What `emissive` is scaled by.
        emissive_map: Id of a texture that multiplies the emissive, or
            `NO_TEXTURE`.

    Returns:
        The material, of kind `STANDARD`.

    Raises:
        Error: If any argument holds a value `Material` refuses; see there.
    """
    return Material(
        color,
        map=map,
        side=side,
        opacity=opacity,
        blending=blending,
        transparent=transparent,
        kind=STANDARD,
        emissive=emissive,
        emissive_intensity=emissive_intensity,
        emissive_map=emissive_map,
        env_map=env_map,
        roughness=roughness,
        metalness=metalness,
        roughness_map=roughness_map,
        metalness_map=metalness_map,
        env_map_intensity=env_map_intensity,
        normal_map=normal_map,
        normal_scale=normal_scale,
        bump_map=bump_map,
        bump_scale=bump_scale,
    )


def physical_material(
    color: Color,
    map: TextureId = NO_TEXTURE,
    roughness: Float32 = 1.0,
    metalness: Float32 = 0.0,
    ior: Float32 = DEFAULT_IOR,
    specular_color: Color = _WHITE,
    specular_intensity: Float32 = 1.0,
    clearcoat: Float32 = 0.0,
    clearcoat_roughness: Float32 = 0.0,
    side: Side = FRONT_SIDE,
    opacity: Float32 = 1.0,
    blending: Optional[Blending] = None,
    transparent: Bool = False,
    env_map: CubeTextureId = NO_CUBE_TEXTURE,
    env_map_intensity: Float32 = 1.0,
    roughness_map: TextureId = NO_TEXTURE,
    metalness_map: TextureId = NO_TEXTURE,
    normal_map: TextureId = NO_TEXTURE,
    normal_scale: Vector2 = UNIT_NORMAL_SCALE,
    bump_map: TextureId = NO_TEXTURE,
    bump_scale: Float32 = 1.0,
    emissive: Color = Color(0, 0, 0),
    emissive_intensity: Float32 = 1.0,
    emissive_map: TextureId = NO_TEXTURE,
) raises -> Material:
    """Return a physically shaded material with an index of refraction and
    a clear coat, three.js's `MeshPhysicalMaterial` at three.js's defaults.

    `standard_material` with three more knobs. The index of refraction,
    the specular color and the specular intensity together set what the
    surface reflects head on, in place of the standard 0.04; see
    `Material.base_reflectance`. The clear coat is a second, colorless
    GGX lobe over the surface, on the surface's own normal, that dims
    what is under it by its own Fresnel. three.js's transmission, sheen,
    iridescence, anisotropy and dispersion are not ported.

    Args:
        color: The base color, as authored in sRGB.
        map: Id of the texture that multiplies the color, or `NO_TEXTURE`.
        roughness: How rough the surface is, from zero to one.
        metalness: How much of a metal it is, from zero to one.
        ior: The index of refraction, from one to 2.333.
        specular_color: What the reflectance head on is tinted by.
        specular_intensity: What it is scaled by, from zero to one.
        clearcoat: How much clear coat there is, from zero to one.
        clearcoat_roughness: How rough the coat is, from zero to one.
        side: `FRONT_SIDE`, `BACK_SIDE` or `DOUBLE_SIDE`.
        opacity: One for an opaque surface, less to see through it.
        blending: `OPAQUE` or `BLEND`, or unset to follow `transparent`.
        transparent: Whether the surface blends over what is behind it.
        env_map: Id of the cube texture the surface reflects, or
            `NO_CUBE_TEXTURE`, or `SCENE_ENVIRONMENT`.
        env_map_intensity: What the environment is multiplied by.
        roughness_map: Id of a texture whose green channel multiplies the
            roughness, or `NO_TEXTURE`.
        metalness_map: Id of a texture whose blue channel multiplies the
            metalness, or `NO_TEXTURE`.
        normal_map: Id of a texture of tangent-space normals, or
            `NO_TEXTURE`.
        normal_scale: What the normal map's x and y are scaled by.
        bump_map: Id of a texture whose red channel is a height, or
            `NO_TEXTURE`.
        bump_scale: What that height is scaled by.
        emissive: Light the surface gives off, as authored in sRGB.
        emissive_intensity: What `emissive` is scaled by.
        emissive_map: Id of a texture that multiplies the emissive, or
            `NO_TEXTURE`.

    Returns:
        The material, of kind `PHYSICAL`.

    Raises:
        Error: If any argument holds a value `Material` refuses; see there.
    """
    return Material(
        color,
        map=map,
        side=side,
        opacity=opacity,
        blending=blending,
        transparent=transparent,
        kind=PHYSICAL,
        emissive=emissive,
        emissive_intensity=emissive_intensity,
        emissive_map=emissive_map,
        env_map=env_map,
        roughness=roughness,
        metalness=metalness,
        roughness_map=roughness_map,
        metalness_map=metalness_map,
        env_map_intensity=env_map_intensity,
        normal_map=normal_map,
        normal_scale=normal_scale,
        bump_map=bump_map,
        bump_scale=bump_scale,
        ior=ior,
        specular_color=specular_color,
        specular_intensity=specular_intensity,
        clearcoat=clearcoat,
        clearcoat_roughness=clearcoat_roughness,
    )


def shadow_material(
    color: Color = Color(0, 0, 0),
    opacity: Float32 = 1.0,
    side: Side = FRONT_SIDE,
) raises -> Material:
    """Return a material that shows only the shadows falling on it,
    three.js's `ShadowMaterial` at three.js's defaults.

    The surface is transparent wherever the lights that cast reach it and
    shows `color` wherever they are blocked, by how much: its alpha is
    `opacity` times one minus `Lighting.shadow_mask`, three.js's
    `opacity * (1.0 - getShadowMask())`. Black at an opacity of one is the
    default, as there: a plain shadow on whatever is behind. The mesh must
    receive shadows, as any surface must, for the mask to be read at all.
    See `lights.shadow`.

    Args:
        color: The shadow's color, as authored in sRGB.
        opacity: How dark the fullest shadow is, from zero to one.
        side: `FRONT_SIDE`, `BACK_SIDE` or `DOUBLE_SIDE`.

    Returns:
        The material, of kind `SHADOW`, which blends.

    Raises:
        Error: If `opacity` is outside zero to one or `side` is none of
            the three.
    """
    return Material(color, side=side, opacity=opacity, kind=SHADOW)


def toon_material(
    color: Color,
    map: TextureId = NO_TEXTURE,
    gradient_map: TextureId = NO_TEXTURE,
    side: Side = FRONT_SIDE,
    opacity: Float32 = 1.0,
    blending: Optional[Blending] = None,
    transparent: Bool = False,
) raises -> Material:
    """Return a lit material that steps through a ramp, three.js's
    `MeshToonMaterial`.

    Every light the surface catches is read off the ramp rather than faded
    smoothly, which is what makes the cartoon look. Pass a `gradient_map`
    to say which ramp. With none, three.js's fallback applies: two tones,
    with the edge where the cosine reads 0.7.

    A ramp is a lookup table and not a picture. Only its top row is read,
    nearest and with the ends clamped, so its size decides how many tones
    there are. Build it `LINEAR` and `IGNORED`, as an alpha map is built.

    Args:
        color: The base color, as authored in sRGB.
        map: Id of the texture that multiplies the color, or `NO_TEXTURE`.
        gradient_map: Id of the ramp, or `NO_TEXTURE` for the fallback.
        side: `FRONT_SIDE`, `BACK_SIDE` or `DOUBLE_SIDE`.
        opacity: One for an opaque surface, less to see through it.
        blending: `OPAQUE` or `BLEND`, or unset to follow `transparent`.
        transparent: Whether the surface blends over what is behind it.

    Returns:
        The material, of kind `TOON`.

    Raises:
        Error: If `map` or `gradient_map` is a negative other than
            `NO_TEXTURE`, `opacity` is outside zero to one, or `side` or
            `blending` holds a value that is none of its named constants.
    """
    return Material(
        color,
        map=map,
        side=side,
        opacity=opacity,
        blending=blending,
        transparent=transparent,
        kind=TOON,
        gradient_map=gradient_map,
    )


def matcap_material(
    matcap: TextureId = NO_TEXTURE,
    color: Color = Color(255, 255, 255),
    map: TextureId = NO_TEXTURE,
    side: Side = FRONT_SIDE,
    opacity: Float32 = 1.0,
    blending: Optional[Blending] = None,
    transparent: Bool = False,
) raises -> Material:
    """Return an unlit material looked up in an image by which way the
    surface is turned, three.js's `MeshMatcapMaterial`.

    The image comes first, because a matcap surface is the image: the
    color is a tint over it and white, the default, leaves it alone. With
    no image, three.js's gray gradient applies.

    The scene's lights are not consulted. A matcap holds a whole lighting
    rig already, which is what makes it cheap and what makes it turn with
    the camera.

    Args:
        matcap: Id of the image, or `NO_TEXTURE` for the gradient.
        color: A tint over the image, as authored in sRGB. White by
            default, which shows the image as it is.
        map: Id of the texture that multiplies the color, or `NO_TEXTURE`.
        side: `FRONT_SIDE`, `BACK_SIDE` or `DOUBLE_SIDE`.
        opacity: One for an opaque surface, less to see through it.
        blending: `OPAQUE` or `BLEND`, or unset to follow `transparent`.
        transparent: Whether the surface blends over what is behind it.

    Returns:
        The material, of kind `MATCAP`.

    Raises:
        Error: If `matcap` or `map` is a negative other than `NO_TEXTURE`,
            `opacity` is outside zero to one, or `side` or `blending` holds
            a value that is none of its named constants.
    """
    return Material(
        color,
        map=map,
        side=side,
        opacity=opacity,
        blending=blending,
        transparent=transparent,
        kind=MATCAP,
        matcap=matcap,
    )


def line_dashed_material(
    color: Color,
    dash_size: Length = DEFAULT_DASH_SIZE,
    gap_size: Length = DEFAULT_GAP_SIZE,
    scale: Float32 = 1.0,
    opacity: Float32 = 1.0,
    blending: Optional[Blending] = None,
    transparent: Bool = False,
    vertex_colors: Bool = False,
) raises -> Material:
    """Return an unlit material that draws a line in dashes, three.js's
    `LineDashedMaterial` at three.js's defaults.

    The defaults are three.js's own: a dash of three and a gap of one, in
    the geometry's units, at a scale of one. `Material(color, kind=BASIC,
    dash_size=..., gap_size=...)` is the same material spelled out.

    The distance each dash is measured along is worked out by the renderer
    from the line's own points, in its geometry's space, as three.js's
    `computeLineDistances` works it out. Nothing has to be called first.

    Args:
        color: The line's color, as authored in sRGB.
        dash_size: How long each dash is.
        gap_size: How long the gap after it is. Zero is a solid line.
        scale: What the distance along the line is multiplied by first.
        opacity: One for an opaque line, less to see through it.
        blending: `OPAQUE` or `BLEND`, or unset to follow `transparent`.
        transparent: Whether the line blends over what is behind it.
        vertex_colors: Whether the geometry's `color` attribute tints it.

    Returns:
        The material, of kind `BASIC`.

    Raises:
        Error: If `opacity` is outside zero to one, `blending` holds a
            value that is neither named constant, either size is negative
            or not finite, `scale` is not finite, or the gap is above zero
            and the dash is not.
    """
    return Material(
        color,
        opacity=opacity,
        blending=blending,
        transparent=transparent,
        kind=BASIC,
        vertex_colors=vertex_colors,
        dash_size=dash_size,
        gap_size=gap_size,
        dash_scale=scale,
    )


def points_material(
    color: Color,
    size: PointSize = DEFAULT_POINT_SIZE,
    size_attenuation: Bool = True,
    map: TextureId = NO_TEXTURE,
    alpha_map: TextureId = NO_TEXTURE,
    alpha_test: Float32 = 0.0,
    opacity: Float32 = 1.0,
    blending: Optional[Blending] = None,
    transparent: Bool = False,
    vertex_colors: Bool = False,
) raises -> Material:
    """Return an unlit material that draws each vertex as a square of
    pixels, three.js's `PointsMaterial` at three.js's defaults.

    The defaults are three.js's own: one pixel across, shrinking with
    distance. `Material(color, kind=BASIC, point_size=..., ...)` is the
    same material spelled out. See `objects.points` for what a point is
    and `render.pointrule` for which pixels it covers.

    A point has a coordinate of its own across its square, so it can
    carry a map and an alpha map, as three.js's can. The map is sampled at
    that coordinate as it is stored: its own transform is not applied, and
    the renderer refuses a map that carries one.

    Args:
        color: The points' color, as authored in sRGB.
        size: How big each point is, in pixels.
        size_attenuation: Whether a point shrinks with its distance from
            the camera.
        map: Id of the image drawn across each point, or `NO_TEXTURE`.
        alpha_map: Id of a texture whose green channel thins each point,
            or `NO_TEXTURE`. It must be built `LINEAR` and `IGNORED`.
        alpha_test: The alpha a pixel must reach to be drawn.
        opacity: One for opaque points, less to see through them.
        blending: `OPAQUE` or `BLEND`, or unset to follow `transparent`.
        transparent: Whether the points blend over what is behind them.
        vertex_colors: Whether the geometry's `color` attribute tints them.

    Returns:
        The material, of kind `BASIC`.

    Raises:
        Error: If `size` is not a positive number, `map` or `alpha_map` is
            a negative other than `NO_TEXTURE`, `opacity` or `alpha_test`
            is outside zero to one, or `blending` holds a value that is
            neither named constant.
    """
    return Material(
        color,
        map=map,
        opacity=opacity,
        blending=blending,
        transparent=transparent,
        kind=BASIC,
        vertex_colors=vertex_colors,
        alpha_map=alpha_map,
        alpha_test=alpha_test,
        point_size=size,
        size_attenuation=size_attenuation,
    )


def sprite_material(
    color: Color = Color(255, 255, 255),
    map: TextureId = NO_TEXTURE,
    alpha_map: TextureId = NO_TEXTURE,
    rotation: Angle = NO_ROTATION,
    size_attenuation: Bool = True,
    alpha_test: Float32 = 0.0,
    opacity: Float32 = 1.0,
    blending: Optional[Blending] = None,
    transparent: Bool = True,
) raises -> Material:
    """Return an unlit material for a quad that always faces the camera,
    three.js's `SpriteMaterial` at three.js's defaults.

    The defaults are three.js's own: white, so a map shows as it is;
    turned not at all; shrinking with distance; and transparent, because
    a sprite is nearly always a cut-out. `Material(color, kind=BASIC,
    rotation=..., transparent=True)` is the same material spelled out. See
    `objects.sprite`.

    Args:
        color: A tint over the image, as authored in sRGB. White, the
            default, shows the image as it is.
        map: Id of the image on the sprite, or `NO_TEXTURE`.
        alpha_map: Id of a texture whose green channel thins the sprite,
            or `NO_TEXTURE`. It must be built `LINEAR` and `IGNORED`.
        rotation: How far the sprite is turned about the line of sight,
            counterclockwise.
        size_attenuation: Whether the sprite shrinks with its distance
            from the camera. Off, it keeps its size on the image.
        alpha_test: The alpha a pixel must reach to be drawn.
        opacity: One for an opaque sprite, less to see through it.
        blending: `OPAQUE` or `BLEND`, or unset to follow `transparent`.
        transparent: Whether the sprite blends over what is behind it. On
            by default, as three.js's is.

    Returns:
        The material, of kind `BASIC`.

    Raises:
        Error: If `rotation` is not finite, `map` or `alpha_map` is a
            negative other than `NO_TEXTURE`, `opacity` or `alpha_test` is
            outside zero to one, or `blending` holds a value that is
            neither named constant.
    """
    return Material(
        color,
        map=map,
        opacity=opacity,
        blending=blending,
        transparent=transparent,
        kind=BASIC,
        alpha_map=alpha_map,
        alpha_test=alpha_test,
        size_attenuation=size_attenuation,
        rotation=rotation,
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
        opacity: One for an opaque surface, less to see through it. It
            reaches the pixel's alpha; it cannot make the surface blend,
            because a normal is not mixed with light.
        blending: `OPAQUE`, or unset, which infers it. `BLEND` is refused.
        alpha_test: The alpha a fragment must reach to be drawn. A normal
            material has no map, so this cuts by the opacity alone.

    Returns:
        The material, of kind `NORMALS`.

    Raises:
        Error: If `opacity` or `alpha_test` is outside zero to one, `side`
            or `blending` holds a value that is none of its named
            constants, or the blending resolves to `BLEND`.
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
        blending: `OPAQUE`, or unset, which infers it. `BLEND` is
            refused: a depth is not mixed with light. Cut a shape out with
            `alpha_test` instead, which discards rather than mixing.
        alpha_map: Id of a texture whose green channel thins the surface,
            or `NO_TEXTURE`. three.js's `MeshDepthMaterial` has one.
        alpha_test: The alpha a fragment must reach to be drawn.

    Returns:
        The material, of kind `DEPTH`.

    Raises:
        Error: If `map` or `alpha_map` is a negative other than
            `NO_TEXTURE`, `opacity` or `alpha_test` is outside zero to one,
            `side` or `blending` holds a value that is none of its named
            constants, or the blending resolves to `BLEND`.
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


def _is_unit_fraction(value: Float32) -> Bool:
    """Return True if `value` is finite and between zero and one."""
    return isfinite(value) and value >= 0 and value <= 1


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
