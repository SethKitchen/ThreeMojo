# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A ribbon eight pixels wide turns around a box.

    mojo run -I . examples/wide.mojo [path.png]

The page is Lines. `Line2` draws the path as triangles, so the width is
in pixels and the caps are round. The color runs along the path. A
one-pixel line cannot do either.
"""

from examples.output import example_destination, gallery_camera, spin_clip

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, directional_light
from materials.material import LineWidth, Material, line_material
from math.vector3 import Vector3
from objects.line_segments2 import Line2, line_geometry
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/wide.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime STEPS = 64


def ribbon() -> Tuple[List[Vector3], List[FloatColor]]:
    """Return a closed path and a color at each point.

    Returns:
        The points, then one linear color per point. The first point is
        repeated at the end so the ribbon meets itself.
    """
    var points = List[Vector3]()
    var colors = List[FloatColor]()
    for index in range(STEPS + 1):
        var turn = (
            Float32(2) * Float32(pi) * Float32(index % STEPS) / Float32(STEPS)
        )
        var climb = sin(turn * 2)
        points.append(Vector3(cos(turn) * 1.05, climb * 0.45, sin(turn) * 0.72))
        var red = Float32(0.5) + Float32(0.5) * cos(turn)
        var green = Float32(0.5) + Float32(0.5) * cos(turn + Float32(2))
        var blue = Float32(0.5) + Float32(0.5) * sin(turn)
        colors.append(FloatColor(red, green, blue))
    return (points^, colors^)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))
    var assets = Assets()
    var shape = ribbon()
    var path = assets.geometries.add(line_geometry(shape[0], shape[1]))
    var block = assets.geometries.add(cube(Length(0.7, METER)))
    var ink = assets.materials.add(
        line_material(
            Color(255, 255, 255),
            LineWidth(pixels=8),
            vertex_colors=True,
        )
    )
    var blue = assets.materials.add(Material(Color(60, 90, 160)))

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(block, blue, node))
    scene.add_wide_line(Line2(path, ink, node))

    var lamp = Object3D()
    lamp.set_position(0.8, 1.2, 1.4)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.5))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.2))

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0.2, 0.55, 3.2),
        Vector3(0, 0, 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(40.0, METER),
    )

    spin_clip(
        renderer, camera, assets, scene, node, FRAMES, DELAY_MS, destination
    )
