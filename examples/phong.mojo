# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A Phong highlight that follows the camera around a red sphere.

    mojo run -I . examples/phong.mojo [path.png]

The highlight is tinted by the specular color, not by the base color. A
red plastic ball has a white spot on it. The camera rides a pivot, so the
spot moves and the lit face stays lit.
"""

from examples.output import (
    example_destination,
    fill_and_key,
    gallery_renderer,
    spin_clip,
)

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from materials.material import phong_material
from objects.mesh import Mesh
from render.framebuffer import Color
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/phong.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(12, 13, 18))

    var assets = Assets()
    var ball = assets.geometries.add(sphere(Length(1.0, METER), 32, 20))
    var paint = assets.materials.add(
        phong_material(
            Color(200, 40, 40),
            specular=Color(255, 255, 255),
            shininess=48.0,
        )
    )

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(ball, paint, node))

    fill_and_key(
        scene,
        0.6,
        0.7,
        1.2,
        Color(255, 255, 255),
        0.38,
        Color(255, 255, 255),
        3.14,
    )

    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0, 0.25, 3.1)
    var eye_node = scene.attach(eye^, pivot)
    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.attach(eye_node)

    spin_clip(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
