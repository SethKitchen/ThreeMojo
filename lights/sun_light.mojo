# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sun whose shadow follows the camera, from three.js
`examples/jsm/lights/SunLight.js` and its `SunLightShadow`.

A directional light in three.js shines from its position toward its
target, and its shadow camera is a box of a fixed size around that line.
A sun has neither a position nor a target: only the way its light
travels. `SunLight` holds that direction, and `update` places the light
and its shadow camera for each frame so the shadow covers what the
camera sees, three.js's `SunLightShadow.updateMatrices`.

**How the shadow is fit.** The camera's view volume, from its near plane
to its far plane or `max_distance`, whichever is nearer, is enclosed in
a sphere: the middle of its eight corners, and the distance to the
furthest. The radius is rounded up to a sixteenth of a meter, so it
does not change as the camera turns. The shadow camera is a square two
radii across, around the sphere. Its middle is snapped to whole texels
of the map along the light's two other axes, so the shadow does not
crawl as the camera moves. The light stands `margin` beyond the sphere,
back along its direction, so a caster between the sun and the view
still casts.

A sphere rather than a tight box wastes some texels. It keeps the size
of the map's texels the same whatever way the camera turns, which a tight
box does not. This is what `CSM` does for each cascade, for one cascade.

**What is built.** The constructor adds a node, a target node and a
casting directional light to the scene, at its root, as world positions
are what `update` writes. Call `update` after the camera
moves. The light is an ordinary directional light: both rasterizers
draw it and its shadow as they draw any other.
"""

from cameras.camera import Camera
from core.object3d import NodeId, Object3D
from core.scene import Scene
from lights.csm import CsmFrustum
from lights.light import directional_light
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.framebuffer import Color
from std.math import ceil, floor, isfinite, max, min
from units.si import Length, METER

# How far into the view the shadow reaches by default, from the camera.
comptime DEFAULT_SUN_DISTANCE = Length(100.0, METER)
# How far beyond the view the sun stands by default, to catch casters
# between it and the view.
comptime DEFAULT_SUN_MARGIN = Length(50.0, METER)
# What the sphere's radius is rounded up to a whole number of.
comptime SUN_RADIUS_STEP = Float32(0.0625)


struct SunLightShadow(ImplicitlyCopyable):
    """How a sun's shadow is fit to the view, three.js's
    `SunLightShadow`."""

    # The furthest depth in front of the camera the shadow covers.
    var max_distance: Length
    # How far beyond the view's sphere the light stands.
    var margin: Length
    # How many texels a side the map is.
    var map_size: Int

    def __init__(
        out self,
        max_distance: Length = DEFAULT_SUN_DISTANCE,
        margin: Length = DEFAULT_SUN_MARGIN,
        map_size: Int = 2048,
    ):
        """Set how the shadow is fit.

        Args:
            max_distance: The furthest depth the shadow covers.
            margin: How far beyond the view the light stands.
            map_size: How many texels a side the map is.
        """
        self.max_distance = max_distance
        self.margin = margin
        self.map_size = map_size

    def validate(self) raises:
        """Refuse numbers the fit cannot use.

        Raises:
            Error: If the distance is not a positive finite length, the
                margin is negative or not finite, or the map is not one
                to 8192 texels a side.
        """
        var reach = self.max_distance.to(METER)
        if not isfinite(reach) or reach <= 0:
            raise Error("A sun's shadow distance must be a positive length")
        var margin = self.margin.to(METER)
        if not isfinite(margin) or margin < 0:
            raise Error("A sun's shadow margin must be finite and not negative")
        if self.map_size < 1 or self.map_size > 8192:
            raise Error("A shadow map must be one to 8192 texels a side")


@fieldwise_init
struct SunFit(ImplicitlyCopyable):
    """Where a sun stands and how wide its shadow camera is, for one
    view."""

    # Where the light's node goes.
    var position: Vector3
    # Where its target goes: the middle of the view's sphere.
    var target: Vector3
    # The sphere's radius: each edge of the shadow camera from its axis.
    var radius: Float32
    # Where the shadow camera's far plane goes, from the light.
    var far: Float32


def fit_sun[
    C: Camera
](
    scene: Scene, camera: C, direction: Vector3, shadow: SunLightShadow
) raises -> SunFit:
    """Return where a sun stands to shadow what a camera sees.

    Args:
        scene: The scene the camera stands in, updated.
        camera: The camera to fit to.
        direction: Which way the light travels, unit length.
        shadow: How the fit is made.

    Returns:
        The fit.

    Raises:
        Error: If the camera's view or projection is refused.
    """
    var reach = min(camera.far_distance(), shadow.max_distance.to(METER))
    var seen = CsmFrustum.from_projection(camera.projection_matrix(), reach)
    var placed = camera.view_matrix_in(scene)
    placed.invert()
    var world = seen.to_space(placed)
    var center = Vector3(0, 0, 0)
    # Four corners, always.
    for corner in range(4):  # pragma: no branch
        center = center + world.near[corner] + world.far[corner]
    center = center * Float32(0.125)
    var radius = Float32(0)
    for corner in range(4):  # pragma: no branch
        radius = max(radius, (world.near[corner] - center).length())
        radius = max(radius, (world.far[corner] - center).length())
    radius = ceil(radius / SUN_RADIUS_STEP) * SUN_RADIUS_STEP
    var orientation = Matrix4()
    orientation.look_at(Vector3(0, 0, 0), direction, Vector3(0, 1, 0))
    var inverse = orientation
    inverse.invert()
    var texel = 2 * radius / Float32(shadow.map_size)
    var local = inverse.transform_point(center)
    local.x = floor(local.x / texel) * texel
    local.y = floor(local.y / texel) * texel
    var snapped = orientation.transform_point(local)
    var back = radius + shadow.margin.to(METER)
    return SunFit(snapped - direction * back, snapped, radius, back + radius)


struct SunLight(Movable):
    """A directional light with a direction and no target, whose shadow
    is fit to the view: three.js's `SunLight`."""

    # Which way the light travels, unit length.
    var direction: Vector3
    var shadow: SunLightShadow
    # The light, as its index in `Scene.lights`, and its node and its
    # target's node.
    var light: Int
    var node: NodeId
    var target: NodeId

    def __init__(
        out self,
        mut scene: Scene,
        color: Color = Color(255, 255, 255),
        intensity: Float32 = 1.0,
        direction: Vector3 = Vector3(-1, -2, -1),
        shadow: SunLightShadow = SunLightShadow(),
        cast_shadow: Bool = True,
    ) raises:
        """Add the sun's light to a scene.

        Args:
            scene: The scene to add the light and its two nodes to.
            color: Its color.
            intensity: How bright, multiplying the color.
            direction: Which way the light travels; normalized here.
            shadow: How the shadow is fit to the view.
            cast_shadow: Whether the sun casts a shadow.

        Raises:
            Error: If the direction is zero or not finite, the shadow is
                refused by `SunLightShadow.validate`, or the light is
                refused by `Light.validate`.
        """
        self.direction = _unit(direction)
        shadow.validate()
        self.shadow = shadow
        self.node = scene.add(Object3D())
        self.target = scene.add(Object3D())
        var light = directional_light(color, self.node, intensity, self.target)
        light.cast_shadow = cast_shadow
        light.shadow.map_size = shadow.map_size
        light.validate()
        self.light = len(scene.lights)
        scene.add_light(light)
        scene.node(self.node).set_position(
            -self.direction.x, -self.direction.y, -self.direction.z
        )
        scene.update()

    def set_direction(mut self, direction: Vector3) raises:
        """Turn the sun. Call `update` after it.

        Args:
            direction: Which way the light travels; normalized here.

        Raises:
            Error: If the direction is zero or not finite.
        """
        self.direction = _unit(direction)

    def update[C: Camera](self, mut scene: Scene, camera: C) raises:
        """Place the light and size its shadow camera for what a camera
        sees now, and update the scene.

        Args:
            scene: The scene holding the sun's light, updated.
            camera: The camera to fit to.

        Raises:
            Error: If the light this added is gone from the scene, or the
                camera's view is refused.
        """
        if self.light >= len(scene.lights) or (
            scene.lights[self.light].node != self.node
        ):
            raise Error("A sun's light is not in this scene")
        var fit = fit_sun(scene, camera, self.direction, self.shadow)
        ref shadow = scene.lights[self.light].shadow
        shadow.map_size = self.shadow.map_size
        shadow.set_extent(Length(fit.radius, METER))
        shadow.near = Length(0.0, METER)
        shadow.far = Length(fit.far, METER)
        scene.node(self.node).set_position(
            fit.position.x, fit.position.y, fit.position.z
        )
        scene.node(self.target).set_position(
            fit.target.x, fit.target.y, fit.target.z
        )
        scene.update()


def _unit(direction: Vector3) raises -> Vector3:
    """Return a direction made unit length, or refuse a zero or infinite
    one."""
    var length = direction.length()
    if not isfinite(length) or length == 0:
        raise Error("A sun's direction must be finite and not zero")
    var unit = direction
    unit.normalize()
    return unit
