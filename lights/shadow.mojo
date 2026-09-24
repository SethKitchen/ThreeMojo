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
camera placed at its node, looking at its target, its `left`, `right`,
`top` and `bottom` edges meters from its axis: three.js's
`DirectionalLightShadow`. A spot light draws
through a perspective camera at its node with a field of view twice its
cone's angle, three.js's `SpotLightShadow`. Both take their near and far
planes from `LightShadow`, except that a light with a `distance` puts its
far plane there, as three.js's `updateMatrices` does.

**A point light draws six maps.** It shines every way, so no one camera
sees all it lights. three.js's `PointLightShadow` draws six ninety-degree
views from the bulb, one along each axis, with the directions and ups of
its `_cubeDirections` and `_cubeUps`, and stores in each texel not the
camera's depth but the distance from the bulb, from zero at the near
plane to one at the far. A fragment is compared along the way from the
bulb to it: `cube_texel` finds the face and the texel that direction
crosses. See `point_shadow_tap` for its nine taps.

**A spot light can project a picture.** three.js's `SpotLight.map` is a
texture seen through the spot light's shadow camera, and the light's
color is multiplied by what it shows where a fragment lands on it: a
slide projector. `SpotLightMap` holds it.

**The comparison is softened.** One depth compared against one texel
gives an edge as hard as the map's texels, which is what a shadow map
looks like at a glance and what three.js's `BasicShadowMap` does. Its
default is `PCFShadowMap`: seventeen taps around the fragment, each
compared on its own, averaged. Nine lie on a three-by-three grid
`radius` texels apart, and eight more around its middle, half as far
apart, as three.js 0.180's `getShadow` has them. That is `ShadowMap.lit` below, the
same seventeen offsets in the same order on both backends.

**The renderer picks the filter.** three.js's `renderer.shadowMap.type`
is `Renderer.shadow_map_type` here, a `ShadowMapType`, and every map it
draws carries it. `BASIC_SHADOW_MAP` compares one texel.
`PCF_SOFT_SHADOW_MAP` is a three-texel box: sixteen comparisons around
the fragment, the outer ones weighed by how far the fragment lies inside
its texel, which `soft_shadow` sums as three.js's `getShadow` does.
`VSM_SHADOW_MAP` keeps two numbers per texel, the mean of the depth and
its spread, blurred across `radius` texels in `blur_samples` steps by
`vsm_moments`, and reads them with Chebyshev's bound, `vsm_shadow`. A
point light's cube keeps its nine taps under both, and one tap under
`BASIC_SHADOW_MAP`, as three.js's `getPointShadow` does.

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
from render.texture import Texture
from render.texture_store import TextureId
from std.math import floor, isfinite, max, min, sqrt
from units.si import Length, METER


@fieldwise_init
struct ShadowMapType(Equatable, ImplicitlyCopyable, Writable):
    """Which filter a renderer reads its shadow maps with, three.js's
    `renderer.shadowMap.type`, as a type rather than an int.

    See `core.object3d.NodeId` for why. The type stops a bare integer at
    compile time; it does not stop `ShadowMapType(7)`, which
    `Renderer.shadow_maps`, `ShadowMap` and `Lighting` refuse.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of three.js's four shadow map types.

        Returns:
            Whether it is `BASIC_SHADOW_MAP`, `PCF_SHADOW_MAP`,
            `PCF_SOFT_SHADOW_MAP` or `VSM_SHADOW_MAP`.
        """
        return (
            self == BASIC_SHADOW_MAP
            or self == PCF_SHADOW_MAP
            or self == PCF_SOFT_SHADOW_MAP
            or self == VSM_SHADOW_MAP
        )


# three.js's `BasicShadowMap`: one texel compared, a hard edge.
comptime BASIC_SHADOW_MAP = ShadowMapType(0)
# three.js's `PCFShadowMap`, its default: seventeen comparisons at `radius`
# texels and at half that, averaged.
comptime PCF_SHADOW_MAP = ShadowMapType(1)
# three.js's `PCFSoftShadowMap`: sixteen comparisons weighed into a box
# three texels wide, whatever the radius.
comptime PCF_SOFT_SHADOW_MAP = ShadowMapType(2)
# three.js's `VSMShadowMap`: the depth's mean and spread, blurred, read
# with Chebyshev's bound.
comptime VSM_SHADOW_MAP = ShadowMapType(3)

