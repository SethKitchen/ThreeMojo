# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An LDraw model of bricks turns under a lamp.

    mojo run -I . examples/bricks.mojo [path.png]

The page is More model files. `read_ldraw` builds `assets/ldraw/scene.mpd`
from the parts library beside it, and `load_ldraw` puts that model in the
scene. The root turns one whole turn.
"""

from examples.output import example_destination, gallery_camera, spin_clip

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from lights.light import ambient_light, directional_light
from loaders.ldraw import load_ldraw, read_ldraw
from loaders.ldraw_parse import LDrawLoader
from math.vector3 import Vector3
from render.framebuffer import Color
from renderers.renderer import Renderer, available_workers
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/models.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime LIBRARY = "assets/ldraw/library/"


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))

    var model = read_ldraw("assets/ldraw/scene.mpd", LDrawLoader(LIBRARY))
    var assets = Assets()
    var scene = Scene()
    load_ldraw(model, scene, assets)
    var root = model.scene_nodes[model.root]

    var lamp = Object3D()
    lamp.set_position(12, -16, 10)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.55))
    scene.add_light(
        directional_light(Color(255, 248, 236), scene.add(lamp^), 2.4)
    )

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(8, -7, 11),
        Vector3(0, 1.5, 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(200.0, METER),
    )

    spin_clip(
        renderer, camera, assets, scene, root, FRAMES, DELAY_MS, destination
    )
