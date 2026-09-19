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

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, directional_light
from materials.material import (
    Material,
    PointSize,
    points_material,
    sprite_material,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import Sprite
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.srgb import LINEAR
from render.texture import BILINEAR, CLAMP, IGNORED, Texture, checkerboard
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin, sqrt
from std.pathlib import Path
from std.sys import argv
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
            var reach = sqrt(dx * dx + dy * dy) * 2
            var inside = 1 - reach * reach * reach
            if inside < 0:
                inside = 0
            var green = UInt8(inside * 255)
            pixels.append(0)
            pixels.append(green)
            pixels.append(0)
            pixels.append(255)
    return Texture(size, size, pixels^, CLAMP, BILINEAR, LINEAR, True, IGNORED)


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the group by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometries, materials and textures.
        scene: The persistent scene, edited in place.
        node: The node everything hangs from.
        step: How much further to turn this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(node).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))

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

    var lamp = Object3D()
    lamp.set_position(0.5, 0.9, 0.8)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.79))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.51))

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.9, 4.0), Vector3(0, 0.1, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, node, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