# three.js's `LightShadow` defaults: a map five hundred and twelve texels
# a side, no bias, one texel of blur, and eight blur samples for a
# variance map.
comptime DEFAULT_MAP_SIZE = 512
comptime DEFAULT_SHADOW_RADIUS = Float32(1.0)
comptime DEFAULT_BLUR_SAMPLES = 8
# The most samples each of a variance map's two blur passes takes.
comptime MAX_BLUR_SAMPLES = 256
# three.js's shadow cameras: half a meter to five hundred, and a
# directional light's five meters to each side.
comptime DEFAULT_SHADOW_NEAR = Length(0.5, METER)
comptime DEFAULT_SHADOW_FAR = Length(500.0, METER)
comptime DEFAULT_SHADOW_EXTENT = Length(5.0, METER)
# three.js's default `shadow.intensity`: the shadow takes all the light.
comptime FULL_SHADOW = Float32(1.0)
# The largest map this project builds: a square of this many texels a
# side is sixty-four million depths.
comptime MAX_MAP_SIZE = 8192
# How many taps `PCF_SHADOW_MAP` averages: a three-by-three square at the
# radius and the eight around the middle of one at half the radius.
comptime PCF_TAPS = 17
# Which of the seventeen taps is the fragment's own texel, with no offset.
comptime CENTER_TAP = 8
# How many taps a point light's cube averages, under every filter but
# `BASIC_SHADOW_MAP`: three.js's `getPointShadow`.
comptime POINT_SHADOW_TAPS = 9
# Each PCF tap's offset across and down, in units of the radius, in the
# order three.js's `getShadow` sums them. Padded to a power of two.
comptime _PCF_ACROSS = SIMD[DType.float32, 32](
    -1, 0, 1,
    -0.5, 0, 0.5,
    -1, -0.5, 0, 0.5, 1,
    -0.5, 0, 0.5,
    -1, 0, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
)  # fmt: skip
comptime _PCF_DOWN = SIMD[DType.float32, 32](
    -1, -1, -1,
    -0.5, -0.5, -0.5,
    0, 0, 0, 0, 0,
    0.5, 0.5, 0.5,
    1, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
)  # fmt: skip
# How many comparisons `soft_shadow` weighs, four by four.
comptime SOFT_TAPS = 16
# The two ends of three.js's `VSMShadow` ramp: a Chebyshev bound below
# the first is dark and above the second is lit, which cuts light bleed.
comptime VSM_DARK = Float32(0.3)
comptime VSM_LIT = Float32(0.95)
# How many floats a shadow map's header takes in the flat light buffer:
# its size, its bias, its normal bias, its radius, its sixteen-float
# frame, then its `ShadowMapType` and its intensity; the depths follow. See
# `render.gpu.flatten_lights`. A point light's cube puts its bulb's
# position, its near plane and its far plane in the first five of the
# frame's floats instead, and zeros after them.
comptime SHADOW_HEADER = 22
# Where in the header the `ShadowMapType` is, and the intensity.
comptime SHADOW_TYPE_AT = 20
comptime SHADOW_INTENSITY_AT = 21
# How many faces a point light's cube has, and how many texels of one
# face of its map the nine taps spread `radius` over: three.js lays the six
# out on a texture four faces wide and two high and offsets a tap by the
# radius times one texel of its height, which is half a face's texel.
comptime CUBE_FACES = 6
comptime CUBE_TEXEL_SHARE = Float32(0.5)
# How many floats a spot light's map takes in the flat light buffer: the
# texture's slot, the normal bias, and the sixteen-float frame.
comptime SPOT_MAP_FLOATS = 18


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
    # How many texels the PCF taps spread over, three.js's `radius`.
    var radius: Float32
    # The shadow camera's planes, three.js's `shadow.camera.near` and
    # `far`.
    var near: Length
    var far: Length
    # Where a directional light's camera sees to, three.js's
    # `shadow.camera.left`, `right`, `top` and `bottom`: each edge's
    # distance from the camera's axis, left and bottom negative. A spot
    # light's camera takes its width from the cone instead.
    var left: Length
    var right: Length
    var top: Length
    var bottom: Length
    # How many samples each of a variance map's two blur passes takes,
    # three.js's `blurSamples`. Read only under `VSM_SHADOW_MAP`.
    var blur_samples: Int
    # How much of the light the shadow takes away, three.js's
    # `shadow.intensity`: one for all of it, zero for none. See
    # `shadow_strength`.
    var intensity: Float32
    # Whether the map is drawn again every frame, three.js's
    # `shadow.autoUpdate`, and whether a map that is not is drawn once
    # more, three.js's `shadow.needsUpdate`. See `Renderer.shadow_maps`.
    var auto_update: Bool
    var needs_update: Bool

    def __init__(out self):
        """Start at three.js's defaults."""
        self.map_size = DEFAULT_MAP_SIZE
        self.bias = 0
        self.normal_bias = 0
        self.radius = DEFAULT_SHADOW_RADIUS
        self.near = DEFAULT_SHADOW_NEAR
        self.far = DEFAULT_SHADOW_FAR
        self.left = -DEFAULT_SHADOW_EXTENT
        self.right = DEFAULT_SHADOW_EXTENT
        self.top = DEFAULT_SHADOW_EXTENT
        self.bottom = -DEFAULT_SHADOW_EXTENT
        self.blur_samples = DEFAULT_BLUR_SAMPLES
        self.intensity = FULL_SHADOW
        self.auto_update = True
        self.needs_update = False

    def set_extent(mut self, extent: Length):
        """Make a directional light's camera see `extent` to each side of
        its axis: the square three.js's defaults make, at another size.

        Args:
            extent: How far each edge lies from the axis.
        """
        self.left = -extent
        self.right = extent
        self.top = extent
        self.bottom = -extent

    def is_frozen(self) -> Bool:
        """Return True if the map is kept as it was rather than drawn
        again: three.js's `autoUpdate` and `needsUpdate` both false.

        Returns:
            Whether `Renderer.shadow_maps` reuses a kept map.
        """
        return not self.auto_update and not self.needs_update

    def validate(self) raises:
        """Refuse numbers a shadow map cannot be built from.

        Raises:
            Error: If the map size is below one or above `MAX_MAP_SIZE`;
                the bias or the normal bias is not finite; the radius is
                negative or not finite; the blur samples are below one or
                above `MAX_BLUR_SAMPLES`; the near plane is negative, the
                far plane not beyond it, or either not finite; or the
                extent is not a positive finite length.
        """
        if self.map_size < 1 or self.map_size > MAX_MAP_SIZE:
            raise Error("A shadow map must be one to 8192 texels a side")
        if not isfinite(self.bias) or not isfinite(self.normal_bias):
            raise Error("A shadow bias must be finite")
        if not isfinite(self.radius) or self.radius < 0:
            raise Error("A shadow radius cannot be negative")
        if self.blur_samples < 1 or self.blur_samples > MAX_BLUR_SAMPLES:
            raise Error("A shadow's blur takes one to 256 samples")
        var near = self.near.to(METER)
        var far = self.far.to(METER)
        if not isfinite(near) or not isfinite(far) or near < 0 or far <= near:
            raise Error(
                "A shadow camera's far plane must lie beyond its near plane"
            )
        var left = self.left.to(METER)
        var right = self.right.to(METER)
        var top = self.top.to(METER)
        var bottom = self.bottom.to(METER)
        if (
            not isfinite(left)
            or not isfinite(right)
            or not isfinite(top)
            or not isfinite(bottom)
            or right <= left
            or top <= bottom
        ):
            raise Error(
                "A shadow camera's right edge must lie beyond its left and"
                " its top above its bottom"
            )
        if (
            not isfinite(self.intensity)
            or self.intensity < 0
            or self.intensity > 1
        ):
            raise Error("A shadow's intensity must be between zero and one")


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
    # infinite where nothing was drawn. Under `VSM_SHADOW_MAP`, two
    # squares instead: the blurred mean of the depth, from zero at the
    # near plane to one at the far, then its blurred spread, as
    # `vsm_moments` makes them.
    var depths: List[Float32]
    var bias: Float32
    var normal_bias: Float32
    var radius: Float32
    # Which filter reads the map; the renderer's `shadow_map_type`.
    var shadow_type: ShadowMapType
    # Whether this is a point light's six faces rather than one square.
    # A cube's depths are six squares, face by face in `cube_direction`
    # order, each holding the distance from the bulb from zero at the
    # near plane to one at the far, and one where nothing was drawn.
    var cube: Bool
    # Where a cube's bulb is, in world space, and its near and far
    # planes, in meters. Zero for a square map, which reads its frame.
    var origin: Vector3
    var near: Float32
    var far: Float32
    # How much of the light the shadow takes away, the light's
    # `shadow.intensity`; see `shadow_strength`.
    var intensity: Float32

    def __init__(
        out self,
        light: Int,
        size: Int,
        frame: SIMD[DType.float32, 16],
        var depths: List[Float32],
        bias: Float32,
        normal_bias: Float32,
        radius: Float32,
        shadow_type: ShadowMapType = PCF_SHADOW_MAP,
        intensity: Float32 = FULL_SHADOW,
    ) raises:
        """Adopt a rendered depth square.

        Args:
            light: Which of the scene's lights drew it.
            size: How many texels a side.
            frame: World space to the light's clip space, column major.
            depths: `size * size` normalized device depths, from the top,
                or under `VSM_SHADOW_MAP` the `2 * size * size` means and
                spreads `vsm_moments` returns.
            bias: What is added to a fragment's depth before it is compared.
            normal_bias: How far a fragment is moved along its normal, in
                meters, before it is projected.
            radius: How many texels the taps spread over.
            shadow_type: Which filter reads the map.
            intensity: How much of the light the shadow takes away.

        Raises:
            Error: If the size is not positive, the type is none of the
                four, or the depths do not fill the square, or two squares
                under `VSM_SHADOW_MAP`.
        """
        if size <= 0:
            raise Error("A shadow map must be at least one texel a side")
        if not shadow_type.is_valid():
            raise Error("A shadow map type that is none of the four")
        var squares = 1
        if shadow_type == VSM_SHADOW_MAP:
            squares = 2
        if len(depths) != squares * size * size:
            raise Error("A shadow map's depths must fill its square")
        self.light = light
        self.size = size
        self.frame = frame
        self.depths = depths^
        self.bias = bias
        self.normal_bias = normal_bias
        self.radius = radius
        self.shadow_type = shadow_type
        self.cube = False
        self.origin = Vector3(0, 0, 0)
        self.near = 0
        self.far = 0
        self.intensity = intensity

    def __init__(
        out self,
        *,
        cube_of: Int,
        size: Int,
        origin: Vector3,
        near: Float32,
        far: Float32,
        var depths: List[Float32],
        bias: Float32,
        normal_bias: Float32,
        radius: Float32,
        shadow_type: ShadowMapType = PCF_SHADOW_MAP,
        intensity: Float32 = FULL_SHADOW,
    ) raises:
        """Adopt a point light's six rendered faces, three.js's
        `PointLightShadow` map.

        Args:
            cube_of: Which of the scene's lights drew it.
            size: How many texels a side each face is.
            origin: Where the bulb is, in world space.
            near: The near plane, in meters.
            far: The far plane, in meters.
            depths: `6 * size * size` distances, face by face in
                `cube_direction` order, each face row-major from the top,
                from zero at the near plane to one at the far.
            bias: What is added to a fragment's distance before it is
                compared, in the same zero-to-one measure.
            normal_bias: How far a fragment is moved along its normal, in
                meters, before it is measured.
            radius: How far the taps spread; see `point_shadow_tap`.
            shadow_type: Which filter reads the cube: one tap under
                `BASIC_SHADOW_MAP` and nine under the other three.
            intensity: How much of the light the shadow takes away.

        Raises:
            Error: If the size is not positive, the type is none of the
                four, the depths do not fill six squares, or the far plane
                does not lie beyond the near plane.
        """
        if size <= 0:
            raise Error("A shadow map must be at least one texel a side")
        if not shadow_type.is_valid():
            raise Error("A shadow map type that is none of the four")
        if len(depths) != CUBE_FACES * size * size:
            raise Error("A point light's shadow must fill six square faces")
        if not (far > near):
            raise Error(
                "A shadow camera's far plane must lie beyond its near plane"
            )
        self.light = cube_of
        self.size = size
        self.frame = SIMD[DType.float32, 16](0)
        self.depths = depths^
        self.bias = bias
        self.normal_bias = normal_bias
        self.radius = radius
        self.shadow_type = shadow_type
        self.cube = True
        self.origin = origin
        self.near = near
        self.far = far
        self.intensity = intensity

    def lit(self, position: Vector3, normal: Vector3) -> Float32:
        """Return how much of the light reaches a surface, one for all of
        it and zero for none: `pcf_shadow` over this map, or three.js's
        `getPointShadow` over a cube.

        Args:
            position: Where the surface is, in world space.
            normal: Its unit normal, for the normal bias.

        Returns:
            The fraction of the light that found nothing in the way, by
            the map's `shadow_type`, weakened by its `intensity` as
            `shadow_strength` weakens it.
        """
        return shadow_strength(
            self._unweakened(position, normal), self.intensity
        )

    def _unweakened(self, position: Vector3, normal: Vector3) -> Float32:
        """Return what the map lets through at full intensity."""
        if self.cube:
            return self._cube_lit(position, normal)
        var place = shadow_coordinate(
            self.frame, biased_position(position, normal, self.normal_bias)
        )
        if not inside_shadow_map(place, self.bias):
            return 1
        if self.shadow_type == BASIC_SHADOW_MAP:
            return shadow_tap(
                self.depths[shadow_texel(place, CENTER_TAP, 0, self.size)],
                place.z,
                self.bias,
            )
        if self.shadow_type == PCF_SOFT_SHADOW_MAP:
            var taps = SIMD[DType.float32, SOFT_TAPS](0)
            for tap in range(SOFT_TAPS):  # pragma: no branch
                taps[tap] = shadow_tap(
                    self.depths[soft_texel(place, tap, self.size)],
                    place.z,
                    self.bias,
                )
            return soft_shadow(
                taps,
                soft_fraction(place.x, self.size),
                soft_fraction(place.y, self.size),
            )
        if self.shadow_type == VSM_SHADOW_MAP:
            var across = place.x * Float32(self.size)
            var down = place.y * Float32(self.size)
            var square = self.size * self.size
            var corners = SIMD[DType.float32, 8](0)
            for corner in range(4):  # pragma: no branch
                var texel = bilinear_texel(across, down, corner, self.size)
                corners[corner] = self.depths[texel]
                corners[corner + 4] = self.depths[square + texel]
            return vsm_shadow(
                bilinear(corners, 0, across, down),
                bilinear(corners, 4, across, down),
                place.z + self.bias,
            )
        var total = Float32(0)
        for tap in range(PCF_TAPS):  # pragma: no branch
            var texel = shadow_texel(place, tap, self.radius, self.size)
            total += shadow_tap(self.depths[texel], place.z, self.bias)
        return total / Float32(PCF_TAPS)

    def _cube_lit(self, position: Vector3, normal: Vector3) -> Float32:
        """Return what a point light's cube lets through to a surface."""
        var away = biased_position(position, normal, self.normal_bias)
        var toward = Vector3(
            away.x - self.origin.x,
            away.y - self.origin.y,
            away.z - self.origin.z,
        )
        var distance = toward.length()
        if not inside_point_shadow(distance, self.near, self.far):
            return 1
        var depth = point_shadow_depth(distance, self.near, self.far) + (
            self.bias
        )
        var way = Vector3(
            toward.x / distance, toward.y / distance, toward.z / distance
        )
        if self.shadow_type == BASIC_SHADOW_MAP:
            return cube_tap(self.depths[cube_texel(way, self.size)], depth)
        var spread = point_shadow_spread(self.radius, self.size)
        var total = Float32(0)
        for tap in range(POINT_SHADOW_TAPS):  # pragma: no branch
            var texel = cube_texel(
                point_shadow_tap(way, tap, spread), self.size
            )
            total += cube_tap(self.depths[texel], depth)
        return total / Float32(POINT_SHADOW_TAPS)


