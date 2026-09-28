# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sun whose shadow follows the camera, from three.js
`examples/jsm/lights/SunLight.js`, `SunLightShadow.js`, `SunLightNode.js`
and `SunShadowNode.js`.

three.js's `SunLight` is a light with a position and no target. Its light
travels from its position toward the world origin, and its position is
`Object3D.DEFAULT_UP`, straight up, to begin with. Its shadow is two
cascades, each an orthographic camera fit to one slice of the view
camera's depth, drawn into one atlas.

**How the cascades are fit.** `fit_sun` is `SunLightShadow.updateMatrices`:

1. The view's depth runs from its near plane to its far plane or the
   shadow's far plane, whichever is nearer. It is split halfway between
   an even and a logarithmic split, three.js's practical scheme.
2. The eight corners of the view volume are turned into the light's
   frame, `lookAt( 0, direction, up )`, with up `+y`, or `+z` when the
   light is within about eight degrees of vertical.
3. Each cascade reaches from the fade start of the one before it to its
   split. Its corners are enclosed in a sphere: their middle, and the
   distance to the furthest.
4. The radius is padded by half a texel, and the middle is rounded to
   whole texels of the map, so the shadow does not crawl.
5. The camera stands at the caster ceiling, the highest corner raised by
   the view's depth, plus the shadow's near plane. Its far plane reaches
   the lowest corner of its cascade.

**How the cascades blend.** three.js lights the sun once and mixes the
cascades' shadows by depth: the last tenth of each cascade fades into the
next, and past the last the light has no shadow. Here each cascade is a
directional light that carries a `ShadowCascade` of `SUN_BLEND`, and
`lights.shadow.sun_reach` splits the same blend between them. Both
rasterizers read it.

**The map.** three.js draws both cascades into one atlas two maps wide,
each tile inset by `ceil( radius ) + 1` texels. Here each cascade has a
map of its own, as wide as three.js's tile less its inset, so the texels
are the same size.
"""

from cameras.camera import Camera
from core.object3d import NodeId, Object3D
from core.scene import Scene
from lights.csm import CsmFrustum
from lights.light import directional_light
from lights.shadow import LightShadow, SUN_BLEND, ShadowCascade
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.framebuffer import Color
from std.math import ceil, floor, isfinite, log, exp, max, min, sqrt
from units.si import Length, METER

# How many cascades a sun draws, three.js's `_cascadeCount`.
comptime SUN_CASCADES = 2
# How much of each cascade's depth fades into the next, three.js's
# `_cascadeFade`.
comptime SUN_CASCADE_FADE = Float32(0.1)
# three.js's `SunLightShadow` map: 1024 texels a side.
comptime SUN_MAP_SIZE = 1024


def sun_light_shadow() -> LightShadow:
    """Return a sun's shadow with three.js's `SunLightShadow` defaults: a
    map 1024 texels a side, a near plane of half a meter and a far plane
    of 500 meters.

    Returns:
        The shadow.
    """
    var shadow = LightShadow()
    shadow.map_size = SUN_MAP_SIZE
    shadow.near = Length(0.5, METER)
    shadow.far = Length(500.0, METER)
    return shadow^


@fieldwise_init
struct SunCascade(ImplicitlyCopyable):
    """One cascade of a sun, fit to one slice of the view."""

    # Where its camera stands, in world space.
    var position: Vector3
    # Each edge of its camera from the axis: the sphere's padded radius.
    var radius: Float32
    # Its camera's near and far planes, from where it stands.
    var near: Float32
    var far: Float32
    # Where the cascade begins and ends, in meters in front of the view,
    # and where its shadow starts to fade, three.js's `_cascadeData`.
    var start: Float32
    var end: Float32
    var fade_start: Float32
    # Where the cascade before it ends: its light ramps in from `start`.
    var ramp_end: Float32

    def band(self, last: Bool) -> ShadowCascade:
        """Return the cascade as its light carries it.

        Args:
            last: Whether it is the furthest cascade.

        Returns:
            A `SUN_BLEND` cascade over a span of one meter.
        """
        return ShadowCascade(
            self.start,
            self.end,
            Length(1.0, METER),
            last,
            False,
            SUN_BLEND,
            self.fade_start,
            self.ramp_end,
        )


struct SunFit(Copyable, Movable):
    """Where a sun's cascades stand for one view."""

    # Which way the light travels, unit length.
    var direction: Vector3
    # How many texels a side each cascade's map is: three.js's tile less
    # its inset.
    var resolution: Int
    var cascades: List[SunCascade]

    def __init__(
        out self,
        direction: Vector3,
        resolution: Int,
        var cascades: List[SunCascade],
    ):
        """Hold a fit.

        Args:
            direction: Which way the light travels.
            resolution: Each cascade's map, texels a side.
            cascades: The cascades, nearest first.
        """
        self.direction = direction
        self.resolution = resolution
        self.cascades = cascades^


