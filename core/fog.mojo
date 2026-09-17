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

**Mixed in linear light, before the image is encoded.** three.js applies its
fog after tone mapping and after the output color-space conversion, on the
encoded color, a quirk of shader-chunk order that three.js itself has an
issue open about. Here the mix happens where every other mix happens, in the
linear working space, so that halfway into the fog really is half the light
of each. The fog color is decoded from sRGB on the way in, as a light's is.
The fog reaches every material, lit or not, since three.js's
`Material.fog` defaults to on and is not ported. The uv debug view is not
fogged: it shows coordinates, not light.

**Two boundaries, one arithmetic.** `Fog` is what a scene holds, in lengths.
`FogView` is what a rasterizer takes: the same fog seen through one camera,
as plain floats with the view matrix's depth row folded in, so that a
fragment's depth is one dot product from its world position. `fog_factor`
and `fog_depth` are the arithmetic itself, shared with the GPU kernel as
`lights.lighting.falloff` is, and held to the same numbers by the parity
tests.
"""

from math.matrix4 import Matrix4
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from std.math import exp
from units.si import InverseLength, Length, METER, PER_METER


@fieldwise_init
struct FogKind(Equatable, ImplicitlyCopyable, Writable):
    """Which of the three fogs this is, as a type rather than an int.

    See `core.object3d.NodeId` for why. The type stops a bare integer at
    compile time; it does not stop `FogKind(7)`, which `FogView` refuses
    before a fragment is drawn.
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


@fieldwise_init
struct Fog(ImplicitlyCopyable):
    """What a scene holds: a kind, a color, and the numbers that kind reads.

    Build one with `no_fog`, `linear_fog` or `exp2_fog`, which check the
    numbers. The fields are open, as every struct's are, so `FogView` checks
    them again where they are read.
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
        Error: If `near` is negative, which would put the start behind the
            camera, or `far` is not beyond `near`, which leaves no room for
            the rise.
    """
    if near.value < 0:
        raise Error("A fog cannot start behind the camera")
    if far.value <= near.value:
        raise Error("A fog's far edge must be beyond its near edge")
    return Fog(LINEAR_FOG, color, near, far, _NO_DENSITY)


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
        Error: If the density is negative. The square would hide the sign,
            and a negative density is a mistake rather than a thinner fog.
    """
    if density.value < 0:
        raise Error("A fog's density cannot be negative")
    return Fog(EXP2_FOG, color, _NO_LENGTH, _NO_LENGTH, density)


def fog_depth(
    zx: Float32,
    zy: Float32,
    zz: Float32,
    zw: Float32,
    wx: Float32,
    wy: Float32,
    wz: Float32,
) -> Float32:
    """Return how far in front of the camera a world position is.

    three.js's `vFogDepth = -mvPosition.z`: the view matrix's depth row
    applied to the position, negated because the camera looks down -z.
    Taken from the interpolated world position rather than carried as a
    varying of its own, which comes to the same number: the depth is linear
    in the world position, and the world position is interpolated with
    perspective correction.

    Args:
        zx: The view matrix's depth row, first entry.
        zy: Its second entry.
        zz: Its third entry.
        zw: Its translation, the fourth entry.
        wx: The position's x, in world space.
        wy: Its y.
        wz: Its z.

    Returns:
        The camera-space depth, positive in front of the camera.
    """
    return -(zx * wx + zy * wy + zz * wz + zw)


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
    three -- which `FogView` refuses before this is ever asked.

    Args:
        kind: `LINEAR_FOG`, `EXP2_FOG` or `NO_FOG`.
        depth: The fragment's camera-space depth, from `fog_depth`.
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


@fieldwise_init
struct FogView(ImplicitlyCopyable):
    """A scene's fog seen through one camera, ready to evaluate per fragment.

    What both rasterizers take, as `Lighting` is what they take for the
    lights: plain floats, the color already linear, and the view matrix's
    depth row folded in so a fragment's depth is one dot product from its
    world position. Built once per frame, and checked once: a fog's fields
    are open, so this is where a wrong kind or an inside-out range is
    refused, before any fragment reads it.
    """

    var kind: FogKind
    # The fog color, decoded to linear light. Alpha is not fog and stays one.
    var color: FloatColor
    var near: Float32
    var far: Float32
    var density: Float32
    # The view matrix's depth row: what `fog_depth` applies to a position.
    var zx: Float32
    var zy: Float32
    var zz: Float32
    var zw: Float32

    def __init__(out self, fog: Fog, view: Matrix4) raises:
        """Resolve a scene's fog for a camera.

        Args:
            fog: The scene's fog.
            view: The camera's world-to-camera transform, the one the
                renderer projects with.

        Raises:
            Error: If the fog's kind is none of the three, a linear fog
                starts behind the camera or ends before it starts, or an
                exponential fog has a negative density -- the checks the
                builders make, made again because the fields are open.
        """
        if not fog.kind.is_valid():
            raise Error("A fog of an unknown kind cannot be drawn")
        if fog.kind == LINEAR_FOG:
            if fog.near.value < 0:
                raise Error("A fog cannot start behind the camera")
            if fog.far.value <= fog.near.value:
                raise Error("A fog's far edge must be beyond its near edge")
        if fog.kind == EXP2_FOG and fog.density.value < 0:
            raise Error("A fog's density cannot be negative")
        self.kind = fog.kind
        self.color = FloatColor(srgb=fog.color)
        self.color.a = 1.0
        self.near = fog.near.value
        self.far = fog.far.value
        self.density = fog.density.value
        # Column-major, as `Matrix4` is: the depth row is every column's
        # third entry.
        self.zx = view.elements[2]
        self.zy = view.elements[6]
        self.zz = view.elements[10]
        self.zw = view.elements[14]

    @staticmethod
    def none() -> FogView:
        """Return the view of no fog, which leaves every fragment alone.

        What a rasterizer takes when nothing says otherwise: a value rather
        than an Optional, as `Lighting.uniform` is for the lights.
        """
        return FogView(
            NO_FOG, FloatColor(0.0, 0.0, 0.0, 1.0), 0, 0, 0, 0, 0, 0, 0
        )

    def is_on(self) -> Bool:
        """Return True if this fog changes any fragment at all."""
        return self.kind != NO_FOG

    def depth_of(self, world: Vector3) -> Float32:
        """Return how far in front of the camera a world position is.

        Args:
            world: The position, in world space.

        Returns:
            Its camera-space depth, positive in front of the camera.
        """
        return fog_depth(
            self.zx, self.zy, self.zz, self.zw, world.x, world.y, world.z
        )

    def factor_at(self, world: Vector3) -> Float32:
        """Return how much of the fog color a fragment at `world` shows.

        Args:
            world: Where the fragment is, in world space.

        Returns:
            Zero for the fragment's own color, one for the fog color alone.
        """
        return fog_factor(
            self.kind, self.depth_of(world), self.near, self.far, self.density
        )
