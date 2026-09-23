# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cube and a ball on a grid, in the terminal, turned with the mouse.

    mojo run -I . examples/viewer.mojo [columns rows]

Drag with the left button to orbit, with the right button to pan, and turn
the wheel to dolly. The arrows pan; with Shift they orbit. `q`, Escape or
Ctrl+C quits. The frame is `columns` pixels wide and twice `rows` high,
96 by 32 rows unless given. The window then asks the terminal its size
every second, and follows it when the terminal answers.

This example needs a terminal. It is not run by `make animation`.
"""

from cameras.perspective_camera import PerspectiveCamera
from controls.input import CTRL_C, ESCAPE, KEY_DOWN, Key, RESIZE
from controls.orbit_controls import OrbitControls
from core.assets import Assets
from core.clock import Clock
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.sphere import sphere
from helpers.grid import grid_helper
from helpers.material import helper_material
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.line import Line, SEGMENTS
from render.framebuffer import Color
from renderers.renderer import Renderer, available_workers
from std.sys import argv
from units.si import Angle, DEGREE, Duration, Length, METER, MILLISECOND
from window.terminal import TerminalWindow

comptime DEFAULT_COLUMNS = 96
comptime DEFAULT_ROWS = 32
# How long to wait for input before drawing the next frame: about sixty
# frames a second when the render is quick.
comptime FRAME_MS = 16
comptime QUIT = Key(113)
# How often to ask the terminal its size, in frames.
comptime SIZE_EVERY = 60


def main() raises:
    var args = argv()
    var columns = DEFAULT_COLUMNS
    var rows = DEFAULT_ROWS
    if len(args) > 2:
        columns = Int(args[1])
        rows = Int(args[2])
    var width = columns
    var height = rows * 2

    var renderer = Renderer(width, height, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))
    var assets = Assets()
    var scene = Scene()
    var root = scene.add(Object3D())
    var block = assets.geometries.add(cube(Length(0.8, METER)))
    var ball = assets.geometries.add(sphere(Length(0.35, METER), 24, 16))
    var blue = assets.materials.add(Material(Color(70, 110, 200)))
    var orange = assets.materials.add(Material(Color(230, 140, 60)))
    var stand = Object3D()
    stand.set_position(-0.5, 0.4, 0)
    scene.add_mesh(Mesh(block, blue, scene.add(stand^)))
    var perch = Object3D()
    perch.set_position(0.8, 0.35, 0.4)
    scene.add_mesh(Mesh(ball, orange, scene.add(perch^)))

    var paint = assets.materials.add(helper_material())
    var grid = assets.geometries.add(grid_helper(Length(4.0, METER), 8))
    scene.add_line(Line(grid, paint, root, mode=SEGMENTS))

    var lamp = Object3D()
    lamp.set_position(0.5, 0.9, 0.8)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.79))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.51))
    scene.update()

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(width) / Float32(height),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(2.4, 1.8, 3.2), Vector3(0, 0.3, 0))
    var controls = OrbitControls(Vector3(0, 0.3, 0))
    controls.enable_damping = True
    controls.min_distance = Length(1.0, METER)
    controls.max_distance = Length(20.0, METER)

    var window = TerminalWindow(width, height)
    var clock = Clock()
    var running = True
    var frame = 0
    try:
        while running:
            if frame % SIZE_EVERY == 0:
                window.request_size()
            frame += 1
            for event in window.poll(Duration(Float32(FRAME_MS), MILLISECOND)):
                var quit = event.key == QUIT or event.key == ESCAPE
                if event.kind == KEY_DOWN and (quit or event.key == CTRL_C):
                    running = False
                var grew = event.x != width or event.y != height
                if event.kind == RESIZE and grew:
                    width = event.x
                    height = event.y
                    window.resize(width, height)
                    renderer = Renderer(
                        width, height, workers=available_workers()
                    )
                    renderer.set_background(Color(16, 18, 26))
                    camera.aspect = Float32(width) / Float32(height)
                    continue
                controls.handle(event, camera, height)
            _ = controls.update(camera, clock.delta())
            window.present(renderer.render(scene, assets, camera))
    finally:
        window.close()