def sun_splits(near: Float32, far: Float32) -> List[Float32]:
    """Return where a sun's cascades begin and end: three.js's practical
    split, halfway between an even and a logarithmic split.

    Args:
        near: The view's near plane.
        far: Where the shadow stops.

    Returns:
        `SUN_CASCADES + 1` depths, from `near` to `far`.
    """
    var splits = List[Float32]()
    splits.append(near)
    for index in range(1, SUN_CASCADES):  # pragma: no branch
        var amount = Float32(index) / Float32(SUN_CASCADES)
        var even = near + (far - near) * amount
        var logarithmic = even
        if near > 0:
            logarithmic = near * exp(log(far / near) * amount)
        splits.append((even + logarithmic) * 0.5)
    splits.append(far)
    return splits^


def fit_sun[
    C: Camera
](
    scene: Scene, camera: C, position: Vector3, shadow: LightShadow
) raises -> SunFit:
    """Return where a sun's cascades stand to shadow what a camera sees:
    three.js's `SunLightShadow.updateMatrices`.

    Args:
        scene: The scene the camera stands in, updated.
        camera: The view camera.
        position: Where the sun is, in world space. Its light travels
            from there toward the origin.
        shadow: The sun's shadow: its map size, its radius, and its near
            and far planes.

    Returns:
        The fit.

    Raises:
        Error: If the sun is at the origin, or the camera's view or
            projection is refused.
    """
    var length = position.length()
    if not isfinite(length) or length == 0:
        raise Error("A sun at the origin has no direction")
    var direction = -position
    direction.normalize()
    var size = Float32(shadow.map_size)
    var inset = min(Float32(0.25), (ceil(shadow.radius) + 1) / size)
    var resolution = size * (1 - 2 * inset)
    var camera_near = camera.near_distance()
    var camera_far = max(
        camera_near + Float32(1e-6),
        min(shadow.far.to(METER), camera.far_distance()),
    )
    var splits = sun_splits(camera_near, camera_far)
    var up = Vector3(0, 1, 0)
    if abs(up.dot(direction)) > 0.99:
        up = Vector3(0, 0, 1)
    var orientation = Matrix4()
    orientation.look_at(Vector3(0, 0, 0), direction, up)
    var to_light = orientation
    to_light.invert()
    var placed = camera.view_matrix_in(scene)
    placed.invert()
    to_light.multiply(placed)
    var projection = camera.projection_matrix()
    var perspective = projection.elements[11] != 0
    var inverse = projection
    inverse.invert()
    var view = CsmFrustum.empty()
    # Four corners, always.
    for corner in range(4):  # pragma: no branch
        var x = Float32(1) if corner < 2 else Float32(-1)
        var y = Float32(1) if corner == 0 or corner == 3 else Float32(-1)
        var near = inverse.transform_point(Vector3(x, y, -1))
        var far = Vector3(near.x, near.y, -camera_far)
        if perspective:
            far = near * (camera_far / camera_near)
        view.near[corner] = near
        view.far[corner] = far
    var seen = view.to_space(to_light)
    var ceiling = seen.near[0].z
    for corner in range(4):  # pragma: no branch
        ceiling = max(ceiling, max(seen.near[corner].z, seen.far[corner].z))
    # One shadow range toward the light, so casters outside the view cast.
    ceiling += camera_far
    var shadow_near = shadow.near.to(METER)
    var cascades = List[SunCascade]()
    var previous_fade = splits[0]
    for index in range(SUN_CASCADES):  # pragma: no branch
        var cascade_near = splits[0] if index == 0 else previous_fade
        var cascade_far = splits[index + 1]
        var fade_start = cascade_far - SUN_CASCADE_FADE * (
            cascade_far - splits[index]
        )
        var near_alpha = (cascade_near - camera_near) / (
            camera_far - camera_near
        )
        var far_alpha = (cascade_far - camera_near) / (camera_far - camera_near)
        var center = Vector3(0, 0, 0)
        var corners = CsmFrustum.empty()
        for corner in range(4):  # pragma: no branch
            corners.near[corner].lerp_vectors(
                seen.near[corner], seen.far[corner], near_alpha
            )
            corners.far[corner].lerp_vectors(
                seen.near[corner], seen.far[corner], far_alpha
            )
            center = center + corners.near[corner] + corners.far[corner]
        center = center * Float32(0.125)
        var radius_sq = Float32(0)
        var low = corners.near[0].z
        for corner in range(4):  # pragma: no branch
            radius_sq = max(
                radius_sq,
                max(
                    (corners.near[corner] - center).length_sq(),
                    (corners.far[corner] - center).length_sq(),
                ),
            )
            low = min(low, min(corners.near[corner].z, corners.far[corner].z))
        var radius = sqrt(radius_sq)
        if resolution > 1:
            # Half a texel of padding, so snapping cannot clip a corner.
            radius /= 1 - 1 / resolution
            var texel = 2 * radius / resolution
            center.x = floor(center.x / texel + 0.5) * texel
            center.y = floor(center.y / texel + 0.5) * texel
        center.z = ceiling + shadow_near
        var start = cascade_near if index > 0 else Float32(0)
        cascades.append(
            SunCascade(
                orientation.transform_point(center),
                radius,
                shadow_near,
                ceiling - low + 2 * shadow_near,
                start,
                cascade_far,
                fade_start,
                start if index == 0 else splits[index],
            )
        )
        previous_fade = fade_start
    return SunFit(direction, max(1, Int(resolution)), cascades^)


