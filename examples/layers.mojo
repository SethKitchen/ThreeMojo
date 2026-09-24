# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Sheen, a thin film and a stretched highlight, side by side.

    mojo run -I . examples/layers.mojo [path.png]

The page is Materials. The left sphere is cloth: a pink sheen on a dark
base. The middle sphere is a metal under a thin film, so its color shifts
with the angle. The right sphere is brushed metal, and its highlight is
long in one direction. The camera turns around them.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import physical_material
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, NANOMETER, Angle, Length

comptime DEFAULT_OUTPUT = "out/layers.png"
comptime WIDTH = 320
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
    """Turn the camera by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera riding a child of `pivot`.
        assets: The geometry and the three materials.
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
    renderer.set_background(Color(14, 16, 22))
    var assets = Assets()
    var ball = assets.geometries.add(sphere(Length(0.55, METER), 40, 28))
    var cloth = assets.materials.add(
        physical_material(
            Color(50, 12, 36),
            roughness=0.9,
            sheen=1.0,
            sheen_color=Color(255, 130, 190),
            sheen_roughness=0.35,
        )
    )
    var film = assets.materials.add(
        physical_material(
            Color(180, 180, 190),
            roughness=0.15,
            metalness=1.0,
            iridescence=1.0,
            iridescence_ior=1.3,
            iridescence_thickness_minimum=Length(100.0, NANOMETER),
            iridescence_thickness_maximum=Length(400.0, NANOMETER),
        )
    )
    var brush = assets.materials.add(
        physical_material(
            Color(212, 160, 64),
            roughness=0.28,
            metalness=1.0,
            anisotropy=0.85,
            anisotropy_rotation=Angle(90.0, DEGREE),
        )
    )

    var scene = Scene()
    var left = Object3D()
    left.set_position(-1.25, 0, 0)
    scene.add_mesh(Mesh(ball, cloth, scene.add(left^)))
    scene.add_mesh(Mesh(ball, film, scene.add(Object3D())))
    var right = Object3D()
    right.set_position(1.25, 0, 0)
    scene.add_mesh(Mesh(ball, brush, scene.add(right^)))

    var lamp = Object3D()
    lamp.set_position(1.4, 1.6, 2.2)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.28))
    scene.add_light(directional_light(Color(255, 248, 236), lamp_node, 2.8))

    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0, 0.35, 4.2)
    var eye_node = scene.attach(eye^, pivot)
    var camera = PerspectiveCamera(
        Angle(36.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(40.0, METER),
    )
    camera.attach(eye_node)

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, pivot, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