@fieldwise_init
struct ShadowCascade(ImplicitlyCopyable):
    """Which slice of a camera's depth one directional light lights, as
    three.js's `CSMShader` gates each light of a `CSM`.

    Every light carries one; only a directional light reads it, and one
    whose `span` is zero is no cascade and lights every depth. A fragment's
    depth is its distance in front of the camera over `span`, three.js's
    `linearDepth`, and `cascade_reach` says how much of the light it gets
    and how much of the light's shadow falls on it. `lights.csm.CSM` fills
    these in.
    """

    # Where the slice begins and ends, as fractions of `span`: three.js's
    # `CSM_cascades[ i ].x` and `.y`.
    var start: Float32
    var end: Float32
    # What a depth is divided by, three.js's `shadowFar - cameraNear`.
    # Zero for a light that is no cascade.
    var span: Length
    # Whether this is the furthest slice, which also lights every depth
    # beyond its end, as three.js's `CSM_CASCADES - 1` does.
    var last: Bool
    # Whether the slices blend into each other, three.js's `CSM.fade`.
    var fade: Bool

    @staticmethod
    def none() -> ShadowCascade:
        """Return what a light that is no cascade carries.

        Returns:
            A slice with a span of zero.
        """
        return ShadowCascade(0, 0, Length(0.0, METER), False, False)

    def is_cascade(self) -> Bool:
        """Return True if this gates its light by depth.

        Returns:
            Whether the span is not zero.
        """
        return self.span.value != 0

    def validate(self) raises:
        """Refuse a slice no depth can be measured against.

        A light that is no cascade is not checked further.

        Raises:
            Error: If the span is not zero and is negative or not finite,
                or the start or end is not finite, the start is negative
                or the end lies before the start.
        """
        if not self.is_cascade():
            return
        var span = self.span.to(METER)
        if not isfinite(span) or span < 0:
            raise Error("A shadow cascade's span must be a positive length")
        if (
            not isfinite(self.start)
            or not isfinite(self.end)
            or self.start < 0
            or self.end < self.start
        ):
            raise Error(
                "A shadow cascade must start at zero or later and end no"
                " sooner than it starts"
            )


