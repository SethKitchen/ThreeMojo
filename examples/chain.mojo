# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A chain of parented cubes waving, each an earlier index in the array.

    mojo run -I . examples/chain.mojo [path.png]

The scene graph is a flat array. A parent is always an earlier node. This
file is five children in a row, so turning the first carries the rest.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/chain.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime LINKS = 5


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    links: List[NodeId],
    phase: Float32,
) raises -> Framebuffer:
    """Wave each joint and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry and materials.
        scene: The persistent scene, edited in place.
        links: The chain, root first.
        phase: How far the wave has run, in radians.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    for index in range(len(links)):
        var bend = Angle(
            18.0 * cos(phase + Float32(0.7) * Float32(index)), DEGREE
        )
        scene.node(links[index]).set_euler(
            Angle(0.0, DEGREE), Angle(0.0, DEGREE), bend
        )
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
    var block = assets.geometries.add(cube(Length(0.42, METER)))
    var paint = assets.materials.add(Material(Color(255, 150, 70)))

    var scene = Scene()
    var root = Object3D()
    root.set_position(-1.1, 0, 0)
    var prev = scene.add(root^)
    var links = List[NodeId]()
    links.append(prev)
    scene.add_mesh(Mesh(block, paint, prev))
    for _ in range(LINKS - 1):
        var child = Object3D()
        child.set_position(0.46, 0, 0)
        prev = scene.attach(child^, prev)
        links.append(prev)
        scene.add_mesh(Mesh(block, paint, prev))

    var lamp = Object3D()
    lamp.set_position(0.3, 0.9, 0.7)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.69))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.51))

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.35, 3.6), Vector3(0, 0, 0))

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var phase = Float32(2) * Float32(pi) * Float32(index) / Float32(FRAMES)
        frames.append(frame_at(renderer, camera, assets, scene, links, phase))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
