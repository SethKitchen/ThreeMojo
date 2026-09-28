# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Hills from simplex noise turn under a lamp.

    mojo run -I . examples/terrain.mojo [path.png]

The page is Math addons. `SimplexNoise` sets the height of a grid, and
the height sets the vertex color. The ground turns one whole turn. The
field itself stays put, so the loop has no jump.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.noise import SimplexNoise
from math.utils import SeededRandom
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/mathaddons.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime COLUMNS = 28
comptime ROWS = 28
comptime SPAN = Float32(2.8)


def _ground() raises -> BufferGeometry:
    """Return a flat grid in the xz plane, ready for heights.

    Returns:
        The grid, with positions, a placeholder color and an index.

    Raises:
        Error: If the index is not whole triangles.
    """
    var geometry = BufferGeometry()
    var positions = List[Float32]()
    var colors = List[Float32]()
    for _ in range(COLUMNS * ROWS):
        positions.append(0)
        positions.append(0)
        positions.append(0)
        colors.append(1)
        colors.append(1)
        colors.append(1)
    geometry.set_attribute(POSITION, BufferAttribute(positions^, 3))
    geometry.set_attribute(COLOR, BufferAttribute(colors^, 3))
    var index = List[Int]()
    for row in range(ROWS - 1):
        for col in range(COLUMNS - 1):
            var i00 = row * COLUMNS + col
            var i10 = i00 + 1
            var i01 = i00 + COLUMNS
            var i11 = i01 + 1
            index.append(i00)
            index.append(i10)
            index.append(i11)
            index.append(i00)
            index.append(i11)
            index.append(i01)
    geometry.set_index(index^)
    return geometry^


def _roll(mut geometry: BufferGeometry, field: SimplexNoise) raises:
    """Write the noise field into the grid's heights and colors.

    Args:
        geometry: The grid from `_ground`.
        field: The noise. A seed fixes the hills.

    Raises:
        Error: If the geometry has no positions, or a sample is not finite.
    """
    var positions = List[Float32]()
    var colors = List[Float32]()
    for row in range(ROWS):
        var z = (Float32(row) / Float32(ROWS - 1) - 0.5) * SPAN
        for col in range(COLUMNS):
            var x = (Float32(col) / Float32(COLUMNS - 1) - 0.5) * SPAN
            var height = Float32(
                field.noise3d(Float64(x) * 1.35, Float64(z) * 1.35, 0.4)
            )
            positions.append(x)
            positions.append(height * 0.42)
            positions.append(z)
            var t = (height + 1) * 0.5
            colors.append(0.12 + 0.76 * t)
            colors.append(0.28 + 0.4 * t)
            colors.append(0.62 - 0.38 * t)
    geometry.set_attribute(POSITION, BufferAttribute(positions^, 3))
    geometry.set_attribute(COLOR, BufferAttribute(colors^, 3))
    geometry.compute_vertex_normals()


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    ground: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the ground by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera, placed above the ground.
        assets: The geometry and the material.
        scene: The persistent scene, edited in place.
        ground: The ground's node.
        step: How much further the ground turns.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(ground).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))

    var random = SeededRandom(7)
    var field = SimplexNoise(random)
    var shape = _ground()
    _roll(shape, field)

    var assets = Assets()
    var ground_shape = assets.geometries.add(shape^)
    var paint = assets.materials.add(
        Material(Color(255, 255, 255), vertex_colors=True)
    )

    var scene = Scene()
    var ground = scene.add(Object3D())
    scene.add_mesh(Mesh(ground_shape, paint, ground))

    var lamp = Object3D()
    lamp.set_position(1.4, 2.2, 1.2)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.4))
    scene.add_light(
        directional_light(Color(255, 244, 230), scene.add(lamp^), 2.1)
    )

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(30.0, METER),
    )
    camera.place(Vector3(1.7, 1.25, 2.15), Vector3(0, 0, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, ground, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