def view_depth(position: Vector3, eye: Vector3, back: Vector3) -> Float32:
    """Return how far in front of a camera a position lies, along the way
    it looks: three.js's `vViewPosition.z`.

    Args:
        position: The world position.
        eye: Where the camera is, in world space.
        back: The camera's +z axis in world space, unit length.

    Returns:
        The depth, positive in front of the camera.
    """
    return -(
        (position.x - eye.x) * back.x
        + (position.y - eye.y) * back.y
        + (position.z - eye.z) * back.z
    )


def cascade_reach(
    depth: Float32, start: Float32, end: Float32, last: Bool, fade: Bool
) -> SIMD[DType.float32, 2]:
    """Return how much of a cascade's light reaches a depth and how much of
    its shadow falls there: three.js's `CSMShader` `lights_fragment_begin`
    for one directional light.

    Without fade, a depth in the slice gets the light and its shadow, a
    depth past the last slice gets the light with no shadow, and any other
    depth gets nothing. With fade, each slice reaches a margin further
    either way, a quarter of its nearer edge squared, and the light ramps
    across that margin, as three.js's `ratio` ramps it. The last slice
    fades its shadow out, not its light, past its middle.

    Args:
        depth: The fragment's depth over the span, three.js's
            `linearDepth`.
        start: Where the slice begins, `ShadowCascade.start`.
        end: Where it ends, `ShadowCascade.end`.
        last: Whether it is the furthest slice.
        fade: Whether the slices blend, three.js's `CSM.fade`.

    Returns:
        The share of the light, then the share of its shadow: what three.js
        blends `reflectedLight` by and mixes `directLight.color` by. A
        margin of zero ramps at once, a ratio of one.
    """
    if not fade:
        var inside = depth >= start and depth < end
        var lit = inside or (last and depth >= start)
        return SIMD[DType.float32, 2](
            Float32(1) if lit else Float32(0),
            Float32(1) if inside else Float32(0),
        )
    var center = (start + end) / 2
    var edge = start if depth < center else end
    var margin = Float32(0.25) * edge * edge
    var low = start - margin / 2
    var high = end + margin / 2
    var reached = depth >= low and (depth < high or last)
    if not reached:
        return SIMD[DType.float32, 2](0, 0)
    var ratio = Float32(1)
    if margin > 0:
        ratio = max(
            Float32(0), min(Float32(1), min(depth - low, high - depth) / margin)
        )
    return SIMD[DType.float32, 2](
        ratio if (not last or depth < center) else Float32(1),
        ratio if (last and depth > center) else Float32(1),
    )


