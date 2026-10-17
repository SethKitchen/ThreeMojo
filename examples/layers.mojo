# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Sheen, a thin film and a stretched highlight, side by side.

    mojo run -I . examples/layers.mojo [path.png]

The page is Materials. The left sphere is cloth: a pink sheen on a dark
base. The middle sphere is a metal under a thin film, so its color shifts
with the angle. The right sphere is brushed metal, and its highlight is
long in one direction. The camera turns around them.
"""

from tools._example_output import (
    example_destination,
    fill_and_key,
    framed_camera,
    gallery_renderer,
    spin_clip,
)

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from materials.material import physical_material
from objects.mesh import Mesh
from render.framebuffer import Color
from units.si import DEGREE, METER, NANOMETER, Angle, Length

comptime DEFAULT_OUTPUT = "out/layers.png"
comptime WIDTH = 320
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(14, 16, 22))
    var assets = Assets()
    var ball = assets.geometries.add(sphere(Length(0.55, METER), 40, 28))
    var cloth = assets.materials.add(
        physical_material(
            Color(50, 12, 36),
            roughness=0.9,
            sheen=1.0,
            sheen_color=Color(255, 130, 190),
            sheen_roughness=0.35,
        )
    )
    var film = assets.materials.add(
        physical_material(
            Color(180, 180, 190),
            roughness=0.15,
            metalness=1.0,
            iridescence=1.0,
            iridescence_ior=1.3,
            iridescence_thickness_minimum=Length(100.0, NANOMETER),
            iridescence_thickness_maximum=Length(400.0, NANOMETER),
        )
    )
    var brush = assets.materials.add(
        physical_material(
            Color(212, 160, 64),
            roughness=0.28,
            metalness=1.0,
            anisotropy=0.85,
            anisotropy_rotation=Angle(90.0, DEGREE),
        )
    )

    var scene = Scene()
    var left = Object3D()
    left.set_position(-1.25, 0, 0)
    scene.add_mesh(Mesh(ball, cloth, scene.add(left^)))
    scene.add_mesh(Mesh(ball, film, scene.add(Object3D())))
    var right = Object3D()
    right.set_position(1.25, 0, 0)
    scene.add_mesh(Mesh(ball, brush, scene.add(right^)))

    fill_and_key(
        scene,
        1.4,
        1.6,
        2.2,
        Color(255, 255, 255),
        0.28,
        Color(255, 248, 236),
        2.8,
    )

    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0, 0.35, 4.2)
    var eye_node = scene.attach(eye^, pivot)
    var camera = framed_camera(
        WIDTH,
        HEIGHT,
        field_of_view=Angle(36.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(40.0, METER),
    )
    camera.attach(eye_node)

    spin_clip(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
