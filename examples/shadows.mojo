# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cube's shadow swings across a floor as the lamp orbits.

    mojo run -I . examples/shadows.mojo [path.png]

The page is Lights. The lamp casts, the cube casts and receives, and
the floor only receives. The map is a soft percentage-closer filter, so
the edge of the shadow is a band rather than a step.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from lights.light import ambient_light, directional_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/shadows.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    lamp: NodeId,
    turn: Float32,
) raises -> Framebuffer:
    """Move the lamp around the cube and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera, placed above the floor.
        assets: The geometries and materials.
        scene: The persistent scene, edited in place.
        lamp: The node the directional light shines from.
        turn: The lamp's angle around the cube, in radians.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(lamp).set_position(cos(turn) * 2.2, 2.6, sin(turn) * 2.2)
    scene.update()
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
        plane(Length(4.0, METER), Length(4.0, METER))
    )
    var orange = assets.materials.add(Material(Color(230, 140, 50)))
    var gray = assets.materials.add(Material(Color(150, 154, 164)))

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

    var lamp = Object3D()
    lamp.set_position(2.2, 2.6, 0)
    var lamp_node = scene.add(lamp^)
    var sun = directional_light(Color(255, 248, 236), lamp_node, 2.8)
    sun.cast_shadow = True
    sun.shadow.map_size = 256
    sun.shadow.bias = -0.001
    sun.shadow.normal_bias = 0.02
    sun.shadow.extent = Length(3.0, METER)
    sun.shadow.near = Length(0.2, METER)
    sun.shadow.far = Length(12.0, METER)
    scene.add_light(sun)
    scene.add_light(ambient_light(Color(180, 190, 210), 0.35))

    var camera = PerspectiveCamera(
        Angle(38.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(40.0, METER),
    )
    camera.place(Vector3(2.4, 1.8, 2.6), Vector3(0, 0.2, 0))

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var turn = Float32(2) * Float32(pi) * Float32(index) / Float32(FRAMES)
        frames.append(
            frame_at(renderer, camera, assets, scene, lamp_node, turn)
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
