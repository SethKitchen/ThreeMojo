# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A grid, the axes, a box around a cube and the frustum of a second camera.

    mojo run -I . examples/outlines.mojo [path.png]

The page is Helpers. Every helper is a line geometry drawn by the line
pass, so the camera circling the scene draws them behind the cube and in
front of it as it goes. The second camera rides a node aimed at the cube,
and its outline rides the same node.
"""

from examples.output import (
    example_destination,
    fill_and_key,
    gallery_renderer,
    spin_clip,
)

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from helpers.axes import axes_helper
from helpers.box import DEFAULT_BOX_COLOR, box_helper
from helpers.camera import camera_helper
from helpers.grid import grid_helper
from helpers.material import helper_material
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.line import Line, SEGMENTS
from objects.mesh import Mesh
from render.framebuffer import Color
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/helpers.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))
    var assets = Assets()
    var scene = Scene()
    var root = scene.add(Object3D())

    # The ground and the frame: a grid of four meters in eight cells, and
    # the axes, both at the origin.
    var paint = assets.materials.add(helper_material())
    var grid = assets.geometries.add(grid_helper(Length(4.0, METER), 8))
    var axes = assets.geometries.add(axes_helper(Length(1.2, METER)))
    scene.add_line(Line(grid, paint, root, mode=SEGMENTS))
    scene.add_line(Line(axes, paint, root, mode=SEGMENTS))

    # A cube, turned and moved, and the box around where it stands.
    var block = assets.geometries.add(cube(Length(0.7, METER)))
    var blue = assets.materials.add(Material(Color(70, 110, 200)))
    var stand = Object3D()
    stand.set_position(0.9, 0.35, -0.3)
    stand.rotate_y(Angle(30.0, DEGREE))
    var placed = scene.add(stand^)
    scene.update()
    scene.add_mesh(Mesh(block, blue, placed))
    var bounds = assets.geometries.get(block).bounding_box()
    bounds.apply_matrix4(scene.world_matrix(placed))
    var yellow = assets.materials.add(Material(DEFAULT_BOX_COLOR, kind=BASIC))
    var edges = assets.geometries.add(box_helper(bounds))
    scene.add_line(Line(edges, yellow, root, mode=SEGMENTS))

    # A second camera, perched and aimed at the cube, with its outline on
    # the node it rides. It is never rendered through; it is only drawn.
    var watched = PerspectiveCamera(
        Angle(40.0, DEGREE), 1.5, Length(0.25, METER), Length(1.6, METER)
    )
    var perch = Object3D()
    perch.set_position(-1.2, 0.9, 1.1)
    var perch_node = scene.add(perch^)
    scene.update()
    scene.look_at(perch_node, Vector3(0.9, 0.35, -0.3), camera=True)
    watched.attach(perch_node)
    var outline = assets.geometries.add(camera_helper(watched))
    scene.add_line(Line(outline, paint, perch_node, mode=SEGMENTS))

    fill_and_key(
        scene,
        0.5,
        0.9,
        0.8,
        Color(255, 255, 255),
        0.79,
        Color(255, 255, 255),
        2.51,
    )

    # The camera that renders swings around a pivot at the origin.
    var pivot = scene.add(Object3D())
    var seat = Object3D()
    seat.set_position(0, 1.9, 4.2)
    var seat_node = scene.attach(seat^, pivot)
    scene.update()
    scene.look_at(seat_node, Vector3(0, 0.2, 0), camera=True)
    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.attach(seat_node)
    spin_clip(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
