# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One box, six materials, one on each face.

    mojo run -I . examples/faces.mojo [path.png]

The page is Meshes and assets. The box geometry has a group for each
face. The mesh wears a list, and each group draws with the material its
index names. The box turns so every face comes around.
"""

from tools._example_output import (
    example_destination,
    fill_and_key,
    gallery_camera,
    gallery_renderer,
    write_example,
)

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.clock import Clock
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from materials.material import Material, MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/faces.png"
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
    """Turn the box by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera, placed in front of the box.
        assets: The geometry and the six materials.
        scene: The persistent scene, edited in place.
        node: The node the box rides.
        step: How much further the box turns this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(node).rotate_y(step)
    scene.node(node).rotate_x(Angle(step.to(DEGREE) * 0.35, DEGREE))
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))
    var assets = Assets()
    var block = assets.geometries.add(cube(Length(1.1, METER)))
    var colors = List[Color]()
    colors.append(Color(210, 50, 40))
    colors.append(Color(40, 90, 200))
    colors.append(Color(40, 170, 70))
    colors.append(Color(230, 170, 40))
    colors.append(Color(150, 70, 190))
    colors.append(Color(230, 230, 235))
    var faces = List[MaterialId]()
    for index in range(6):
        faces.append(assets.materials.add(Material(colors[index])))

    var scene = Scene()
    var posed = Object3D()
    posed.rotate_y(Angle(32.0, DEGREE))
    posed.rotate_x(Angle(22.0, DEGREE))
    var node = scene.add(posed^)
    scene.add_mesh(Mesh(block, faces^, node))
    fill_and_key(
        scene,
        1.2,
        1.6,
        1.8,
        Color(255, 255, 255),
        0.4,
        Color(255, 255, 255),
        2.4,
    )

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0.6, 0.7, 3.1),
        Vector3(0, 0, 0),
        field_of_view=Angle(38.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(20.0, METER),
    )

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, node, step))

    write_example(frames, destination, DELAY_MS, FRAMES, frame_clock)
