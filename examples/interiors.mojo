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

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from lights.light import ambient_light, directional_light
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
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


def _light(mut scene: Scene) raises:
    """Add a sky fill and a sun.

    Args:
        scene: The scene to light.

    Raises:
        Error: If the scene refuses a node.
    """
    scene.add_light(ambient_light(Color(214, 222, 232), 0.5))
    var sun = Object3D()
    sun.set_position(30, 60, 40)
    scene.add_light(
        directional_light(Color(255, 246, 230), scene.add(sun^), 1.6)
    )


def _write(frames: List[Framebuffer]) raises:
    """Write the frames as an animated PNG.

    Args:
        frames: The frames.

    Raises:
        Error: If the file cannot be written.
    """
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])
    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", len(frames), "frames")


def main() raises:
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(150, 182, 214))
    var assets = Assets()
    var scene = Scene()
    var root = _build(scene, assets)
    _light(scene)
    var camera = _camera()
    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        scene.node(root).rotate_y(step)
        scene.update()
        frames.append(renderer.render(scene, assets, camera))
    _write(frames)
