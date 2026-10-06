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
    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(1, METER),
        Length(500, METER),
    )
    camera.place(Vector3(75, 48, 80), Vector3(0, 26, 0))
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
