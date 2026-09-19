# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fog, from three.js `src/scenes/Fog.js` and `src/scenes/FogExp2.js`.

Fog is scene content, as lights are: `Scene.fog` holds one, and the renderer
reads it from there, as three.js's `scene.fog` is read by its renderer. It
is one struct with a kind rather than two types, for the reason `Light` is:
a scene holds one fog, which is one of three things -- none, three.js's
`Fog`, or three.js's `FogExp2` -- and a field has to hold one type.

**What fog does.** Every fragment is mixed toward the fog color by how far it
is from the camera. three.js's `Fog` rises smoothly from nothing at `near`
to everything at `far`, a smooth step over the depth; `FogExp2` rises as
`1 - exp(-(density * depth)^2)`, which never quite reaches everything and
has no far edge to tune. The depth is the camera-space depth, three.js's
`vFogDepth = -mvPosition.z`: how far in front of the camera the fragment
is, not how far from it, so a fragment off to the side at the same depth
gets the same fog.

**The depth is a varying of its own.** Each corner carries its camera-space
depth, `RasterVertex.view_depth`, taken from the clipped camera-space
position as the renderer projects it, and a fragment interpolates it with
the same perspective correction as its color. The first version recovered
the depth from the interpolated *world* position and the view matrix's
depth row, which comes to the same number on paper and not in `Float32`:
a plane eight meters in front of a camera a million meters from the origin
interpolated to world coordinates that rounded by a sixteenth, and the
depth recovered from them wandered from 7.875 to 8.125 across one flat
surface. A depth of eight interpolated as eight stays eight.

**Mixed in linear light, before the image is encoded.** three.js's WebGL
renderer applies its fog after tone mapping and after the output
color-space conversion, on the encoded color, a quirk of shader-chunk order
that three.js itself has an issue open about, and that its newer WebGPU
renderer does not repeat: its node materials fog the linear color and then
tone map and encode it. That newer order is the one kept here, where every
other mix happens, in the linear working space, so that halfway into the
fog really is half the light of each. The fog color is decoded from sRGB on
the way in, as a light's is.
The fog reaches every material, lit or not, since three.js's
`Material.fog` defaults to on and is not ported. The uv debug view is not
fogged: it shows coordinates, not light.

**The mix is a weighted sum, not a lerp.** `surface + (fog - surface) * veil`
is the textbook form and the wrong one for light that has no top: a
surface a million times brighter than the fog color swallows the fog color
in the subtraction, and at a veil of one the fragment came out black
rather than fogged. `fog_mix` weights the two ends instead, so that at one
the surface is multiplied by zero and only the fog color remains, however
bright the surface was.

