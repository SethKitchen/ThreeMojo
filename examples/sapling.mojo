# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A procedural tree turns under a lamp.

    mojo run -I . examples/sapling.mojo [path.png]

The page is Procedural generators. `TreeGenerator` grows one mesh from
a seed. The trunk is shorter than the default, so the crown fits the
frame. The tree turns one whole turn.
"""

from tools._example_output import (
    example_destination,
    fill_and_key,
    gallery_camera,
    gallery_renderer,
    spin_clip,
)

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from generators.tree import TreeGenerator, TreeParameters
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/generators.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def _tree() raises -> TreeGenerator:
    """Return a generator for a short tree.

    Returns:
        The generator. `build` grows the mesh.

    Raises:
        Error: If `check` refuses a parameter.
    """
    var parameters = TreeParameters()
    parameters.levels = 3
    parameters.trunk_length = Length(1.7, METER)
    parameters.trunk_radius = Length(0.08, METER)
    parameters.section_length = Length(0.26, METER)
    parameters.radial_segments = 5
    parameters.min_length = Length(0.22, METER)
    parameters.children[0] = 3
    parameters.children[1] = 6
    parameters.children[2] = 4
    parameters.check()
    return TreeGenerator(parameters^)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))

    var assets = Assets()
    var generator = _tree()
    var shape = assets.geometries.add(generator.build())
    var leaves = assets.materials.add(Material(Color(72, 118, 52)))

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(shape, leaves, node))
    fill_and_key(
        scene,
        1.6,
        2.8,
        1.4,
        Color(214, 220, 208),
        0.38,
        Color(255, 246, 230),
        1.8,
    )

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(2.75, 1.7, 4.15),
        Vector3(0, 1.32, 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(30.0, METER),
    )

    spin_clip(
        renderer, camera, assets, scene, node, FRAMES, DELAY_MS, destination
    )
