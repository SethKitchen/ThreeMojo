# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two metaballs join into one surface.

    mojo run -I . examples/blobs.mojo [path.png]

The page is Scene objects. `MarchingCubes` fills a cube of cells from
two balls, then builds the surface where the field crosses isolation.
Each ball paints its own color onto the vertices. The surface turns.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.marching_cubes import MarchingCubes
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, FloatColor, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/blobs.png"
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
    """Turn the surface by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera, placed in front of the surface.
        assets: The geometry and the material.
        scene: The persistent scene, edited in place.
        node: The node the surface rides.
        step: How much further the surface turns this frame.

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
    var field = MarchingCubes(16, enable_colors=True)
    field.reset()
    field.add_ball(0.42, 0.52, 0.5, 0.85, 10, FloatColor(1, 0.35, 0.12, 1))
    field.add_ball(0.58, 0.5, 0.48, 0.75, 10, FloatColor(0.2, 0.45, 1, 1))
    field.update()

    var assets = Assets()
    var surface = assets.geometries.add(field.geometry())
    var paint = assets.materials.add(
        Material(Color(255, 255, 255), vertex_colors=True)
    )

    var scene = Scene()
    var stand = Object3D()
    stand.set_scale(1.45, 1.45, 1.45)
    var node = scene.add(stand^)
    scene.add_mesh(Mesh(surface, paint, node))
    var lamp = Object3D()
    lamp.set_position(1.2, 1.6, 1.4)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.4))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.4))

    var camera = PerspectiveCamera(
        Angle(38.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.9, 0.55, 2.4), Vector3(0, 0, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, node, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