struct SunLight(Movable):
    """A light with a position and no target, whose shadow is two
    cascades fit to the view: three.js's `SunLight`."""

    # Its color and how bright, as on any light.
    var color: Color
    var intensity: Float32
    # Whether it casts, three.js's `castShadow`. Off by default, as on
    # every three.js light.
    var cast_shadow: Bool
    # Its shadow, three.js's `SunLightShadow`: the map size, the planes,
    # the biases, the radius and the intensity every cascade takes.
    var shadow: LightShadow
    # Where the sun is, three.js's `position`: a node at `(0, 1, 0)` to
    # begin with. Its light travels from there toward the origin.
    var node: NodeId
    # One directional light per cascade, as its index in `Scene.lights`,
    # with the node its camera stands on and the node it looks at.
    var lights: List[Int]
    var nodes: List[NodeId]
    var targets: List[NodeId]

    def __init__(
        out self,
        mut scene: Scene,
        color: Color = Color(255, 255, 255),
        intensity: Float32 = 1.0,
    ) raises:
        """Add a sun to a scene, three.js's `new SunLight( color,
        intensity )`.

        Args:
            scene: The scene to add the sun's node and its cascades to.
            color: Its color.
            intensity: How bright, multiplying the color.

        Raises:
            Error: If `Light.validate` refuses the intensity.
        """
        self.color = color
        self.intensity = intensity
        self.cast_shadow = False
        self.shadow = sun_light_shadow()
        var place = Object3D()
        place.set_position(0, 1, 0)
        self.node = scene.add(place^)
        self.lights = List[Int]()
        self.nodes = List[NodeId]()
        self.targets = List[NodeId]()
        for index in range(SUN_CASCADES):  # pragma: no branch
            var stand = Object3D()
            stand.set_position(0, 1, 0)
            var node = scene.add(stand^)
            var target = scene.add(Object3D())
            var light = directional_light(color, node, intensity, target)
            var last = index == SUN_CASCADES - 1
            # Until the first fit, the last cascade lights every depth
            # with no shadow and the others light nothing.
            light.cascade = ShadowCascade(
                0, 0, Length(1.0, METER), last, False, SUN_BLEND, 0, 0
            )
            light.validate()
            self.lights.append(len(scene.lights))
            self.nodes.append(node)
            self.targets.append(target)
            scene.add_light(light)
        scene.update()

    def update[C: Camera](self, mut scene: Scene, camera: C) raises:
        """Fit the cascades to what a camera sees now, three.js's
        `SunShadowNode.renderShadow`, and update the scene.

        Each cascade light takes the sun's color, intensity, shadow and
        `cast_shadow`, and its slice of the view.

        Args:
            scene: The scene holding the sun, updated.
            camera: The view camera.

        Raises:
            Error: If the cascades this added are gone from the scene, the
                sun is at the origin, the shadow is refused by
                `LightShadow.validate`, or the camera's view is refused.
        """
        # One light per cascade, always.
        for index in range(len(self.lights)):  # pragma: no branch
            var at = self.lights[index]
            if at >= len(scene.lights) or (
                scene.lights[at].node != self.nodes[index]
            ):
                raise Error("A sun's cascades are not in this scene")
        self.shadow.validate()
        var fit = fit_sun(
            scene, camera, scene.world_position(self.node), self.shadow
        )
        for index in range(SUN_CASCADES):  # pragma: no branch
            ref cascade = fit.cascades[index]
            ref light = scene.lights[self.lights[index]]
            light.color = self.color
            light.intensity = self.intensity
            light.cast_shadow = self.cast_shadow
            light.shadow = self.shadow
            light.shadow.map_size = fit.resolution
            light.shadow.set_extent(Length(cascade.radius, METER))
            light.shadow.near = Length(cascade.near, METER)
            light.shadow.far = Length(cascade.far, METER)
            light.cascade = cascade.band(index == SUN_CASCADES - 1)
            light.validate()
            var aim = cascade.position + fit.direction
            scene.node(self.nodes[index]).set_position(
                cascade.position.x, cascade.position.y, cascade.position.z
            )
            scene.node(self.targets[index]).set_position(aim.x, aim.y, aim.z)
        scene.update()
