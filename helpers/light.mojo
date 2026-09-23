# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Where a light is and which way it shines, drawn as lines, from three.js
`src/helpers/DirectionalLightHelper.js`, `PointLightHelper.js`,
`HemisphereLightHelper.js`, `SpotLightHelper.js` and
`examples/jsm/helpers/RectAreaLightHelper.js`.

Each builder reads one `Light` and the scene its node is in, and returns
the lines three.js draws for it, in world space. The `Line` belongs on a
node at the origin. The helper shows the light as it stood when it was
built: build it again after the light or its node moves, as three.js's
helpers need `update()`.

Each helper takes the light's own color unless a color is given, as
three.js's does when its `color` argument is left out.

**What three.js turns, and what it scales.** Three of the helpers aim a
part of themselves with `lookAt`: the directional light's square and its
line to the target, the spot light's cone, and the hemisphere light's
octahedron. Here those parts are placed at the light node's world
position and turned the way `lookAt` turns them, with +y up. three.js
also scales them by the light node's world scale, as they are children of
a helper that takes the light's world matrix. That scale is not applied
here: the parts keep the size the helper is given. The point light's
octahedron takes the light node's whole world matrix, as three.js's does,
and the rect area light's rectangle takes its rotation and position and
not its scale, which is what three.js's `updateMatrixWorld` does too.

**Wireframes are written as their edges.** three.js draws the point light
and the hemisphere light as wireframe meshes. The point light's sphere of
four by two segments is an octahedron, and its twelve edges are written
once each. The hemisphere light's octahedron is written face by face,
three edges a face, so each edge is written twice: once in the color of
each face that holds it, as three.js's wireframe draws it.
"""

from core.buffer_geometry import BufferGeometry
from core.object3d import NO_PARENT, facing
from core.scene import Scene
from helpers.segments import Segments
from lights.light import (
    DIRECTIONAL,
    HEMISPHERE,
    Light,
    LightKind,
    POINT,
    RECT_AREA,
    SPOT,
)
from math.matrix4 import Matrix4, scaling, translation
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from std.math import cos, pi, sin, tan
from units.si import Length, METER, RADIAN

# three.js's defaults: a square, a sphere and an octahedron of one unit.
comptime DEFAULT_LIGHT_HELPER_SIZE = Length(1.0, METER)
# How far a spot light's cone reaches when the light has no cutoff
# distance, three.js's `1000`.
comptime SPOT_HELPER_REACH = Float32(1000)
# How many segments make the rim of a spot light's cone.
comptime SPOT_HELPER_RIM = 32


def _check(light: Light, kind: LightKind, name: String) raises:
    """Refuse a light that is not of `kind`, or that its kind refuses."""
    if not light.kind.is_valid() or light.kind != kind:
        raise Error("A " + name + " helper needs a " + name)
    light.validate()


def _paint(light: Light, color: Optional[Color]) -> FloatColor:
    """Return `color` decoded if one is given, else the light's own color."""
    if Bool(color):
        return FloatColor(srgb=color.value())
    return FloatColor(srgb=light.color)


def _positive(size: Length, name: String) raises -> Float32:
    """Return `size` in meters, refusing one that is not positive."""
    var meters = size.to(METER)
    if meters <= 0:
        raise Error("A " + name + " helper needs a positive size")
    return meters


def _target(light: Light, scene: Scene) raises -> Vector3:
    """Return where a light's target is in world space: its node's world
    position, or the origin for `NO_PARENT`."""
    if light.target == NO_PARENT:
        return Vector3(0, 0, 0)
    return scene.world_position(light.target)


def _aimed(position: Vector3, target: Vector3) raises -> Matrix4:
    """Return the transform that puts a part at `position` with its +z
    toward `target` and +y up, as three.js's `Object3D.lookAt` turns it."""
    var place = translation(position.x, position.y, position.z)
    place.multiply(
        facing(position, target, Vector3(0, 1, 0), False).to_matrix()
    )
    return place^


def directional_light_helper(
    light: Light,
    scene: Scene,
    size: Length = DEFAULT_LIGHT_HELPER_SIZE,
    color: Optional[Color] = None,
) raises -> BufferGeometry:
    """Return a square at a directional light and a line to its target,
    for a `Line` in `SEGMENTS` mode on a node at the origin.

    Args:
        light: A directional light.
        scene: The scene its node and target are in, up to date.
        size: Half the side of the square, three.js's `size`. Must be
            positive.
        color: The color of every line, as authored in sRGB. The light's
            own color when unset.

    Returns:
        Ten points, two per segment: the four sides of the square, facing
        the target, then the line from the light to its target. A `color`
        attribute in linear light.

    Raises:
        Error: If the light is not a directional light or is refused by
            `Light.validate`, `size` is not positive, or the scene cannot
            give a world position.
    """
    _check(light, DIRECTIONAL, "directional light")
    var half = _positive(size, "directional light")
    var paint = _paint(light, color)
    var start = scene.world_position(light.node)
    var end = _target(light, scene)
    var place = _aimed(start, end)
    var square: List[Vector3] = [
        Vector3(-half, half, 0),
        Vector3(half, half, 0),
        Vector3(half, -half, 0),
        Vector3(-half, -half, 0),
        Vector3(-half, half, 0),
    ]
    var segments = Segments()
    segments.add_strip(square, place, paint)
    # three.js's `targetLine`, one unit along +z scaled to the distance.
    var reach = (end - start).length()
    segments.add(start, place.transform_point(Vector3(0, 0, reach)), paint)
    return segments.geometry()


