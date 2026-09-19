# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A ray through the image center, marked where it hits a sphere.

    mojo run -I . examples/raycast.mojo [path.png]

The camera rides a pivot. Each frame the center pixel is picked again.
The marker is a small cube placed at `Hit.point`. That is what
`Raycaster.set_from_pixel` is for.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.raycaster import Raycaster
from core.scene import Scene
from geometries.box import cube
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/raycast.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    pivot: NodeId,
    marker: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Swing the camera, place the marker on the hit, and render.

    Args:
        renderer: The renderer to draw with.
        camera: The camera the ray is aimed through, riding `pivot`.
        assets: The geometry and materials.
        scene: The persistent scene, edited in place.
        pivot: The node the camera swings about.
        marker: The small cube that sits on the hit.
        step: How much further the camera goes this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene, the pick or the render is invalid.
    """
    scene.node(pivot).rotate_y(step)
    scene.update()
    var caster = Raycaster(Vector3(0, 0, 0), Vector3(0, 0, -1))
    caster.set_from_pixel(
        Float32(WIDTH) / 2,
        Float32(HEIGHT) / 2,
        WIDTH,
        HEIGHT,
        camera,
        scene,
    )
    var hits = caster.intersect_mesh(scene, assets, 0)
    if len(hits) > 0:
        var at = hits[0].point
        scene.node(marker).set_position(at.x, at.y, at.z)
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
    var ball = assets.geometries.add(sphere(Length(1.0, METER), 24, 16))
    var tip = assets.geometries.add(cube(Length(0.16, METER)))
    var white = assets.materials.add(Material(Color(220, 225, 235)))
    var mark = assets.materials.add(Material(Color(255, 70, 70)))

    var scene = Scene()
    var ball_node = scene.add(Object3D())
    scene.add_mesh(Mesh(ball, white, ball_node))
    var marker = scene.add(Object3D())
    scene.add_mesh(Mesh(tip, mark, marker))

    var lamp = Object3D()
    lamp.set_position(0.5, 0.9, 0.7)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.79))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.51))

    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0, 0.25, 3.2)
    var eye_node = scene.attach(eye^, pivot)
    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.attach(eye_node)

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(
            frame_at(renderer, camera, assets, scene, pivot, marker, step)
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
