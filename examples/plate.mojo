# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A simply supported square plate bending under a uniform pressure.

    mojo run -I . examples/plate.mojo [path.png]

The page is Shell analysis. A 10 m concrete plate, 0.2 m thick, is cut
into 16 by 16 squares of two flat shells each. Its edges rest on supports.
The deflection is drawn scaled up, growing with the load, and colored
from the edges to the middle.
"""

from tools._example_output import (
    example_destination,
    gallery_camera,
    gallery_renderer,
    write_frames,
)
from tools._example_preview import Triangles, add_sky_and_sun, heat_color

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from generators.utils import Vec3d
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import cos, pi
from units.si import DEGREE, METER, Angle, Length
from extensions.building.material import concrete
from extensions.structure.ids import NodeId as StructureNode
from extensions.structure.kinds import UX, UY, UZ
from extensions.structure.model import StructuralModel
from extensions.structure.static import solve_static
from units.si import KILOPASCAL, Length64, Pressure64

comptime DEFAULT_OUTPUT = "out/shell-analysis.png"
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
        Vector3(11, 10, 12),
        Vector3(0, -0.5, 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(100.0, METER),
    )
    return camera^


def main() raises:
    var n = 16
    var side = 10.0
    var model = StructuralModel()
    var ids = List[StructureNode]()
    for j in range(n + 1):
        for i in range(n + 1):
            var x = -side / 2 + side * Float64(i) / Float64(n)
            var y = -side / 2 + side * Float64(j) / Float64(n)
            ids.append(model.add_node(Vec3d(x, y, 0)))
    for j in range(n + 1):
        for i in range(n + 1):
            if i == 0 or j == 0 or i == n or j == n:
                model.add_support(ids[j * (n + 1) + i], [UZ])
    model.add_support(ids[0], [UX, UY])
    model.add_support(ids[n], [UY])
    var load_case = model.add_load_case("pressure")
    for j in range(n):
        for i in range(n):
            var a = ids[j * (n + 1) + i]
            var b = ids[j * (n + 1) + i + 1]
            var c = ids[(j + 1) * (n + 1) + i + 1]
            var d = ids[(j + 1) * (n + 1) + i]
            var t = Length64(0.2, METER)
            var s1 = model.add_shell(a, b, c, t, concrete())
            var s2 = model.add_shell(a, c, d, t, concrete())
            model.add_pressure(load_case, s1, Pressure64(10, KILOPASCAL))
            model.add_pressure(load_case, s2, Pressure64(10, KILOPASCAL))
    var result = solve_static(model, load_case)
    var largest = Float64(0)
    for k in range(len(ids)):
        largest = max(largest, abs(result.displacements[6 * k + 2]))
    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(26, 30, 40))
    var camera = _camera()
    var frames = List[Framebuffer]()
    for f in range(FRAMES):
        var load = 0.5 - 0.5 * cos(2 * pi * Float64(f) / Float64(FRAMES))
        var scale = 1.5 * load / largest
        var assets = Assets()
        var scene = Scene()
        var root = scene.add(Object3D())
        var mesh = Triangles()
        for j in range(n):
            for i in range(n):
                var corners = [
                    j * (n + 1) + i,
                    j * (n + 1) + i + 1,
                    (j + 1) * (n + 1) + i + 1,
                    (j + 1) * (n + 1) + i,
                ]
                var p = List[Vec3d]()
                var w = List[Float64]()
                for k in range(4):
                    var node = corners[k]
                    var dz = result.displacements[6 * node + 2]
                    p.append(model.nodes[node] + Vec3d(0, 0, dz * scale))
                    w.append(abs(dz) / largest)
                var color = heat_color(load * (w[0] + w[1] + w[2] + w[3]) / 4)
                mesh.triangle(p[0], p[1], p[2], color)
                mesh.triangle(p[0], p[2], p[3], color)
                mesh.triangle(p[0], p[2], p[1], color)
                mesh.triangle(p[0], p[3], p[2], color)
        mesh.add_to(scene, assets, root)
        scene.node(root).rotate_y(Angle(Float32(f) * 4, DEGREE))
        add_sky_and_sun(scene, 0.55, 1.5)
        scene.update()
        frames.append(renderer.render(scene, assets, camera))
    write_frames(
        frames,
        example_destination(String(DEFAULT_OUTPUT)),
        DELAY_MS,
        len(frames),
    )
