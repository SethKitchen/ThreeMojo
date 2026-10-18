# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bright sphere through ACES tone mapping as the exposure breathes.

    mojo run -I . examples/exposure.mojo [path.png]

Tone mapping runs once on the composited light of each pixel, after
shading and fog. The curve stays put. Only the exposure changes.
"""

from examples.output import (
    example_destination,
    fill_and_key,
    gallery_camera,
    gallery_renderer,
    write_example,
)

from core.assets import Assets
from core.clock import Clock
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from materials.material import phong_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from std.math import cos, pi
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/exposure.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(8, 9, 12))

    var assets = Assets()
    var ball = assets.geometries.add(sphere(Length(1.0, METER), 28, 18))
    var paint = assets.materials.add(
        phong_material(
            Color(255, 210, 160),
            specular=Color(255, 255, 255),
            shininess=24.0,
        )
    )

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(ball, paint, node))

    fill_and_key(
        scene,
        0.4,
        0.6,
        1.0,
        Color(255, 255, 255),
        0.25,
        Color(255, 240, 210),
        7.54,
    )
    scene.update()

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 0.15, 3.1),
        Vector3(0, 0, 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(100.0, METER),
    )

    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var turn = Float32(2) * Float32(pi) * Float32(index) / Float32(FRAMES)
        var exposure = Float32(0.25) + Float32(1.6) * (
            Float32(0.5) - Float32(0.5) * cos(turn)
        )
        renderer.set_tone_mapping(ACES_FILMIC_TONE_MAPPING, exposure)
        frames.append(renderer.render(scene, assets, camera))

    write_example(frames, destination, DELAY_MS, FRAMES, frame_clock)
