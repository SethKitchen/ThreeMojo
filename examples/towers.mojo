# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A seeded tower with a set-back crown turns under a lamp.

    mojo run -I . examples/towers.mojo [path.png]

The page is Procedural towers. `generate_tower` writes a whole building
model from the skyscraper's seed: storeys, rooms, doors, windows, a frame
and furniture. The render view draws its outside.
"""

from tools._example_output import (
    example_destination,
    build_and_spin,
    gallery_camera,
)

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId
from core.scene import Scene
from math.vector3 import Vector3
from render.framebuffer import Color
from units.si import DEGREE, METER, Angle, Length
from extensions.building.generate.tower import TowerOptions, generate_tower
from extensions.building.views.render import (
    MASSING,
    RenderOptions,
    add_building,
)
from generators.skyscraper import SkyscraperParameters

comptime DEFAULT_OUTPUT = "out/procedural-towers.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 70


def _build(mut scene: Scene, mut assets: Assets) raises -> NodeId:
    """Add a 60 m tower.

    Args:
        scene: The scene.
        assets: The asset store.

    Returns:
        The tower's node.

    Raises:
        Error: If the tower or the render is not valid.
    """
    var parameters = SkyscraperParameters()
    parameters.total_height = Length(60, METER)
    var options = TowerOptions(parameters^)
    options.furnished = False
    var tower = generate_tower(options)
    return add_building(scene, assets, tower, RenderOptions(MASSING, -1)).root


def _camera() raises -> PerspectiveCamera:
    """Return the camera, placed to frame the scene.

    Returns:
        The camera.

    Raises:
        Error: If the camera's settings are not valid.
    """
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(75, 48, 80),
        Vector3(0, 26, 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(1, METER),
        far=Length(500, METER),
    )
    return camera^


def main() raises:
    build_and_spin[_build, _camera](
        WIDTH,
        HEIGHT,
        Color(150, 182, 214),
        0.5,
        1.6,
        FRAMES,
        DELAY_MS,
        example_destination(String(DEFAULT_OUTPUT)),
    )