def point_light_helper(
    light: Light,
    scene: Scene,
    sphere_size: Length = DEFAULT_LIGHT_HELPER_SIZE,
    color: Optional[Color] = None,
) raises -> BufferGeometry:
    """Return the wireframe sphere three.js draws at a point light, for a
    `Line` in `SEGMENTS` mode on a node at the origin.

    three.js's `SphereGeometry(sphereSize, 4, 2)` has two poles and four
    points on its equator, which is an octahedron.

    Args:
        light: A point light.
        scene: The scene its node is in, up to date.
        sphere_size: The sphere's radius. Must be positive.
        color: The color of every line, as authored in sRGB. The light's
            own color when unset.

    Returns:
        Twenty-four points, two per edge: the four edges from the top pole,
        the four around the equator, and the four to the bottom pole,
        carried through the light node's world matrix. A `color` attribute
        in linear light.

    Raises:
        Error: If the light is not a point light or is refused by
            `Light.validate`, `sphere_size` is not positive, or the scene
            cannot give a world matrix.
    """
    _check(light, POINT, "point light")
    var radius = _positive(sphere_size, "point light")
    var paint = _paint(light, color)
    var place = scene.world_matrix(light.node)
    # three.js's equator, from u = 0 around: x = -r cos(u), z = r sin(u).
    var equator: List[Vector3] = [
        Vector3(-radius, 0, 0),
        Vector3(0, 0, radius),
        Vector3(radius, 0, 0),
        Vector3(0, 0, -radius),
    ]
    var top = place.transform_point(Vector3(0, radius, 0))
    var bottom = place.transform_point(Vector3(0, -radius, 0))
    var segments = Segments()
    for side in range(4):  # pragma: no branch
        segments.add(top, place.transform_point(equator[side]), paint)
    for side in range(4):  # pragma: no branch
        segments.add(
            place.transform_point(equator[side]),
            place.transform_point(equator[(side + 1) % 4]),
            paint,
        )
    for side in range(4):  # pragma: no branch
        segments.add(place.transform_point(equator[side]), bottom, paint)
    return segments.geometry()


def hemisphere_light_helper(
    light: Light,
    scene: Scene,
    size: Length = DEFAULT_LIGHT_HELPER_SIZE,
    color: Optional[Color] = None,
) raises -> BufferGeometry:
    """Return the wireframe octahedron three.js draws at a hemisphere
    light, sky colored on the side toward the sky, for a `Line` in
    `SEGMENTS` mode on a node at the origin.

    three.js's `OctahedronGeometry(size)` turned a quarter turn about y,
    then aimed with its +z away from the sky: its -z corner points the way
    the light's node sits from the origin. Its first four faces take the
    sky color and its last four the ground color.

    Args:
        light: A hemisphere light.
        scene: The scene its node is in, up to date.
        size: The distance from the center to each corner. Must be
            positive.
        color: One color for every line, as authored in sRGB. The sky and
            ground colors when unset.

    Returns:
        Forty-eight points: three edges for each of the eight faces, in
        three.js's order, at the light node's world position. A `color`
        attribute in linear light.

    Raises:
        Error: If the light is not a hemisphere light or is refused by
            `Light.validate`, `size` is not positive, or the scene cannot
            give a world position.
    """
    _check(light, HEMISPHERE, "hemisphere light")
    var reach = _positive(size, "hemisphere light")
    var sky = FloatColor(srgb=light.color)
    var ground = FloatColor(srgb=light.ground)
    if Bool(color):
        sky = FloatColor(srgb=color.value())
        ground = sky
    var position = scene.world_position(light.node)
    var place = _aimed(position, -position)
    place.multiply(scaling(reach, reach, reach))
    # three.js's six corners, already turned by `rotateY(pi / 2)`, which
    # takes (x, y, z) to (z, y, -x).
    var corners: List[Vector3] = [
        Vector3(0, 0, -1),
        Vector3(0, 0, 1),
        Vector3(0, 1, 0),
        Vector3(0, -1, 0),
        Vector3(1, 0, 0),
        Vector3(-1, 0, 0),
    ]
    # And its eight faces, as corner numbers.
    var faces: List[Int] = [
        0,
        2,
        4,
        0,
        4,
        3,
        0,
        3,
        5,
        0,
        5,
        2,
        1,
        2,
        5,
        1,
        5,
        3,
        1,
        3,
        4,
        1,
        4,
        2,
    ]
    var segments = Segments()
    for face in range(8):  # pragma: no branch
        var paint = ground
        if face < 4:
            paint = sky
        var a = place.transform_point(corners[faces[face * 3]])
        var b = place.transform_point(corners[faces[face * 3 + 1]])
        var c = place.transform_point(corners[faces[face * 3 + 2]])
        # A face is stored b, c, a, and its wireframe joins each point to
        # the next and the last to the first.
        segments.add(b, c, paint)
        segments.add(c, a, paint)
        segments.add(a, b, paint)
    return segments.geometry()