def shadow_strength(through: Float32, intensity: Float32) -> Float32:
    """Return what a shadow lets through, weakened by its intensity:
    three.js's `mix( 1.0, shadow, shadowIntensity )`, the last line of
    `getShadow` and `getPointShadow`.

    Written as one plus the shadow's part of the gap, so a fragment the
    map leaves lit stays at exactly one whatever the intensity. A full
    intensity returns the shadow as it is, as `mix` does at one, with no
    rounding through the gap.

    Args:
        through: What the map lets through, one for all the light.
        intensity: How much of the light the shadow takes away, from zero
            to one.

    Returns:
        The fraction of the light that arrives.
    """
    if intensity == FULL_SHADOW:
        return through
    return 1 + (through - 1) * intensity


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


def inside_shadow_map(place: Vector3, bias: Float32) -> Bool:
    """Return True if a map coordinate falls on the map and before its far
    plane: three.js's `frustumTest`. Outside it, a surface is lit, since
    the light drew nothing there to shadow it with.

    The far plane is tested after the bias is added, as three.js's
    `getShadow` adds `shadowBias` to `shadowCoord.z` first. A negative
    bias thus keeps a surface just past the far plane in the map.

    Args:
        place: What `shadow_coordinate` returned.
        bias: The map's depth bias, added to the depth before the test.

    Returns:
        Whether the map has an answer for it.
    """
    return (
        place.x >= 0
        and place.x <= 1
        and place.y >= 0
        and place.y <= 1
        and place.z + bias <= 1
    )


def shadow_texel(place: Vector3, tap: Int, radius: Float32, size: Int) -> Int:
    """Return which texel one of the seventeen taps reads.

    three.js 0.180's `getShadow` under `PCFShadowMap` reads a
    three-by-three grid of taps `radius` texels apart and, inside it, the
    eight taps around the middle of a grid half as far apart. The taps go down the
    rows and across each row, from `radius` texels up and left of the
    coordinate to `radius` texels down and right of it, in the order
    three.js sums them: three on the top row, three at half the radius up,
    five on the middle row, three at half the radius down and three on
    the bottom row. A radius of zero reads the one texel seventeen times.
    A tap past an edge reads the edge, as three.js's clamped map does.

    Args:
        place: What `shadow_coordinate` returned.
        tap: Which of the seventeen, zero through sixteen.
        radius: How many texels the taps spread over.
        size: How many texels a side the map is.

    Returns:
        The texel's index, row-major from the top.
    """
    var across = _PCF_ACROSS[tap] * radius
    var down = _PCF_DOWN[tap] * radius
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


def _mix(low: Float32, high: Float32, weight: Float32) -> Float32:
    """Return GLSL's `mix`: `low` at a weight of zero, `high` at one."""
    return low * (1 - weight) + high * weight


def _texel_at(column: Int, row: Int, size: Int) -> Int:
    """Return a texel's index with its column and row held to the map, as
    a map clamped to its edge reads past them."""
    # One statement: a soft shadow reads sixteen of these per fragment,
    # and a coverage run writes a record per statement.
    return min(max(row, 0), size - 1) * size + min(max(column, 0), size - 1)


def soft_texel(place: Vector3, tap: Int, size: Int) -> Int:
    """Return which texel one of `PCF_SOFT_SHADOW_MAP`'s sixteen taps reads.

    three.js's `getShadow` moves the coordinate back to the corner of the
    texel it lies nearest, `uv -= f * texelSize`, and reads a four-by-four
    block from one texel before that corner to two after it. The taps go
    across then down: tap `t` is `t % 4 - 1` texels across and `t // 4 - 1`
    down from the texel just before the corner. A tap past an edge reads
    the edge.

    Args:
        place: What `shadow_coordinate` returned.
        tap: Which of the sixteen, zero through fifteen.
        size: How many texels a side the map is.

    Returns:
        The texel's index, row-major from the top.
    """
    var column = Int(floor(place.x * Float32(size) + 0.5)) + tap % 4 - 2
    var row = Int(floor(place.y * Float32(size) + 0.5)) + tap // 4 - 2
    return _texel_at(column, row, size)


def soft_fraction(coordinate: Float32, size: Int) -> Float32:
    """Return how far past the nearest texel corner a coordinate lies, in
    texels: three.js's `f = fract(uv * shadowMapSize + 0.5)`.

    Args:
        coordinate: One component of what `shadow_coordinate` returned.
        size: How many texels a side the map is.

    Returns:
        Zero up to one.
    """
    var texels = coordinate * Float32(size) + 0.5
    return texels - floor(texels)