**Two boundaries, one arithmetic.** `Fog` is what a scene holds, in lengths.
`FogView` is what a rasterizer takes: the same fog as plain floats, the
color decoded. Both check their numbers, because both have open fields.
`fog_factor` and `fog_mix` are the arithmetic itself, shared with the GPU
kernel as `lights.lighting.falloff` is, and held to the same numbers by the
parity tests.
"""

from math.smoothstep import smoothstep
from render.framebuffer import Color, FloatColor
from std.math import exp, isfinite
from units.si import InverseLength, Length, METER, PER_METER


@fieldwise_init
struct FogKind(Equatable, ImplicitlyCopyable, Writable):
    """Which of the three fogs this is, as a type rather than an int.

    See `core.object3d.NodeId` for why. The type stops a bare integer at
    compile time; it does not stop `FogKind(7)`, which `Fog.validate` and
    `FogView.validate` refuse before a fragment is drawn.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `NO_FOG`, `LINEAR_FOG` or `EXP2_FOG`."""
        return self == NO_FOG or self == LINEAR_FOG or self == EXP2_FOG


# No fog at all: every fragment keeps its own color. What a scene starts with.
comptime NO_FOG = FogKind(0)
# three.js's `Fog`: nothing at `near`, everything at `far`, a smooth step
# between.
comptime LINEAR_FOG = FogKind(1)
# three.js's `FogExp2`: `1 - exp(-(density * depth)^2)`, which rises from
# nothing at the camera and never quite reaches everything.
comptime EXP2_FOG = FogKind(2)

# three.js's defaults: `Fog(color, near = 1, far = 1000)` and
# `FogExp2(color, density = 0.00025)`.
comptime DEFAULT_FOG_NEAR = Length(1.0, METER)
comptime DEFAULT_FOG_FAR = Length(1000.0, METER)
comptime DEFAULT_FOG_DENSITY = InverseLength(0.00025, PER_METER)
comptime _NO_LENGTH = Length(0.0, METER)
comptime _NO_DENSITY = InverseLength(0.0, PER_METER)


def _check_fog_numbers(
    kind: FogKind, near: Float32, far: Float32, density: Float32
) raises:
    """Refuse a kind that is none of the three, and the numbers it reads
    when they cannot draw.

    One list, asked by `Fog.validate` of the scene's lengths and by
    `FogView.validate` of the rasterizer's floats, so the two boundaries
    cannot drift apart. Only the numbers the kind reads are checked: a
    linear fog's density and an exponential fog's edges are placeholders.

    Args:
        kind: Which fog.
        near: Where a linear fog starts, in meters.
        far: Where a linear fog is complete, in meters.
        density: How fast an exponential fog thickens, per meter.

    Raises:
        Error: If the kind is unknown; a linear fog starts at a depth that
            is negative or not finite, or ends at one that is not finite or
            not beyond its start; or an exponential fog's density is
            negative or not finite.
    """
    if not kind.is_valid():
        raise Error("A fog of an unknown kind cannot be drawn")
    if kind == LINEAR_FOG:
        if not isfinite(near) or near < 0:
            raise Error(
                "A fog must start at a finite depth, not behind the camera"
            )
        if not isfinite(far) or far <= near:
            raise Error(
                "A fog's far edge must be finite and beyond its near edge"
            )
    if kind == EXP2_FOG and (not isfinite(density) or density < 0):
        raise Error("A fog's density must be finite and not negative")


@fieldwise_init
struct Fog(ImplicitlyCopyable):
    """What a scene holds: a kind, a color, and the numbers that kind reads.

    Build one with `no_fog`, `linear_fog` or `exp2_fog`, which call
    `validate`. The fields are open, as every struct's are, so `FogView`
    validates again where they are read.
    """

    var kind: FogKind
    # The color a fragment is mixed toward, as authored in sRGB.
    var color: Color
    # Where a linear fog starts and where it is complete. Read only by
    # `LINEAR_FOG`.
    var near: Length
    var far: Length
    # How fast an exponential fog thickens, per meter of depth. Read only by
    # `EXP2_FOG`.
    var density: InverseLength

    def is_on(self) -> Bool:
        """Return True if this fog changes any fragment at all."""
        return self.kind != NO_FOG

    def validate(self) raises:
        """Refuse a fog that cannot draw.

        The builders ask this of what they make, and `FogView` asks it again
        of what it is handed, because a field can be edited in between.

        Raises:
            Error: If the kind is none of the three, or the numbers the kind
                reads are not finite or are inside out; see
                `_check_fog_numbers`.
        """
        _check_fog_numbers(
            self.kind, self.near.value, self.far.value, self.density.value
        )


def no_fog() -> Fog:
    """Return the fog a scene starts with, which changes nothing.

    Returns:
        A fog of kind `NO_FOG`.
    """
    return Fog(NO_FOG, Color(0, 0, 0), _NO_LENGTH, _NO_LENGTH, _NO_DENSITY)


def linear_fog(
    color: Color,
    near: Length = DEFAULT_FOG_NEAR,
    far: Length = DEFAULT_FOG_FAR,
) raises -> Fog:
    """Return three.js's `Fog`: none at `near`, all at `far`, smooth between.

    Args:
        color: The color a fragment is mixed toward, as authored in sRGB.
        near: The depth the fog starts at. Nothing nearer is fogged.
        far: The depth the fog is complete at. Everything further is the fog
            color and nothing else.

    Returns:
        The fog.

    Raises:
        Error: If `near` is negative or not finite, which would put the
            start behind the camera or nowhere, or `far` is not finite or
            not beyond `near`, which leaves no room for the rise.
    """
    var fog = Fog(LINEAR_FOG, color, near, far, _NO_DENSITY)
    fog.validate()
    return fog


def exp2_fog(
    color: Color, density: InverseLength = DEFAULT_FOG_DENSITY
) raises -> Fog:
    """Return three.js's `FogExp2`: `1 - exp(-(density * depth)^2)`.

    Args:
        color: The color a fragment is mixed toward, as authored in sRGB.
        density: How fast the fog thickens with depth, per meter. Zero is
            no fog at all.

    Returns:
        The fog.

    Raises:
        Error: If the density is negative or not finite. The square would
            hide the sign, and a negative density is a mistake rather than a
            thinner fog.
    """
    var fog = Fog(EXP2_FOG, color, _NO_LENGTH, _NO_LENGTH, density)
    fog.validate()
    return fog


def fog_factor(
    kind: FogKind,
    depth: Float32,
    near: Float32,
    far: Float32,
    density: Float32,
) -> Float32:
    """Return how much of the fog color a fragment at `depth` shows.

    three.js's `fog_fragment`, chunk for chunk: a smooth step from `near`
    to `far` for a linear fog, `1 - exp(-(density * depth)^2)` for an
    exponential one, and nothing for no fog or a kind that is none of the
    three -- which `FogView.validate` refuses before this is ever asked.

    Args:
        kind: `LINEAR_FOG`, `EXP2_FOG` or `NO_FOG`.
        depth: The fragment's camera-space depth, interpolated from
            `RasterVertex.view_depth`.
        near: Where a linear fog starts.
        far: Where a linear fog is complete.
        density: How fast an exponential fog thickens.

    Returns:
        Zero for the fragment's own color, one for the fog color alone.
    """
    if kind == LINEAR_FOG:
        return smoothstep(near, far, depth)
    if kind == EXP2_FOG:
        var scaled = density * depth
        return 1 - exp(-scaled * scaled)
    return 0


def fog_mix(surface: FloatColor, fog: FloatColor, veil: Float32) -> FloatColor:
    """Return `surface` veiled by `fog`, `veil` of the way.

    A weighted sum of the two ends, `surface * (1 - veil) + fog * veil`,
    rather than `surface + (fog - surface) * veil`: the lerp subtracts the
    surface from the fog color, and a surface bright enough -- light here
    has no top -- swallows the fog color in that subtraction, so a fully
    fogged fragment came out black. Weighted, a veil of one multiplies the
    surface by zero and leaves the fog color exactly, however bright the
    surface was. Both rasterizers mix with this function.

    Args:
        surface: The fragment's shaded color, linear, straight alpha.
        fog: The fog color, linear.
        veil: How much of the fog color shows, zero to one, from
            `fog_factor`.

    Returns:
        The veiled color, with `surface`'s alpha: fog changes the color of
        a surface and not its coverage.
    """
    var keep = 1 - veil
    return FloatColor(
        surface.r * keep + fog.r * veil,
        surface.g * keep + fog.g * veil,
        surface.b * keep + fog.b * veil,
        surface.a,
    )


@fieldwise_init
struct FogView(ImplicitlyCopyable):
    """A scene's fog as a rasterizer takes it, ready to evaluate per fragment.

    Plain floats, the color already linear, as `Lighting` is for the lights.
    Built once per frame by `Renderer.render` from `scene.fog`, and checked
    once there; but its fields are open and it can be built by hand, so
    `rasterize_all`, `rasterize_shaded` and `GpuRenderer.draw` ask
    `validate` again before any fragment reads it.
    """

    var kind: FogKind
    # The fog color, decoded to linear light. Alpha is not fog and stays one.
    var color: FloatColor
    var near: Float32
    var far: Float32
    var density: Float32

    def __init__(out self, fog: Fog) raises:
        """Resolve a scene's fog for the rasterizers.

        Args:
            fog: The scene's fog.

        Raises:
            Error: If `fog.validate` refuses it: an unknown kind, a linear
                fog that starts behind the camera or ends before it starts,
                or an exponential fog with a negative density, or a number
                that is not finite.
        """
        fog.validate()
        self.kind = fog.kind
        self.color = FloatColor(srgb=fog.color)
        self.color.a = 1.0
        self.near = fog.near.value
        self.far = fog.far.value
        self.density = fog.density.value

    @staticmethod
    def none() -> FogView:
        """Return the view of no fog, which leaves every fragment alone.

        What a rasterizer takes when nothing says otherwise: a value rather
        than an Optional, as `Lighting.uniform` is for the lights.
        """
        return FogView(NO_FOG, FloatColor(0.0, 0.0, 0.0, 1.0), 0, 0, 0)

    def is_on(self) -> Bool:
        """Return True if this fog changes any fragment at all."""
        return self.kind != NO_FOG

    def validate(self) raises:
        """Refuse a view that cannot draw.

        The same list `Fog.validate` asks, of this view's floats, and the
        color as well: a view built by hand can hold anything, and the
        kernel cannot raise on what it finds.

        Raises:
            Error: If the kind is none of the three, the numbers the kind
                reads are not finite or are inside out, or a channel of the
                color is not finite.
        """
        _check_fog_numbers(self.kind, self.near, self.far, self.density)
        if (
            not isfinite(self.color.r)
            or not isfinite(self.color.g)
            or not isfinite(self.color.b)
        ):
            raise Error("A fog's color must be finite")

    def factor_at(self, depth: Float32) -> Float32:
        """Return how much of the fog color a fragment at `depth` shows.

        Args:
            depth: The fragment's camera-space depth, in meters, positive
                in front of the camera.

        Returns:
            Zero for the fragment's own color, one for the fog color alone.
        """
        return fog_factor(self.kind, depth, self.near, self.far, self.density)
