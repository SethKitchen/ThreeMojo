# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A furnished floor of homes, cut away above its ceiling.

    mojo run -I . examples/interiors.mojo [path.png]

The page is Floor plans and interiors. The tower's shaft holds homes. The
render view draws the storeys up to the first shaft storey, so the plan,
the doors and the furniture show.
"""

from examples.output import example_destination, spin_daylight

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId
from core.scene import Scene
from math.vector3 import Vector3
from render.framebuffer import Color
from units.si import DEGREE, METER, Angle, Length
from extensions.building.generate.plan import RESIDENTIAL_FLOOR
from extensions.building.generate.tower import TowerOptions, generate_tower
from extensions.building.views.render import FULL, RenderOptions, add_building
from generators.skyscraper import SkyscraperParameters

comptime DEFAULT_OUTPUT = "out/floor-plans-and-interiors.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 70


def _build(mut scene: Scene, mut assets: Assets) raises -> NodeId:
    """Add a small tower of homes, cut away above its second storey.

    Args:
        scene: The scene.
        assets: The asset store.

    Returns:
        The tower's node.

    Raises:
        Error: If the tower or the render is not valid.
    """
    var parameters = SkyscraperParameters()
    parameters.total_height = Length(12, METER)
    var options = TowerOptions(parameters^)
    options.shaft = RESIDENTIAL_FLOOR
    options.frame = False
    var tower = generate_tower(options)
    return add_building(scene, assets, tower, RenderOptions(FULL, 1)).root


def _camera() raises -> PerspectiveCamera:
    """Return the camera, placed to frame the scene.

    Returns:
        The camera.

    Raises:
        Error: If the camera's settings are not valid.
    """
    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.5, METER),
        Length(300, METER),
    )
    camera.place(Vector3(17, 21, 19), Vector3(0, 3, 0))
    return camera^


def main() raises:
    var assets = Assets()
    var scene = Scene()
    var root = _build(scene, assets)
    spin_daylight(
        WIDTH,
        HEIGHT,
        Color(150, 182, 214),
        0.5,
        1.6,
        scene,
        assets,
        root,
        _camera(),
        FRAMES,
        DELAY_MS,
        example_destination(String(DEFAULT_OUTPUT)),
    )