def soft_shadow(
    taps: SIMD[DType.float32, SOFT_TAPS], across: Float32, down: Float32
) -> Float32:
    """Return what `PCF_SOFT_SHADOW_MAP` lets through: three.js's sum of
    its sixteen comparisons, divided by nine.

    The four middle taps count whole. The outer ones of each row and
    column are mixed by the fractions, and the four corners by both, so
    the sum is a box three texels wide centered on the fragment. The
    radius plays no part, as in three.js.

    Args:
        taps: The sixteen comparisons, one or zero, in `soft_texel` order.
        across: `soft_fraction` of the coordinate's x.
        down: `soft_fraction` of the coordinate's y.

    Returns:
        The fraction of the light that found nothing in the way.
    """
    return (
        taps[5]
        + taps[6]
        + taps[9]
        + taps[10]
        + _mix(taps[4], taps[7], across)
        + _mix(taps[8], taps[11], across)
        + _mix(taps[1], taps[13], down)
        + _mix(taps[2], taps[14], down)
        + _mix(
            _mix(taps[0], taps[3], across),
            _mix(taps[12], taps[15], across),
            down,
        )
    ) * (Float32(1) / 9)


def bilinear_texel(
    across: Float32, down: Float32, corner: Int, size: Int
) -> Int:
    """Return which texel one of the four corners of a linear read takes.

    A linear filter reads the four texels whose centers surround a point,
    as three.js reads a variance map. Corner zero is up and left, one up
    and right, two down and left, three down and right. A corner past an
    edge reads the edge, as a map clamped to its edge does.

    Args:
        across: The point's x, in texels from the left edge.
        down: The point's y, in texels from the top edge.
        corner: Which of the four, zero through three.
        size: How many texels a side the map is.

    Returns:
        The texel's index, row-major from the top.
    """
    var column = Int(floor(across - 0.5)) + corner % 2
    var row = Int(floor(down - 0.5)) + corner // 2
    return _texel_at(column, row, size)


def bilinear_fraction(at: Float32) -> Float32:
    """Return how far a point lies past the texel center before it: the
    weight a linear filter gives the center after it.

    Args:
        at: The point, in texels from the edge.

    Returns:
        Zero up to one.
    """
    return (at - 0.5) - floor(at - 0.5)


def bilinear(
    corners: SIMD[DType.float32, 8], first: Int, across: Float32, down: Float32
) -> Float32:
    """Return a linear read from the four values at `bilinear_texel`'s
    corners.

    Args:
        corners: Two sets of four corner values.
        first: Where the set to read begins, zero or four.
        across: The point's x, in texels from the left edge.
        down: The point's y, in texels from the top edge.

    Returns:
        The value between them.
    """
    var right = bilinear_fraction(across)
    return _mix(
        _mix(corners[first], corners[first + 1], right),
        _mix(corners[first + 2], corners[first + 3], right),
        bilinear_fraction(down),
    )


def vsm_shadow(mean: Float32, spread: Float32, depth: Float32) -> Float32:
    """Return what `VSM_SHADOW_MAP` lets through: three.js's `VSMShadow`.

    A fragment no deeper than the mean is lit. Beyond it, Chebyshev's
    inequality bounds how much of the texel's depth lies beyond the
    fragment: the variance over the variance plus the squared distance.
    three.js maps that bound from `VSM_DARK` to `VSM_LIT` onto zero to
    one, which darkens the light that leaks between two casters.

    Args:
        mean: The blurred mean of the depth, zero to one.
        spread: The blurred standard deviation of the depth.
        depth: The fragment's depth in the map with the bias added.

    Returns:
        Zero up to one.
    """
    if depth <= mean:
        return 1
    var distance = depth - mean
    var variance = spread * spread
    var bound = variance / (variance + distance * distance)
    return min(
        Float32(1), max(Float32(0), (bound - VSM_DARK) / (VSM_LIT - VSM_DARK))
    )


def vsm_depth(ndc_depth: Float32) -> Float32:
    """Return the depth a variance map starts from at one texel: the map's
    zero-to-one depth, three.js's `gl_FragCoord.z`, and one where nothing
    was drawn, as three.js clears its map to white.

    Args:
        ndc_depth: The rasterizer's depth, infinite where nothing was
            drawn.

    Returns:
        Zero to one.
    """
    if ndc_depth > 1:
        return 1
    return ndc_depth * 0.5 + 0.5


def vsm_offset(sample: Int, samples: Int) -> Float32:
    """Return where one blur sample lies, in steps of `radius` texels:
    three.js's `uvStart + i * uvStride`, from minus one to one.

    Args:
        sample: Which sample, from zero.
        samples: How many the pass takes. One takes the texel itself.

    Returns:
        The offset.
    """
    if samples <= 1:
        return 0
    return -1 + Float32(sample) * (2 / Float32(samples - 1))


