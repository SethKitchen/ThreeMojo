# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bright spheres bloom over a dark knot as the camera turns.

    mojo run -I . examples/bloom.mojo [path.png]

The page is Post-processing. An `EffectComposer` draws the scene, lets
the light above a threshold bleed, darkens the corners, and applies the
renderer's tone curve once at the end.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.sphere import sphere
from geometries.torus import torus_knot
from lights.light import ambient_light, point_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.composer import (
    EffectComposer,
    bloom_pass,
    output_pass,
    render_pass,
    vignette_pass,
)
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/postprocessing.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def frame_at(
    mut composer: EffectComposer,
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    pivot: NodeId,
    step: Angle,
    delta: Float32,
) raises -> Framebuffer:
    """Turn the camera by `step` and run the passes on one frame.

    Args:
        composer: The passes, in order.
        renderer: What the render pass draws with.
        camera: The camera riding a child of `pivot`.
        assets: The geometry and materials.
        scene: The persistent scene, edited in place.
        pivot: The node the camera swings about.
        step: How much further round the camera goes this frame.
        delta: Seconds since the previous frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or a pass is invalid.
    """
    scene.node(pivot).rotate_y(step)
    scene.update()
    return composer.render(renderer, scene, assets, camera, delta)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(8, 9, 14))
    renderer.set_tone_mapping(ACES_FILMIC_TONE_MAPPING, 1.1)

    var assets = Assets()
    var knot = assets.geometries.add(
        torus_knot(Length(0.55, METER), Length(0.16, METER), 64, 8)
    )
    var ball = assets.geometries.add(sphere(Length(0.22, METER), 24, 16))
    var dark = assets.materials.add(Material(Color(120, 128, 150)))
    var gold = assets.materials.add(
        Material(
            Color(80, 56, 16),
            emissive=Color(255, 196, 64),
            emissive_intensity=2.2,
        )
    )
    var cyan = assets.materials.add(
        Material(
            Color(16, 48, 56),
            emissive=Color(80, 220, 255),
            emissive_intensity=2.2,
        )
    )

    var scene = Scene()
    var knot_node = scene.add(Object3D())
    scene.add_mesh(Mesh(knot, dark, knot_node))
    var left = Object3D()
    left.set_position(-0.85, 0.35, 0.2)
    scene.add_mesh(Mesh(ball, gold, scene.add(left^)))
    var right = Object3D()
    right.set_position(0.9, -0.15, -0.15)
    scene.add_mesh(Mesh(ball, cyan, scene.add(right^)))

    var bulb = Object3D()
    bulb.set_position(0.2, 1.2, 1.4)
    var bulb_node = scene.add(bulb^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.16))
    scene.add_light(point_light(Color(255, 244, 230), bulb_node, 2.0))

    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(bloom_pass(0.7, 0.35, 0.85))
    composer.add_pass(vignette_pass(0.45, 0.7))
    composer.add_pass(output_pass())

    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0, 0.35, 3.4)
    var eye_node = scene.attach(eye^, pivot)
    var camera = PerspectiveCamera(
        Angle(38.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(40.0, METER),
    )
    camera.attach(eye_node)

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var delta = Float32(1) / Float32(FRAMES)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(
            frame_at(
                composer, renderer, camera, assets, scene, pivot, step, delta
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
