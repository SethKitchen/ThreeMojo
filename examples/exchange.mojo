# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A tower read back from the IFC file it was written to.

    mojo run -I . examples/exchange.mojo [path.png]

The page is IFC exchange. `write_ifc` writes the tower as an IFC4 file
and `read_ifc` reads it back. The render view draws the model that came
back, cut away above its first storey.
"""

from examples.output import example_destination, build_and_spin, gallery_camera

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId
from core.scene import Scene
from math.vector3 import Vector3
from render.framebuffer import Color
from units.si import DEGREE, METER, Angle, Length
from extensions.building.fingerprint import fingerprint
from extensions.building.generate.tower import TowerOptions, generate_tower
from extensions.building.ifc.ifc4 import read_ifc, write_ifc
from extensions.building.views.render import FULL, RenderOptions, add_building
from generators.skyscraper import SkyscraperParameters
from units.si import Length64

comptime DEFAULT_OUTPUT = "out/ifc-exchange.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 70


def _build(mut scene: Scene, mut assets: Assets) raises -> NodeId:
    """Add a tower that went through an IFC file.

    Args:
        scene: The scene.
        assets: The asset store.

    Returns:
        The tower's node.

    Raises:
        Error: If the tower, the file or the render is not valid, or the
            model came back changed.
    """
    var parameters = SkyscraperParameters()
    parameters.seed = 12
    parameters.total_height = Length(8, METER)
    var tower = generate_tower(TowerOptions(parameters^))
    var back = read_ifc(
        write_ifc(tower, "2026-01-01T00:00:00"), Length64(1e-6, METER)
    )
    if fingerprint(back) != fingerprint(tower):
        raise Error("The tower came back changed")
    return add_building(scene, assets, back, RenderOptions(FULL, 0)).root


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
        Vector3(30, 26, 34),
        Vector3(0, 2, 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.5, METER),
        far=Length(300, METER),
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