def vsm_moments(
    depths: List[Float32], size: Int, radius: Float32, samples: Int
) -> List[Float32]:
    """Return a variance map's blurred mean and spread from its depths:
    three.js's `VSMPass`.

    Two passes, each `samples` linear reads `radius` texels apart at most,
    as three.js's `vsm.glsl.js` takes them. The first reads the depth down
    each column and keeps its mean and standard deviation. The second
    reads those across each row, turns each back into a mean square, and
    keeps the mean and standard deviation of the whole. The variance is
    held at zero or above before its root is taken, where rounding could
    leave it below.

    Args:
        depths: `size * size` normalized device depths, row-major from the
            top, infinite where nothing was drawn.
        size: How many texels a side.
        radius: How many texels the samples spread over each way.
        samples: How many reads each pass takes, one or more.

    Returns:
        `size * size` means, then `size * size` standard deviations.
    """
    # `LightShadow.validate` holds the size and the samples at one or
    # more, so no loop below runs zero times.
    var square = size * size
    var stored = List[Float32](capacity=square)
    for texel in range(square):  # pragma: no branch
        stored.append(vsm_depth(depths[texel]))
    var weight = 1 / Float32(samples)
    var columns = List[Float32](length=2 * square, fill=0)
    for row in range(size):  # pragma: no branch
        for column in range(size):  # pragma: no branch
            var mean = Float32(0)
            var squared = Float32(0)
            var across = Float32(column) + 0.5
            for sample in range(samples):  # pragma: no branch
                # three.js's y runs up the map, and this map's rows down.
                var down = (
                    Float32(row) + 0.5 - vsm_offset(sample, samples) * radius
                )
                var corners = SIMD[DType.float32, 8](0)
                for corner in range(4):  # pragma: no branch
                    corners[corner] = stored[
                        bilinear_texel(across, down, corner, size)
                    ]
                var depth = bilinear(corners, 0, across, down)
                mean += depth
                squared += depth * depth
            mean *= weight
            squared *= weight
            columns[row * size + column] = mean
            columns[square + row * size + column] = sqrt(
                max(Float32(0), squared - mean * mean)
            )
    var moments = List[Float32](length=2 * square, fill=0)
    for row in range(size):  # pragma: no branch
        for column in range(size):  # pragma: no branch
            var mean = Float32(0)
            var squared = Float32(0)
            var down = Float32(row) + 0.5
            for sample in range(samples):  # pragma: no branch
                var across = (
                    Float32(column) + 0.5 + vsm_offset(sample, samples) * radius
                )
                var corners = SIMD[DType.float32, 8](0)
                for corner in range(4):  # pragma: no branch
                    var texel = bilinear_texel(across, down, corner, size)
                    corners[corner] = columns[texel]
                    corners[corner + 4] = columns[square + texel]
                var average = bilinear(corners, 0, across, down)
                var spread = bilinear(corners, 4, across, down)
                mean += average
                squared += spread * spread + average * average
            mean *= weight
            squared *= weight
            moments[row * size + column] = mean
            moments[square + row * size + column] = sqrt(
                max(Float32(0), squared - mean * mean)
            )
    return moments^


def inside_point_shadow(distance: Float32, near: Float32, far: Float32) -> Bool:
    """Return True if a point light's cube has an answer for a surface this
    far from the bulb: three.js's test that the distance lies between the
    shadow camera's planes. A surface exactly on the bulb has no direction
    to look along and is lit.

    Args:
        distance: How far the surface is from the bulb, in meters.
        near: The near plane, in meters.
        far: The far plane, in meters.

    Returns:
        Whether the cube is compared at all.
    """
    return distance > 0 and distance - far <= 0 and distance - near >= 0


def point_shadow_depth(
    distance: Float32, near: Float32, far: Float32
) -> Float32:
    """Return a distance from the bulb as a point light's cube stores it:
    zero at the near plane and one at the far, three.js's `dp`.

    Args:
        distance: How far from the bulb, in meters.
        near: The near plane, in meters.
        far: The far plane, in meters.

    Returns:
        The normalized distance.
    """
    return (distance - near) / (far - near)


def point_shadow_spread(radius: Float32, size: Int) -> Float32:
    """Return how far each tap's direction is moved along each axis:
    three.js's `shadowRadius * texelSize.y`, where the texel is one of its
    four-by-two atlas, half of one face's texel.

    Args:
        radius: The shadow's radius, three.js's `radius`.
        size: How many texels a side each face is.

    Returns:
        The offset, in the units of a unit direction.
    """
    return radius * CUBE_TEXEL_SHARE / Float32(size)


