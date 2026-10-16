# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A box with a ring of round points around it and two sprites beside it.

    mojo run -I . examples/sprites.mojo [path.png]

The page is Points and sprites. The points orbit the box and shrink as
they swing behind it, because their size is attenuated by distance: a
size of 0.6 is fourteen pixels four meters from the camera. They
are round because their alpha map is a disc: a point is a square, and a
disc cut out of it is what a particle usually is. The checkered sprite
faces the camera however the group turns, turned a little about the line
of sight by its material. The small blue sprite keeps its size on the
image as it orbits, because its attenuation is off.
"""

from examples.output import (
    example_destination,
    fill_and_key,
    gallery_camera,
    gallery_renderer,
    spin_clip,
)

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from materials.material import (
    Material,
    PointSize,
    points_material,
    sprite_material,
)
from math.norm import squared_length2
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import Sprite
from render.framebuffer import Color
from render.srgb import LINEAR
from render.texture import BILINEAR, CLAMP, IGNORED, Texture, checkerboard
from std.math import cos, pi, sin, sqrt
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/sprites.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
# How far the points stand from the box's center.
comptime RING = Float32(1.3)


def a_ring(count: Int) raises -> BufferGeometry:
    """Return `count` points around a tilted circle.

    Args:
        count: How many points.

    Returns:
        A geometry holding them.

    Raises:
        Error: If the numbers do not divide into vertices.
    """
    var numbers = List[Float32]()
    for point in range(count):
        var turn = 2 * pi * Float32(point) / Float32(count)
        numbers.append(RING * cos(turn))
        numbers.append(0.35 * sin(2 * turn))
        numbers.append(RING * sin(turn))
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(numbers^, 3))
    return geometry^


def a_disc(size: Int) raises -> Texture:
    """Return an alpha map that is a soft disc: full in the middle, falling
    to nothing at the edge of the square.

    An alpha map holds data, so it is linear and ignores its own alpha;
    see the Materials page.

    Args:
        size: How many texels across.

    Returns:
        The texture.

    Raises:
        Error: If the texture cannot be built.
    """
    var pixels = List[UInt8]()
    for y in range(size):
        for x in range(size):
            var dx = (Float32(x) + 0.5) / Float32(size) - 0.5
            var dy = (Float32(y) + 0.5) / Float32(size) - 0.5
            var reach = sqrt(squared_length2[DType.float32](dx, dy)) * 2
            var inside = 1 - reach * reach * reach
            if inside < 0:
                inside = 0
            var green = UInt8(inside * 255)
            pixels.append(0)
            pixels.append(green)
            pixels.append(0)
            pixels.append(255)
    return Texture(size, size, pixels^, CLAMP, BILINEAR, LINEAR, True, IGNORED)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))

    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var ring = assets.geometries.add(a_ring(28))
    var disc = assets.textures.add(a_disc(32))
    var board = assets.textures.add(
        checkerboard(32, 4, Color(255, 235, 190), Color(70, 50, 140))
    )
    var paint = assets.materials.add(Material(Color(70, 110, 200)))
    # Round, translucent particles: a square point with a disc cut out of
    # it, blended over what is behind.
    var sparks = assets.materials.add(
        points_material(
            Color(255, 200, 90),
            size=PointSize(0.6),
            alpha_map=disc,
            transparent=True,
        )
    )
    # A picture that faces the camera, turned a little about the line of
    # sight.
    var label = assets.materials.add(
        sprite_material(map=board, rotation=Angle(15.0, DEGREE))
    )
    # A marker that keeps its size on the image however far away it is.
    var pin = assets.materials.add(
        sprite_material(Color(90, 190, 255), size_attenuation=False)
    )

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(box, paint, node))
    scene.add_points(Points(ring, sparks, node))
    var above = Object3D()
    above.set_position(0, 1.0, 0)
    above.set_scale(0.9, 0.6, 1)
    above.parent = node
    var above_node = scene.add(above^)
    scene.add_sprite(Sprite(label, above_node))
    var beside = Object3D()
    beside.set_position(1.5, -0.6, 0)
    beside.set_scale(0.12, 0.12, 1)
    beside.parent = node
    var beside_node = scene.add(beside^)
    scene.add_sprite(Sprite(pin, beside_node))

    fill_and_key(
        scene,
        0.5,
        0.9,
        0.8,
        Color(255, 255, 255),
        0.79,
        Color(255, 255, 255),
        2.51,
    )

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 0.9, 4.0),
        Vector3(0, 0.1, 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(100.0, METER),
    )

    spin_clip(
        renderer, camera, assets, scene, node, FRAMES, DELAY_MS, destination
    )
