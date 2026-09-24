# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sphere whose color and size come from a node graph.

    mojo run -I . examples/graph.mojo [path.png]

The page is Node materials. A `COLOR_NODE` mixes orange and blue with
the sine of `Renderer.time`. A `POSITION_NODE` pushes each vertex along
its normal by the same wave. The lights still shade the sphere.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import STANDARD, Material
from materials.nodes import COLOR_NODE, POSITION_NODE, NodeGraph
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import pi
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length

comptime DEFAULT_OUTPUT = "out/nodes.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def frame_at(
    mut renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    step: Angle,
    seconds: Float32,
) raises -> Framebuffer:
    """Turn the sphere, set the graph's time, and render one frame.

    Args:
        renderer: The renderer to draw with. Its `time` is the graph's.
        camera: The camera, placed in front of the sphere.
        assets: The geometry and the node material.
        scene: The persistent scene, edited in place.
        node: The node the sphere rides.
        step: How much further the sphere turns this frame.
        seconds: The value of the `time` node, in seconds.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(node).rotate_y(step)
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
    var graph = NodeGraph()
    var warm = graph.color(Color(255, 140, 40))
    var cool = graph.color(Color(40, 110, 230))
    var wave = graph.mul(
        graph.add(graph.sin(graph.time()), graph.float(1.0)),
        graph.float(0.5),
    )
    graph.set_output(COLOR_NODE, graph.mix(warm, cool, wave))
    var nudge = graph.mul(
        graph.normal_local(),
        graph.mul(graph.sin(graph.time()), graph.float(0.08)),
    )
    graph.set_output(POSITION_NODE, nudge)
    var program = assets.programs.add(graph.compile())
    var ball = assets.geometries.add(sphere(Length(0.9, METER), 36, 24))
    var paint = assets.materials.add(
        Material(
            Color(255, 255, 255),
            kind=STANDARD,
            roughness=0.45,
            nodes=program,
        )
    )

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(ball, paint, node))
    var lamp = Object3D()
    lamp.set_position(0.8, 1.3, 1.6)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.35))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.4))

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.2, 0.25, 3.0), Vector3(0, 0, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var seconds = (
            Float32(2) * Float32(pi) * Float32(index) / Float32(FRAMES)
        )
        frames.append(
            frame_at(renderer, camera, assets, scene, node, step, seconds)
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
