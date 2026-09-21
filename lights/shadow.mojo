# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A shadow map: the scene's depth as one light sees it, from three.js
`src/lights/LightShadow.js` and `src/renderers/shaders/ShaderChunk/shadowmap_pars_fragment.glsl.js`.

**What a shadow map is.** A surface is in shadow when something stands
between it and the light. Rather than ask that question with a ray, a
renderer draws the scene once *from the light*, keeping only the depth,
and then, while shading a fragment for the camera, projects the fragment
into that picture and asks whether the depth stored there is nearer the
light than the fragment is. If it is, something was in the way. That is
what `ShadowMap` holds: a square of depths, and the transform that takes
a world position into it.

**How a light draws its map.** A directional light is infinitely far
away, so its rays are parallel and it draws through an orthographic
camera placed at its node, looking at its target, `extent` meters to
each side: three.js's `DirectionalLightShadow`. A spot light draws
through a perspective camera at its node with a field of view twice its
cone's angle, three.js's `SpotLightShadow`. Both take their near and far
planes from `LightShadow`. A point light's shadow is six maps, one per
face of a cube, and is not ported.

**The comparison is softened.** One depth compared against one texel
gives an edge as hard as the map's texels, which is what a shadow map
looks like at a glance and what three.js's `BasicShadowMap` does. Its
default is `PCFShadowMap`: nine taps in a three-by-three square of
`radius` texels around the fragment, each compared on its own, averaged.
That is `pcf_shadow` below, the same nine offsets in the same order on
both backends.

**Two biases, and why.** A surface compared against its own depth is
half in shadow, because the map's depth is quantized and a fragment
falls on either side of its own texel: shadow acne. `bias` moves the
fragment toward the light before the comparison, in the map's own depth,
from zero to one across the near and far planes, and `normal_bias`
moves it along its normal before it is projected, in meters. Both are
three.js's, at three.js's zero defaults; a scene that acnes is the scene
to raise them in.

The depth held here is the rasterizer's own: normalized device depth,
minus one at the near plane and one at the far, infinite where nothing
was drawn. It is compared in the map's zero-to-one depth, as three.js
compares `gl_FragCoord.z`, so a bias means the same number here as there.
"""

from math.vector3 import Vector3
from std.math import isfinite
from units.si import Length, METER

# three.js's `LightShadow` defaults: a map five hundred and twelve texels
# a side, no bias, one texel of blur.
comptime DEFAULT_MAP_SIZE = 512
comptime DEFAULT_SHADOW_RADIUS = Float32(1.0)
# three.js's shadow cameras: half a meter to five hundred, and a
# directional light's five meters to each side.
comptime DEFAULT_SHADOW_NEAR = Length(0.5, METER)
comptime DEFAULT_SHADOW_FAR = Length(500.0, METER)
comptime DEFAULT_SHADOW_EXTENT = Length(5.0, METER)
# The largest map this project builds: a square of this many texels a
# side is sixty-four million depths.
comptime MAX_MAP_SIZE = 8192
# How many taps `pcf_shadow` averages, three by three.
comptime PCF_TAPS = 9
# How many floats a shadow map's header takes in the flat light buffer:
# its size, its bias, its normal bias, its radius, then its sixteen-float
# frame; the depths follow. See `render.gpu.flatten_lights`.
comptime SHADOW_HEADER = 20


@fieldwise_init
struct LightShadow(ImplicitlyCopyable):
    """How a light draws its shadow map: three.js's `LightShadow`, with
    the numbers of its camera beside it.

    Every light carries one, read only when the light casts a shadow.
    The fields are open, as a light's are, and `validate` refuses what a
    map cannot be built from.
    """

    # How many texels a side the map is, three.js's `mapSize`.
    var map_size: Int
    # What is added to a fragment's depth, from zero to one across the
    # planes, before it is compared, three.js's `bias`. Negative moves
    # the fragment toward the light.
    var bias: Float32
    # How far along its normal a fragment is moved before it is
    # projected, in meters, three.js's `normalBias`.
    var normal_bias: Float32
    # How many texels the nine taps spread over, three.js's `radius`.
    var radius: Float32
    # The shadow camera's planes, three.js's `shadow.camera.near` and
    # `far`.
    var near: Length
    var far: Length
    # How far to each side a directional light's camera sees, three.js's
    # `shadow.camera.left` through `top` as one number. A spot light's
    # camera takes its width from the cone instead.
    var extent: Length

    def __init__(out self):
        """Start at three.js's defaults."""
        self.map_size = DEFAULT_MAP_SIZE
        self.bias = 0
        self.normal_bias = 0
        self.radius = DEFAULT_SHADOW_RADIUS
        self.near = DEFAULT_SHADOW_NEAR
        self.far = DEFAULT_SHADOW_FAR
        self.extent = DEFAULT_SHADOW_EXTENT

    def validate(self) raises:
        """Refuse numbers a shadow map cannot be built from.

        Raises:
            Error: If the map size is below one or above `MAX_MAP_SIZE`;
                the bias or the normal bias is not finite; the radius is
                negative or not finite; the near plane is negative, the
                far plane not beyond it, or either not finite; or the
                extent is not a positive finite length.
        """
        if self.map_size < 1 or self.map_size > MAX_MAP_SIZE:
            raise Error("A shadow map must be one to 8192 texels a side")
        if not isfinite(self.bias) or not isfinite(self.normal_bias):
            raise Error("A shadow bias must be finite")
        if not isfinite(self.radius) or self.radius < 0:
            raise Error("A shadow radius cannot be negative")
        var near = self.near.to(METER)
        var far = self.far.to(METER)
        if not isfinite(near) or not isfinite(far) or near < 0 or far <= near:
            raise Error(
                "A shadow camera's far plane must lie beyond its near plane"
            )
        var extent = self.extent.to(METER)
        if not isfinite(extent) or extent <= 0:
            raise Error("A shadow camera's extent must be a positive length")


