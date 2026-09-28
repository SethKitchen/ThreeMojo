# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Voronoi cells drift over a turning sphere.

    mojo run -I . examples/cells.mojo [path.png]

The page is TSL functions. `voronoi2d` reads the sphere's texture
coordinate and the frame's time. `remap_clamp` turns that distance into
a mix of two colors. The time walks one full period of the cells, and
the sphere turns one whole turn.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import STANDARD, Material
from materials.nodes import COLOR_NODE, NodeGraph, NodeProgramId
from materials.tsl_noise import voronoi2d
from materials.tsl_utils import remap_clamp
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import pi
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length

comptime DEFAULT_OUTPUT = "out/tslfunctions.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def _cells(mut assets: Assets) raises -> NodeProgramId:
    """Compile a voronoi color and store it.

    Args:
        assets: The store that receives the program.

    Returns:
        The stored program.

    Raises:
        Error: If a node has the wrong type.
    """
    var graph = NodeGraph()
    var cells = voronoi2d(
        graph,
        graph.mul(graph.uv(), graph.float(5)),
        graph.time(),
    )
    var shade = remap_clamp(graph, cells, graph.float(0), graph.float(0.16))
    var paper = graph.color(Color(244, 214, 170))
    var ink = graph.color(Color(28, 36, 72))
    graph.set_output(COLOR_NODE, graph.mix(paper, ink, shade))
    return assets.programs.add(graph.compile())


def frame_at(
    mut renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    ball: NodeId,
    step: Angle,
    seconds: Float32,
) raises -> Framebuffer:
    """Turn the sphere, set the graph's time, and render one frame.

    Args:
        renderer: The renderer to draw with. Its `time` is the graph's.
        camera: The camera, placed in front of the sphere.
        assets: The geometry and the node material.
        scene: The persistent scene, edited in place.
        ball: The node the sphere rides.
        step: How much further the sphere turns.
        seconds: The value of the `time` node, in seconds.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(ball).rotate_y(step)
    scene.update()
    renderer.time = Duration(seconds, SECOND)
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(14, 16, 22))
    var assets = Assets()
    var program = _cells(assets)
    var ball_shape = assets.geometries.add(sphere(Length(0.9, METER), 36, 24))
    var paint = assets.materials.add(
        Material(
            Color(255, 255, 255),
            kind=STANDARD,
            roughness=0.55,
            nodes=program,
        )
    )

    var scene = Scene()
    var ball = scene.add(Object3D())
    scene.add_mesh(Mesh(ball_shape, paint, ball))
    var lamp = Object3D()
    lamp.set_position(0.8, 1.5, 1.7)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.32))
    scene.add_light(
        directional_light(Color(255, 248, 236), scene.add(lamp^), 2.2)
    )

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.15, 0.2, 2.85), Vector3(0, 0, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var seconds = (
            Float32(2) * Float32(pi) * Float32(index) / Float32(FRAMES)
        )
        frames.append(
            frame_at(renderer, camera, assets, scene, ball, step, seconds)
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
