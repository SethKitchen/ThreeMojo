# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A stereo pair, side by side, from a camera circling a box and a ring.

    mojo run -I . examples/stereo.mojo [path.png]

The page is Cameras. A `StereoCamera` makes a left and a right eye from
the circling camera every frame, and an `ArrayCamera` draws each eye
into its own half of one image. Look at the pair cross-eyed and the
ring stands in front of the box. The eyes are set wide apart for a
scene this small, so the parallax shows at this size.
"""

from tools._example_output import (
    example_destination,
    fill_and_key,
    framed_camera,
    gallery_renderer,
    write_example,
)

from cameras.array_camera import ArrayCamera
from cameras.stereo_camera import StereoCamera
from core.assets import Assets
from core.clock import Clock
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.torus import torus
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.rect import Rect
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/stereo.png"
comptime WIDTH = 240
comptime HEIGHT = 120
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime LEFT = Rect(0, 0, WIDTH // 2, HEIGHT)
comptime RIGHT = Rect(WIDTH // 2, 0, WIDTH // 2, HEIGHT)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))
    var assets = Assets()
    var scene = Scene()

    var block = assets.geometries.add(cube(Length(0.8, METER)))
    var ring = assets.geometries.add(
        torus(Length(0.5, METER), Length(0.12, METER), 10, 24)
    )
    var blue = assets.materials.add(Material(Color(70, 110, 200)))
    var gold = assets.materials.add(Material(Color(230, 180, 60)))
    var back = Object3D()
    back.set_position(0, 0, -0.8)
    back.rotate_y(Angle(25.0, DEGREE))
    var block_node = scene.add(back^)
    scene.add_mesh(Mesh(block, blue, block_node))
    var front = Object3D()
    front.set_position(0.3, 0.1, 0.9)
    var ring_node = scene.add(front^)
    scene.add_mesh(Mesh(ring, gold, ring_node))

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

    # The camera between the eyes rides a seat on a pivot and circles the
    # scene; each eye sees half the image, at half the aspect.
    var pivot = scene.add(Object3D())
    var seat = Object3D()
    seat.set_position(0, 0.8, 3.6)
    var seat_node = scene.attach(seat^, pivot)
    scene.update()
    scene.look_at(seat_node, Vector3(0, 0, 0), camera=True)
    var camera = framed_camera(
        WIDTH,
        HEIGHT,
        field_of_view=Angle(45.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(100.0, METER),
    )
    camera.attach(seat_node)
    var stereo = StereoCamera(
        eye_separation=Length(0.3, METER), focus=Length(3.6, METER), aspect=0.5
    )

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        scene.node(pivot).rotate_y(step)
        scene.update()
        stereo.update(camera, scene)
        var eyes = ArrayCamera()
        eyes.add(stereo.left, LEFT)
        eyes.add(stereo.right, RIGHT)
        frames.append(renderer.render_array(scene, assets, eyes))

    write_example(frames, destination, DELAY_MS, FRAMES, frame_clock)