struct ShadowMap(Movable):
    """One light's view of the scene's depth, ready to compare against.

    Built by `Renderer.shadow_maps` once per frame per light that casts,
    and handed to `Lighting`, which matches each to its light. The kernel
    reads the same numbers from the flat light buffer.
    """

    # Which of the scene's lights this map belongs to: its index in
    # `scene.lights`.
    var light: Int
    # How many texels a side.
    var size: Int
    # The transform from world space to the light's clip space, column
    # major as `Matrix4` is, as sixteen floats so the kernel can hold it.
    var frame: SIMD[DType.float32, 16]
    # One normalized device depth per texel, row-major from the top,
    # infinite where nothing was drawn.
    var depths: List[Float32]
    var bias: Float32
    var normal_bias: Float32
    var radius: Float32

    def __init__(
        out self,
        light: Int,
        size: Int,
        frame: SIMD[DType.float32, 16],
        var depths: List[Float32],
        bias: Float32,
        normal_bias: Float32,
        radius: Float32,
    ) raises:
        """Adopt a rendered depth square.

        Args:
            light: Which of the scene's lights drew it.
            size: How many texels a side.
            frame: World space to the light's clip space, column major.
            depths: `size * size` normalized device depths, from the top.
            bias: What is added to a fragment's depth before it is compared.
            normal_bias: How far a fragment is moved along its normal, in
                meters, before it is projected.
            radius: How many texels the taps spread over.

        Raises:
            Error: If the size is not positive or the depths do not fill
                the square.
        """
        if size <= 0:
            raise Error("A shadow map must be at least one texel a side")
        if len(depths) != size * size:
            raise Error("A shadow map's depths must fill its square")
        self.light = light
        self.size = size
        self.frame = frame
        self.depths = depths^
        self.bias = bias
        self.normal_bias = normal_bias
        self.radius = radius

    def lit(self, position: Vector3, normal: Vector3) -> Float32:
        """Return how much of the light reaches a surface, one for all of
        it and zero for none: `pcf_shadow` over this map.

        Args:
            position: Where the surface is, in world space.
            normal: Its unit normal, for the normal bias.

        Returns:
            The fraction of the nine taps that found nothing in the way.
        """
        var place = shadow_coordinate(
            self.frame, biased_position(position, normal, self.normal_bias)
        )
        if not inside_shadow_map(place):
            return 1
        var total = Float32(0)
        for tap in range(PCF_TAPS):  # pragma: no branch
            var texel = shadow_texel(place, tap, self.radius, self.size)
            total += shadow_tap(self.depths[texel], place.z, self.bias)
        return total / Float32(PCF_TAPS)


