# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An override material paints every sphere but one.

    mojo run -I . examples/override.mojo [path.png]

The page is Renderer hooks and material flags. The scene's override is a
normal material, so two spheres show which way they face. The middle
sphere sets `allow_override` off and keeps its own color. The camera
rides a pivot one whole turn, and the normals shift with it.
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
from materials.material import Material, normal_material
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/hooks.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))

    var assets = Assets()
    var ball = assets.geometries.add(sphere(Length(0.42, METER), 24, 16))
    var kept_paint = Material(Color(232, 120, 64))
    kept_paint.allow_override = False
    var kept = assets.materials.add(kept_paint^)
    var other = assets.materials.add(Material(Color(70, 140, 210)))
    var normals = assets.materials.add(normal_material())

    var scene = Scene()
    scene.override_material = normals
    var places = List[Float32]()
    places.append(-1.05)
    places.append(0)
    places.append(1.05)
    for index in range(3):
        var node = Object3D()
        node.set_position(places[index], 0, 0)
        var material = other
        if index == 1:
            material = kept
        scene.add_mesh(Mesh(ball, material, scene.add(node^)))

    fill_and_key(
        scene,
        2.2,
        3.4,
        2.6,
        Color(210, 214, 224),
        0.45,
        Color(255, 248, 236),
        1.4,
    )

    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0, 0.35, 3.15)
    var camera_node = scene.attach(eye^, pivot)
    var camera = framed_camera(
        WIDTH,
        HEIGHT,
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(30.0, METER),
    )
    camera.attach(camera_node)

    spin_clip(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
