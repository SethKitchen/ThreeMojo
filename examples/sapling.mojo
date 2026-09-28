# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A procedural tree turns under a lamp.

    mojo run -I . examples/sapling.mojo [path.png]

The page is Procedural generators. `TreeGenerator` grows one mesh from
a seed. The trunk is shorter than the default, so the crown fits the
frame. The tree turns one whole turn.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from generators.tree import TreeGenerator, TreeParameters
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/generators.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def _tree() raises -> TreeGenerator:
    """Return a generator for a short tree.

    Returns:
        The generator. `build` grows the mesh.

    Raises:
        Error: If `check` refuses a parameter.
    """
    var parameters = TreeParameters()
    parameters.levels = 3
    parameters.trunk_length = Length(1.7, METER)
    parameters.trunk_radius = Length(0.08, METER)
    parameters.section_length = Length(0.26, METER)
    parameters.radial_segments = 5
    parameters.min_length = Length(0.22, METER)
    parameters.children[0] = 3
    parameters.children[1] = 6
    parameters.children[2] = 4
    parameters.check()
    return TreeGenerator(parameters^)


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the tree by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera, placed in front of the tree.
        assets: The geometry and the material.
        scene: The persistent scene, edited in place.
        node: The node the tree rides.
        step: How much further the tree turns.

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

    var assets = Assets()
    var generator = _tree()
    var shape = assets.geometries.add(generator.build())
    var leaves = assets.materials.add(Material(Color(72, 118, 52)))

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(shape, leaves, node))
    var lamp = Object3D()
    lamp.set_position(1.6, 2.8, 1.4)
    scene.add_light(ambient_light(Color(214, 220, 208), 0.38))
    scene.add_light(
        directional_light(Color(255, 246, 230), scene.add(lamp^), 1.8)
    )

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(30.0, METER),
    )
    camera.place(Vector3(2.75, 1.7, 4.15), Vector3(0, 1.32, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, node, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
