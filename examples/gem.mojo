# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A glass sphere refracts three colored boxes as the camera turns.

    mojo run -I . examples/gem.mojo [path.png]

The page is Materials. The sphere is a physical material with
transmission, thickness, attenuation and dispersion. The opaque boxes
are drawn first, and the sphere bends and tints that picture.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import Material, physical_material
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/transmission.png"
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
    """Turn the camera by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera riding a child of `pivot`.
        assets: The geometries and materials.
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
    var block = assets.geometries.add(cube(Length(0.7, METER)))
    var ball = assets.geometries.add(sphere(Length(0.62, METER), 32, 24))
    var red = assets.materials.add(Material(Color(210, 50, 40)))
    var green = assets.materials.add(Material(Color(40, 170, 70)))
    var blue = assets.materials.add(Material(Color(40, 90, 200)))
    var glass = assets.materials.add(
        physical_material(
            Color(255, 255, 255),
            roughness=0.04,
            ior=1.5,
            transmission=1.0,
            thickness=Length(0.7, METER),
            attenuation_color=Color(190, 220, 255),
            attenuation_distance=Length(1.4, METER),
            dispersion=1.5,
        )
    )

    var scene = Scene()
    var left = Object3D()
    left.set_position(-1.15, 0, -1.35)
    scene.add_mesh(Mesh(block, red, scene.add(left^)))
    var middle = Object3D()
    middle.set_position(0, 0, -1.35)
    scene.add_mesh(Mesh(block, green, scene.add(middle^)))
    var right = Object3D()
    right.set_position(1.15, 0, -1.35)
    scene.add_mesh(Mesh(block, blue, scene.add(right^)))
    scene.add_mesh(Mesh(ball, glass, scene.add(Object3D())))

    var lamp = Object3D()
    lamp.set_position(1.2, 1.6, 1.8)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.45))
    scene.add_light(directional_light(Color(255, 248, 236), lamp_node, 2.4))

    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0.2, 0.35, 3.3)
    var eye_node = scene.attach(eye^, pivot)
    var camera = PerspectiveCamera(
        Angle(38.0, DEGREE),
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
