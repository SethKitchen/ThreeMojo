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
planes from `LightShadow`, except that a light with a `distance` puts its
far plane there, as three.js's `updateMatrices` does.

**A point light draws six maps.** It shines every way, so no one camera
sees all it lights. three.js's `PointLightShadow` draws six ninety-degree
views from the bulb, one along each axis, with the directions and ups of
its `_cubeDirections` and `_cubeUps`, and stores in each texel not the
camera's depth but the distance from the bulb, from zero at the near
plane to one at the far. A fragment is compared along the way from the
bulb to it: `cube_texel` finds the face and the texel that direction
crosses. See `point_shadow_tap` for the nine taps.

**A spot light can project a picture.** three.js's `SpotLight.map` is a
texture seen through the spot light's shadow camera, and the light's
color is multiplied by what it shows where a fragment lands on it: a
slide projector. `SpotLightMap` holds it.

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
from render.texture import Texture
from render.texture_store import TextureId
from std.math import isfinite, max, min, sqrt
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
# frame; the depths follow. See `render.gpu.flatten_lights`. A point
# light's cube puts its bulb's position, its near plane and its far plane
# in the first five of the frame's floats instead, and zeros after them.
comptime SHADOW_HEADER = 20
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
        self.cube = False
        self.origin = Vector3(0, 0, 0)
        self.near = 0
        self.far = 0

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

        Raises:
            Error: If the size is not positive, the depths do not fill six
                squares, or the far plane does not lie beyond the near
                plane.
        """
        if size <= 0:
            raise Error("A shadow map must be at least one texel a side")
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
        self.cube = True
        self.origin = origin
        self.near = near
        self.far = far

    def lit(self, position: Vector3, normal: Vector3) -> Float32:
        """Return how much of the light reaches a surface, one for all of
        it and zero for none: `pcf_shadow` over this map, or three.js's
        `getPointShadow` over a cube.

        Args:
            position: Where the surface is, in world space.
            normal: Its unit normal, for the normal bias.

        Returns:
            The fraction of the nine taps that found nothing in the way.
        """
        if self.cube:
            return self._cube_lit(position, normal)
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
        var spread = point_shadow_spread(self.radius, self.size)
        var total = Float32(0)
        for tap in range(PCF_TAPS):  # pragma: no branch
            var texel = cube_texel(
                point_shadow_tap(way, tap, spread), self.size
            )
            total += cube_tap(self.depths[texel], depth)
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
