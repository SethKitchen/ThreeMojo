# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A six-foot male femur turning under a lamp.

    mojo run -I . examples/femur.mojo [path.png]

The page is Femur. Length, thickness and the neck all come from stature
and sex. Nothing else is sized by hand.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.femur.geometry import femur
from lights.light import ambient_light, directional_light
from materials.material import phong_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, Length, METER

comptime DEFAULT_OUTPUT = "out/femur.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the femur by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry and materials.
        scene: The persistent scene, edited in place.
        node: The femur's node.
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
    renderer.set_background(Color(18, 16, 14))

    var assets = Assets()
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var bone = assets.geometries.add(femur(person, detail=20))
    var paint = assets.materials.add(
        phong_material(
            Color(232, 214, 180),
            specular=Color(90, 82, 70),
            shininess=18.0,
        )
    )

    var scene = Scene()
    var tilted = Object3D()
    tilted.set_euler(
        Angle(12.0, DEGREE), Angle(0.0, DEGREE), Angle(-18.0, DEGREE)
    )
    var node = scene.add(tilted^)
    scene.add_mesh(Mesh(bone, paint, node))

    var lamp = Object3D()
    lamp.set_position(0.35, 0.45, 0.7)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 248, 235), 0.48))
    scene.add_light(directional_light(Color(255, 244, 220), lamp_node, 2.4))

    var camera = PerspectiveCamera(
        Angle(32.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.28, 0.06, 1.05), Vector3(0.0, 0.02, 0.0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, node, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