def point_shadow_tap(way: Vector3, tap: Int, spread: Float32) -> Vector3:
    """Return the direction one of a point light's nine taps looks along.

    three.js's `getPointShadow` adds `offset.xyy`, `yyy`, `xyx`, `yyx`,
    nothing, `xxy`, `yxy`, `xxx` and `yxx` to the direction, in that
    order, where `x` is minus the spread and `y` is plus it. Tap four is
    the direction itself.

    Args:
        way: The unit direction from the bulb to the surface.
        tap: Which of the nine, zero through eight.
        spread: How far to move along each axis; `point_shadow_spread`.

    Returns:
        The direction to look along. It is not normalized, as three.js
        does not normalize it: only which way it points matters.
    """
    if tap == 4:
        return way
    var corner = tap
    if tap > 4:
        corner = tap - 1
    var sx = -spread
    if corner % 2 == 1:
        sx = spread
    var sy = -spread
    if corner < 4:
        sy = spread
    var sz = -spread
    if (corner // 2) % 2 == 0:
        sz = spread
    return Vector3(way.x + sx, way.y + sy, way.z + sz)


def cube_direction(face: Int) -> Vector3:
    """Return which way one face of a point light's cube looks: three.js's
    `PointLightShadow._cubeDirections`, +x, -x, +z, -z, +y, -y.

    Args:
        face: Zero through five. Any other face is the last.

    Returns:
        The unit direction.
    """
    if face == 0:
        return Vector3(1, 0, 0)
    if face == 1:
        return Vector3(-1, 0, 0)
    if face == 2:
        return Vector3(0, 0, 1)
    if face == 3:
        return Vector3(0, 0, -1)
    if face == 4:
        return Vector3(0, 1, 0)
    return Vector3(0, -1, 0)


def cube_up(face: Int) -> Vector3:
    """Return which way is up on one face of a point light's cube:
    three.js's `PointLightShadow._cubeUps`. Each is square to its face's
    direction, so it is also the face's screen up.

    Args:
        face: Zero through five. Any other face is the last.

    Returns:
        The unit up.
    """
    if face < 4:
        return Vector3(0, 1, 0)
    if face == 4:
        return Vector3(0, 0, 1)
    return Vector3(0, 0, -1)


def cube_face(direction: Vector3) -> Int:
    """Return which face of a point light's cube a direction crosses.

    The face of the largest component, and on a tie z before x before y,
    the order three.js's `cubeToUV` asks in.

    Args:
        direction: Any direction but zero.

    Returns:
        The face, in `cube_direction` order.
    """
    var x = abs(direction.x)
    var y = abs(direction.y)
    var z = abs(direction.z)
    if z >= x and z >= y:
        if direction.z > 0:
            return 2
        return 3
    if x >= y:
        if direction.x > 0:
            return 0
        return 1
    if direction.y > 0:
        return 4
    return 5


def cube_texel(direction: Vector3, size: Int) -> Int:
    """Return which texel of a point light's cube a direction reads.

    The face from `cube_face`, then the place on it as the face's camera
    projected it: across along the face's right, which is its direction
    crossed with its up, and down against its up, each divided by how far
    the direction runs along the face. A ninety-degree view puts the edges
    of the face at plus and minus one.

    Args:
        direction: Any direction but zero.
        size: How many texels a side each face is.

    Returns:
        The texel's index: the face's square, then row-major from the top.
    """
    var face = cube_face(direction)
    var forward = cube_direction(face)
    var up = cube_up(face)
    var right = Vector3(
        forward.y * up.z - forward.z * up.y,
        forward.z * up.x - forward.x * up.z,
        forward.x * up.y - forward.y * up.x,
    )
    var along = direction.dot(forward)
    var across = direction.dot(right) / along
    var upward = direction.dot(up) / along
    var column = Int((across * 0.5 + 0.5) * Float32(size))
    var row = Int((0.5 - upward * 0.5) * Float32(size))
    if column >= size:
        column = size - 1
    if row >= size:
        row = size - 1
    return face * size * size + row * size + column


def cube_tap(stored: Float32, depth: Float32) -> Float32:
    """Return one if a fragment is lit at one texel of a cube and zero if
    shadowed: three.js's `texture2DCompare`, `step(dp, stored)`.

    Args:
        stored: The cube's distance at the texel, zero to one, one where
            nothing was drawn.
        depth: The fragment's distance, zero to one, with the bias added.

    Returns:
        One or zero.
    """
    if depth <= stored:
        return 1
    return 0


def cube_stored(
    ndc_depth: Float32,
    column: Int,
    row: Int,
    size: Int,
    near: Float32,
    far: Float32,
) -> Float32:
    """Return what a point light's cube stores at one texel of one face,
    from the depth the rasterizer left there.

    three.js draws each face with `MeshDistanceMaterial`, which writes the
    distance from the bulb, saturated to zero through one across the
    planes. This renderer's rasterizer keeps normalized device depth, so
    the distance is recovered from it: the depth along the face's axis
    from the perspective projection's inverse, then along the ray through
    the texel's center, whose slope a ninety-degree view makes its
    normalized device coordinates. The answer is the distance to the
    surface under the texel's center, where the rasterizer sampled it.

    Args:
        ndc_depth: The rasterizer's depth, infinite where nothing was
            drawn.
        column: The texel's column, from the left.
        row: The texel's row, from the top.
        size: How many texels a side the face is.
        near: The near plane, in meters.
        far: The far plane, in meters.

    Returns:
        The distance from zero at the near plane to one at the far, one
        where nothing was drawn, as three.js clears to white.
    """
    if ndc_depth > 1:
        return 1
    var along = 2 * far * near / ((far + near) - ndc_depth * (far - near))
    var x = (Float32(column) + 0.5) / Float32(size) * 2 - 1
    var y = 1 - (Float32(row) + 0.5) / Float32(size) * 2
    var distance = along * sqrt(1 + x * x + y * y)
    return max(
        Float32(0), min(Float32(1), point_shadow_depth(distance, near, far))
    )


def inside_spot_map(place: Vector3) -> Bool:
    """Return True if a map coordinate falls strictly inside a spot light's
    map and between its planes: three.js's `inSpotLightMap`, every
    component of `coord * 2 - 1` below one in size.

    Args:
        place: What `shadow_coordinate` returned.

    Returns:
        Whether the map tints the light there.
    """
    return (
        place.x > 0
        and place.x < 1
        and place.y > 0
        and place.y < 1
        and place.z > 0
        and place.z < 1
    )


struct SpotLightMap(Movable):
    """The picture a spot light projects, three.js's `SpotLight.map`, and
    the transform that takes a world position onto it.

    Built by `Renderer.spot_light_maps` once per frame per spot light that
    names a map, and handed to `Lighting`, which matches each to its light.
    The frame is the light's shadow camera, as three.js projects the map
    through `shadow.matrix`, whether or not the light casts.
    """

    # Which of the scene's lights projects it: its index in `scene.lights`.
    var light: Int
    # Which texture in the store it is, for the kernel, which reads the
    # store's own copy.
    var texture: TextureId
    # The texture itself, for the host.
    var image: Texture
    # The transform from world space to the light's clip space, column
    # major, as `ShadowMap.frame`.
    var frame: SIMD[DType.float32, 16]
    # How far a surface is moved along its normal before it is projected:
    # the shadow's normal bias when the light casts, and zero when not,
    # as three.js adds it only under a shadow.
    var normal_bias: Float32

    def __init__(
        out self,
        light: Int,
        texture: TextureId,
        var image: Texture,
        frame: SIMD[DType.float32, 16],
        normal_bias: Float32,
    ) raises:
        """Adopt a spot light's picture.

        Args:
            light: Which of the scene's lights projects it.
            texture: Which texture in the store it is.
            image: The texture itself.
            frame: World space to the light's clip space, column major.
            normal_bias: How far a surface is moved along its normal, in
                meters, before it is projected.

        Raises:
            Error: If the texture is blank: it holds no picture to project.
        """
        if image.is_blank():
            raise Error("A spot light's map must hold a picture")
        self.light = light
        self.texture = texture
        self.image = image^
        self.frame = frame
        self.normal_bias = normal_bias

    def tint(self, position: Vector3, normal: Vector3) -> Vector3:
        """Return what the light's color is multiplied by at a surface:
        the picture's color where the surface lands on it, and one outside
        it.

        Args:
            position: Where the surface is, in world space.
            normal: Its unit normal, for the normal bias.

        Returns:
            The red, green and blue multipliers, linear.
        """
        var place = shadow_coordinate(
            self.frame, biased_position(position, normal, self.normal_bias)
        )
        if not inside_spot_map(place):
            return Vector3(1, 1, 1)
        var color = self.image.sample_level(place.x, 1 - place.y, 0)
        return Vector3(color.r, color.g, color.b)
