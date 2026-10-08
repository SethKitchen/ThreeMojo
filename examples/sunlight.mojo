# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A low sun walks around a cube and throws a long shadow.

    mojo run -I . examples/sunlight.mojo [path.png]

The page is Lighting addons. `SunLight` fits two cascades to the camera
on every frame. The sun stays low, so the shadow reaches across the
floor. It walks one whole circle.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.clock import Clock
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from lights.light import ambient_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from lights.sun_light import SunLight
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin
from std.pathlib import Path
from std.sys import argv, stderr
from units.si import DEGREE, METER, Angle, Length, MILLISECOND

comptime DEFAULT_OUTPUT = "out/lighting.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    mut sun: SunLight,
    turn: Float32,
) raises -> Framebuffer:
    """Move the sun, fit its cascades, and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera, placed above the floor.
        assets: The geometries and materials.
        scene: The persistent scene, edited in place.
        sun: The sun. Its cascades are already in `scene`.
        turn: The sun's angle around the cube, in radians.

    Returns:
        The rendered frame.

    Raises:
        Error: If the fit or the render is invalid.
    """
    scene.node(sun.node).set_position(cos(turn) * 2.8, 2.1, sin(turn) * 2.8)
    scene.update()
    sun.update(scene, camera)
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(18, 20, 28))
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP

    var assets = Assets()
    var block = assets.geometries.add(cube(Length(0.9, METER)))
    var ground = assets.geometries.add(
        plane(Length(5.0, METER), Length(5.0, METER))
    )
    var orange = assets.materials.add(Material(Color(230, 140, 50)))
    var gray = assets.materials.add(Material(Color(168, 172, 180)))

    var scene = Scene()
    var block_node = Object3D()
    block_node.set_position(0, 0.45, 0)
    scene.add_mesh(
        Mesh(
            block,
            orange,
            scene.add(block_node^),
            cast_shadow=True,
            receive_shadow=True,
        )
    )
    var floor = Object3D()
    floor.rotate_x(Angle(-90.0, DEGREE))
    scene.add_mesh(Mesh(ground, gray, scene.add(floor^), receive_shadow=True))

    var sun = SunLight(scene, Color(255, 214, 160), 2.2)
    sun.cast_shadow = True
    sun.shadow.map_size = 256
    sun.shadow.bias = -0.0005
    scene.add_light(ambient_light(Color(180, 188, 204), 0.16))
    scene.node(sun.node).set_position(2.8, 2.1, 0)

    var camera = PerspectiveCamera(
        Angle(38.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(16.0, METER),
    )
    camera.place(Vector3(2.5, 1.7, 2.9), Vector3(0, 0.2, 0))

    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var turn = Float32(2) * Float32(pi) * Float32(index) / Float32(FRAMES)
        frames.append(frame_at(renderer, camera, assets, scene, sun, turn))

    print(
        '{"frames_ms": ',
        frame_clock.elapsed().to(MILLISECOND),
        "}",
        sep="",
        file=stderr,
    )
    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
