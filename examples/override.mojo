# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An override material paints every sphere but one.

    mojo run -I . examples/override.mojo [path.png]

The page is Renderer hooks and material flags. The scene's override is a
normal material, so two spheres show which way they face. The middle
sphere sets `allow_override` off and keeps its own color. The camera
rides a pivot one whole turn, and the normals shift with it.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import Material, normal_material
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/hooks.png"
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
    step: Angle,
) raises -> Framebuffer:
    """Swing the camera on by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera riding a child of `pivot`.
        assets: The geometry and materials.
        scene: The persistent scene, edited in place.
        pivot: The node the camera swings about.
        step: How much further round the camera goes this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(pivot).rotate_y(step)
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
    var ball = assets.geometries.add(sphere(Length(0.42, METER), 24, 16))
    var kept_paint = Material(Color(232, 120, 64))
    kept_paint.allow_override = False
    var kept = assets.materials.add(kept_paint^)
    var other = assets.materials.add(Material(Color(70, 140, 210)))
    var normals = assets.materials.add(normal_material())

    var scene = Scene()
    scene.override_material = normals
    var places = List[Float32]()
    places.append(-1.05)
    places.append(0)
    places.append(1.05)
    for index in range(3):
        var node = Object3D()
        node.set_position(places[index], 0, 0)
        var material = other
        if index == 1:
            material = kept
        scene.add_mesh(Mesh(ball, material, scene.add(node^)))

    var lamp = Object3D()
    lamp.set_position(2.2, 3.4, 2.6)
    scene.add_light(ambient_light(Color(210, 214, 224), 0.45))
    scene.add_light(
        directional_light(Color(255, 248, 236), scene.add(lamp^), 1.4)
    )

    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0, 0.35, 3.15)
    var camera_node = scene.attach(eye^, pivot)
    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(30.0, METER),
    )
    camera.attach(camera_node)

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, pivot, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
