# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The three lowest modes of a chain of masses on springs.

    mojo run -I . examples/spring_modes.mojo [path.png]

The page is Numerics. `lowest_modes` finds the lowest eigenpairs of the
chain's stiffness against its mass by subspace iteration. Each row is one
mode, moving at its own frequency.
"""

from examples.output import example_destination, write_frames
from examples.preview import Triangles, add_sky_and_sun

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from generators.utils import Vec3d
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import pi, sin, sqrt
from units.si import DEGREE, METER, Angle, Length
from extensions.numerics.eigen import lowest_modes
from extensions.numerics.sparse import SparseBuilder

comptime DEFAULT_OUTPUT = "out/numerics.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 48
comptime DELAY_MS = 50


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
        Length(0.1, METER),
        Length(100, METER),
    )
    camera.place(Vector3(0, 0, 13), Vector3(0, 0, 0))
    return camera^


def main() raises:
    var n = 15
    var k = SparseBuilder(n)
    var mass = SparseBuilder(n)
    for i in range(n):
        k.add(i, i, 2)
        mass.add(i, i, 1)
        if i + 1 < n:
            k.add(i, i + 1, -1)
            k.add(i + 1, i, -1)
    var modes = lowest_modes(k.build(), mass.build(), 3, 1e-10, 100)
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(26, 30, 40))
    var camera = _camera()
    var frames = List[Framebuffer]()
    var base = sqrt(modes.values[0])
    var colors: List[Vec3d] = [
        Vec3d(0.9, 0.5, 0.3),
        Vec3d(0.4, 0.7, 0.9),
        Vec3d(0.5, 0.8, 0.45),
    ]
    for f in range(FRAMES):
        var assets = Assets()
        var scene = Scene()
        var root = scene.add(Object3D())
        var mesh = Triangles()
        for mode in range(3):
            var speed = sqrt(modes.values[mode]) / base
            var swing = sin(
                2
                * pi
                * Float64(f)
                / Float64(FRAMES)
                * Float64(Int(speed + 0.5))
            )
            var row = 2.6 - 2.6 * Float64(mode)
            var previous = Vec3d(-8, 0, row)
            for i in range(n):
                var x = -7 + 14 * Float64(i + 1) / Float64(n + 1)
                var y = modes.vectors[mode][i] * swing * 3
                var here = Vec3d(x, 0, row + y)
                mesh.box(previous, here, 0.06, Vec3d(0.6, 0.6, 0.65))
                mesh.box(
                    here - Vec3d(0.2, 0, 0),
                    here + Vec3d(0.2, 0, 0),
                    0.4,
                    colors[mode],
                )
                previous = here
            mesh.box(previous, Vec3d(8, 0, row), 0.06, Vec3d(0.6, 0.6, 0.65))
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