def biased_position(
    position: Vector3, normal: Vector3, normal_bias: Float32
) -> Vector3:
    """Return a surface position moved along its normal by the normal
    bias, three.js's `shadowWorldPosition`.

    Args:
        position: Where the surface is, in world space.
        normal: Its unit normal.
        normal_bias: How far to move, in meters. Zero moves nothing.

    Returns:
        The position to project into the map.
    """
    return Vector3(
        position.x + normal.x * normal_bias,
        position.y + normal.y * normal_bias,
        position.z + normal.z * normal_bias,
    )


def shadow_coordinate(
    frame: SIMD[DType.float32, 16], position: Vector3
) -> Vector3:
    """Return where a world position lands in a shadow map.

    The frame is the light's projection times its view, column major, as
    `Matrix4` holds its elements: a point is multiplied through and
    divided by its own w, as `Matrix4.transform_point` divides. What comes
    back is x across the map from zero at the left to one at the right, y
    down it from zero at the top to one at the bottom, as the map's rows
    are stored, and z from zero at the near plane to one at the far, as
    three.js's `gl_FragCoord.z` runs. A position behind the light's
    camera, where w is not positive, is put past the far plane, where
    `inside_shadow_map` leaves it lit.

    Args:
        frame: World space to the light's clip space.
        position: The world position.

    Returns:
        The map coordinate.
    """
    var x = (
        frame[0] * position.x
        + frame[4] * position.y
        + frame[8] * position.z
        + frame[12]
    )
    var y = (
        frame[1] * position.x
        + frame[5] * position.y
        + frame[9] * position.z
        + frame[13]
    )
    var z = (
        frame[2] * position.x
        + frame[6] * position.y
        + frame[10] * position.z
        + frame[14]
    )
    var w = (
        frame[3] * position.x
        + frame[7] * position.y
        + frame[11] * position.z
        + frame[15]
    )
    if w <= 0:
        return Vector3(0.5, 0.5, 2)
    var rcp = 1 / w
    return Vector3(
        x * rcp * 0.5 + 0.5, 0.5 - y * rcp * 0.5, z * rcp * 0.5 + 0.5
    )


def inside_shadow_map(place: Vector3) -> Bool:
    """Return True if a map coordinate falls on the map and before its far
    plane: three.js's `frustumTest`. Outside it, a surface is lit, since
    the light drew nothing there to shadow it with.

    Args:
        place: What `shadow_coordinate` returned.

    Returns:
        Whether the map has an answer for it.
    """
    return (
        place.x >= 0
        and place.x <= 1
        and place.y >= 0
        and place.y <= 1
        and place.z <= 1
    )


def shadow_texel(place: Vector3, tap: Int, radius: Float32, size: Int) -> Int:
    """Return which texel one of the nine taps reads.

    The taps go across then down, from `radius` texels up and left of
    the coordinate to `radius` texels down and right of it, in the order
    three.js's `getShadow` sums them; a radius of zero reads the one
    texel nine times. A tap past an edge reads the edge, as three.js's
    clamped map does.

    Args:
        place: What `shadow_coordinate` returned.
        tap: Which of the nine, zero through eight.
        radius: How many texels the taps spread over.
        size: How many texels a side the map is.

    Returns:
        The texel's index, row-major from the top.
    """
    var across = Float32(tap % 3 - 1) * radius
    var down = Float32(tap // 3 - 1) * radius
    var column = Int(place.x * Float32(size) + across)
    var row = Int(place.y * Float32(size) + down)
    if column < 0:
        column = 0
    if column >= size:
        column = size - 1
    if row < 0:
        row = 0
    if row >= size:
        row = size - 1
    return row * size + column


def shadow_tap(stored: Float32, depth: Float32, bias: Float32) -> Float32:
    """Return one if a fragment is lit at one texel and zero if shadowed:
    three.js's `texture2DCompare`, `step(depth + bias, stored)`.

    Args:
        stored: The map's normalized device depth at the texel, infinite
            where nothing was drawn.
        depth: The fragment's depth in the map, zero to one.
        bias: What is added to the fragment's depth first.

    Returns:
        One or zero.
    """
    if depth + bias <= stored * 0.5 + 0.5:
        return 1
    return 0
