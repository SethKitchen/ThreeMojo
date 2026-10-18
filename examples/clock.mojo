# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cube turned by a Clock delta times an angular speed.

    mojo run -I . examples/clock.mojo [path.png]

The clock is fed synthetic nanoseconds so the loop is deterministic. The
turn is `Angle` from a `Duration` in seconds. A bare number does not
compile in either place.
"""

from examples.output import (
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
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from units.si import Angle, DEGREE, Length, METER, RADIAN, SECOND

comptime DEFAULT_OUTPUT = "out/units.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime FRAME_NS = 16_666_667
comptime RADIANS_PER_SECOND = Float32(2) * Float32(3.14159265) / (
    Float32(FRAMES) * Float32(FRAME_NS) / Float32(1_000_000_000)
)


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    mut clock: Clock,
    now: Int,
) raises -> Framebuffer:
    """Advance the clock to `now`, turn by the delta, and render.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry and materials.
        scene: The persistent scene, edited in place.
        node: The cube's node.
        clock: The stopwatch that yields the delta.
        now: The counter reading for this frame, in nanoseconds.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    var delta = clock.delta_at(now)
    scene.node(node).rotate_y(
        Angle(delta.to(SECOND) * RADIANS_PER_SECOND, RADIAN)
    )
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))

    var assets = Assets()
    var block = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(255, 140, 40)))

    var scene = Scene()
    var tilted = Object3D()
    tilted.set_euler(
        Angle(22.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var node = scene.add(tilted^)
    scene.add_mesh(Mesh(block, paint, node))

    fill_and_key(
        scene,
        0.45,
        0.8,
        0.55,
        Color(255, 255, 255),
        0.69,
        Color(255, 255, 255),
        2.51,
    )

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 0.35, 3.0),
        Vector3(0, 0, 0),
        field_of_view=Angle(45.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(100.0, METER),
    )

    var clock = Clock(auto_start=False)
    clock.start_at(0)
    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        frames.append(
            frame_at(
                renderer,
                camera,
                assets,
                scene,
                node,
                clock,
                (index + 1) * FRAME_NS,
            )
        )

    write_example(frames, destination, DELAY_MS, FRAMES, frame_clock)
