# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A generated tower's frame swaying in its first natural mode.

    mojo run -I . examples/frame_modes.mojo [path.png]

The page is Frame analysis. The structural view turns the tower's columns
and beams into a frame. `solve_modes` finds its lowest mode. The frame is
drawn displaced by that mode shape, scaled up so the sway shows, through
one cycle.
"""

from examples.output import (
    example_destination,
    gallery_camera,
    gallery_renderer,
    write_frames,
)
from examples.preview import Triangles, add_sky_and_sun, heat_color

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from generators.utils import Vec3d
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import pi, sin
from units.si import DEGREE, METER, Angle, Length
from extensions.building.generate.tower import TowerOptions, generate_tower
from extensions.building.views.structural import (
    default_options,
    structural_view,
)
from extensions.structure.modal import solve_modes
from generators.skyscraper import SkyscraperParameters

comptime DEFAULT_OUTPUT = "out/frame-analysis.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 60


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
        Vector3(46, 22, 52),
        Vector3(0, 10, 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.5, METER),
        far=Length(300, METER),
    )
    return camera^


def main() raises:
    var parameters = SkyscraperParameters()
    parameters.total_height = Length(24, METER)
    var options = TowerOptions(parameters^)
    options.furnished = False
    var tower = generate_tower(options)
    var view = structural_view(tower, default_options())
    var modes = solve_modes(view.model, 1)
    ref shape = modes.shapes[0]
    var largest = Float64(0)
    for i in range(len(view.model.nodes)):
        var d = Vec3d(shape[6 * i], shape[6 * i + 1], shape[6 * i + 2])
        largest = max(largest, d.length())
    var scale = 1.5 / largest
    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(150, 182, 214))
    var camera = _camera()
    var frames = List[Framebuffer]()
    for f in range(FRAMES):
        var phase = sin(2 * pi * Float64(f) / Float64(FRAMES)) * scale
        var assets = Assets()
        var scene = Scene()
        var root = scene.add(Object3D())
        var mesh = Triangles()
        for m in range(len(view.model.members)):
            ref member = view.model.members[m]
            var a = member.start.value
            var b = member.end.value
            var da = Vec3d(shape[6 * a], shape[6 * a + 1], shape[6 * a + 2])
            var db = Vec3d(shape[6 * b], shape[6 * b + 1], shape[6 * b + 2])
            var sway = (da.length() + db.length()) / (2 * largest)
            mesh.box(
                view.model.nodes[a] + da * phase,
                view.model.nodes[b] + db * phase,
                0.35,
                heat_color(0.5 + 0.5 * sway * (1.0 if phase >= 0 else -1.0)),
            )
        mesh.add_to(scene, assets, root)
        add_sky_and_sun(scene, 0.55, 1.5)
        scene.update()
        frames.append(renderer.render(scene, assets, camera))
    write_frames(
        frames,
        example_destination(String(DEFAULT_OUTPUT)),
        DELAY_MS,
        len(frames),
    )