def spot_light_helper(
    light: Light, scene: Scene, color: Optional[Color] = None
) raises -> BufferGeometry:
    """Return the cone of a spot light, for a `Line` in `SEGMENTS` mode on
    a node at the origin.

    Args:
        light: A spot light.
        scene: The scene its node and target are in, up to date.
        color: The color of every line, as authored in sRGB. The light's
            own color when unset.

    Returns:
        Seventy-four points, two per segment: five lines from the light,
        one along the axis and four to the rim, then the thirty-two
        segments of the rim. The cone reaches the light's `distance`, or a
        thousand meters when it has none, and is as wide as the light's
        `angle`. A `color` attribute in linear light.

    Raises:
        Error: If the light is not a spot light or is refused by
            `Light.validate`, or the scene cannot give a world position.
    """
    _check(light, SPOT, "spot light")
    var paint = _paint(light, color)
    var reach = SPOT_HELPER_REACH
    if light.distance > 0:
        reach = light.distance
    var width = reach * tan(light.angle.to(RADIAN))
    var start = scene.world_position(light.node)
    var place = _aimed(start, _target(light, scene))
    place.multiply(scaling(width, width, reach))
    var apex = place.transform_point(Vector3(0, 0, 0))
    var spokes: List[Vector3] = [
        Vector3(0, 0, 1),
        Vector3(1, 0, 1),
        Vector3(-1, 0, 1),
        Vector3(0, 1, 1),
        Vector3(0, -1, 1),
    ]
    var segments = Segments()
    for spoke in range(len(spokes)):  # pragma: no branch
        segments.add(apex, place.transform_point(spokes[spoke]), paint)
    for step in range(SPOT_HELPER_RIM):  # pragma: no branch
        var first = Float32(step) / Float32(SPOT_HELPER_RIM) * 2 * pi
        var second = Float32(step + 1) / Float32(SPOT_HELPER_RIM) * 2 * pi
        segments.add(
            place.transform_point(Vector3(cos(first), sin(first), 1)),
            place.transform_point(Vector3(cos(second), sin(second), 1)),
            paint,
        )
    return segments.geometry()


def rect_area_light_helper(
    light: Light, scene: Scene, color: Optional[Color] = None
) raises -> BufferGeometry:
    """Return the outline of a rect area light, for a `Line` in `SEGMENTS`
    mode on a node at the origin.

    Unless a color is given, the outline takes the light's color times its
    intensity, in linear light, scaled down so that no channel is above
    one. That keeps the hue, as three.js's helper does.

    Args:
        light: A rect area light.
        scene: The scene its node is in, up to date.
        color: The color of every line, as authored in sRGB. The light's
            color and intensity when unset.

    Returns:
        Eight points, two per side: the rectangle's four sides, in its
        node's frame without the node's scale. A `color` attribute in
        linear light.

    Raises:
        Error: If the light is not a rect area light or is refused by
            `Light.validate`, or the scene cannot give a world matrix, or
            that matrix has a scale of zero on an axis.
    """
    _check(light, RECT_AREA, "rect area light")
    var paint = light.radiance()
    var brightest = max(paint.r, max(paint.g, paint.b))
    if brightest > 1:
        paint = FloatColor(
            paint.r / brightest, paint.g / brightest, paint.b / brightest
        )
    if Bool(color):
        paint = FloatColor(srgb=color.value())
    var world = scene.world_matrix(light.node)
    var center = world.transform_point(Vector3(0, 0, 0))
    var place = translation(center.x, center.y, center.z)
    place.multiply(world.extract_rotation())
    place.multiply(
        scaling(light.width.to(METER) / 2, light.height.to(METER) / 2, 1)
    )
    var outline: List[Vector3] = [
        Vector3(1, 1, 0),
        Vector3(-1, 1, 0),
        Vector3(-1, -1, 0),
        Vector3(1, -1, 0),
        Vector3(1, 1, 0),
    ]
    var segments = Segments()
    segments.add_strip(outline, place, paint)
    return segments.geometry()
