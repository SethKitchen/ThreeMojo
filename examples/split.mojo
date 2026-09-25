# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A split screen: a circling camera on the left, a plan view on the right.

    mojo run -I . examples/split.mojo [path.png]

The page is Renderer. Two viewports and two scissors draw into one
target. Each half is cleared to its own background and drawn by its own
camera, and neither touches the other. The target is resolved once.
"""

from cameras.orthographic_camera import OrthographicCamera, centered
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.torus import torus
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.rect import Rect
from render.target import RenderTarget
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/split.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime LEFT = Rect(0, 0, WIDTH // 2, HEIGHT)
comptime RIGHT = Rect(WIDTH // 2, 0, WIDTH // 2, HEIGHT)


def frame_at(
    mut renderer: Renderer,
    camera: PerspectiveCamera,
    plan: OrthographicCamera,
    assets: Assets,
    mut scene: Scene,
    pivot: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the circling camera by `step` and render both halves.

    Args:
        renderer: The renderer to draw with; its viewport and scissor
            are set to each half in turn.
        camera: The camera circling the scene, riding a child of the pivot.
        plan: The camera looking straight down.
        assets: The geometries and materials.
        scene: The persistent scene, edited in place.
        pivot: The node the circling camera swings around.
        step: How much further to turn this frame.

    Returns:
        The one image both halves were drawn into.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(pivot).rotate_y(step)
    scene.update()
    var target = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0))
    renderer.set_background(Color(16, 18, 26))
    renderer.set_viewport(LEFT)
    renderer.set_scissor(LEFT)
    renderer.render_into(target, scene, assets, camera)
    renderer.set_background(Color(28, 22, 18))
    renderer.set_viewport(RIGHT)
    renderer.set_scissor(RIGHT)
    renderer.render_into(target, scene, assets, plan)
    return target.resolve(
        renderer.workers,
        renderer.tone_curve(),
        renderer.tone_mapping_exposure,
        output=renderer.output_encoding(),
    )


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_scissor_test(True)
    var assets = Assets()
    var scene = Scene()

    var block = assets.geometries.add(cube(Length(0.8, METER)))
    var ring = assets.geometries.add(
        torus(Length(0.9, METER), Length(0.18, METER), 10, 24)
    )
    var blue = assets.materials.add(Material(Color(70, 110, 200)))
    var gold = assets.materials.add(Material(Color(230, 180, 60)))
    var stand = Object3D()
    stand.set_position(0.6, 0, -0.4)
    stand.rotate_y(Angle(25.0, DEGREE))
    var block_node = scene.add(stand^)
    scene.add_mesh(Mesh(block, blue, block_node))
    var lying = Object3D()
    lying.set_position(-0.7, -0.3, 0.5)
    lying.rotate_x(Angle(90.0, DEGREE))
    var ring_node = scene.add(lying^)
    scene.add_mesh(Mesh(ring, gold, ring_node))

    var lamp = Object3D()
    lamp.set_position(0.5, 0.9, 0.8)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.79))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.51))

    # The circling camera rides a seat on a pivot, and sees its half at
    # the half's own aspect.
    var pivot = scene.add(Object3D())
    var seat = Object3D()
    seat.set_position(0, 1.4, 3.6)
    var seat_node = scene.attach(seat^, pivot)
    scene.update()
    scene.look_at(seat_node, Vector3(0, 0, 0), camera=True)
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH // 2) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.attach(seat_node)
    # The plan view looks straight down, and does not move.
    var plan = centered(
        Length(4.0, METER),
        Float32(WIDTH // 2) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    plan.place(Vector3(0, 6, 0.001), Vector3(0, 0, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(
            frame_at(renderer, camera, plan, assets, scene, pivot, step)
        )
    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
