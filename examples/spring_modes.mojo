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

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, NORMAL, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from generators.utils import Vec3d
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin, sqrt
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length
from extensions.numerics.eigen import lowest_modes
from extensions.numerics.sparse import SparseBuilder

comptime DEFAULT_OUTPUT = "out/numerics.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 48
comptime DELAY_MS = 50


struct Triangles(Movable):
    """Colored triangles under construction, in model coordinates, z up."""

    var positions: List[Float32]
    var normals: List[Float32]
    var colors: List[Float32]

    def __init__(out self):
        """Start with no triangles."""
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.colors = List[Float32]()

    def triangle(mut self, a: Vec3d, b: Vec3d, c: Vec3d, color: Vec3d):
        """Add one flat triangle, converting z up to y up.

        Args:
            a: The first corner.
            b: The second corner.
            c: The third corner.
            color: The linear color, each channel zero to one.
        """
        var n = (b - a).cross(c - a).normalized()
        var corners = [a, b, c]
        for k in range(3):
            var p = corners[k]
            self.positions.append(Float32(p.x))
            self.positions.append(Float32(p.z))
            self.positions.append(Float32(-p.y))
            self.normals.append(Float32(n.x))
            self.normals.append(Float32(n.z))
            self.normals.append(Float32(-n.y))
            self.colors.append(Float32(color.x))
            self.colors.append(Float32(color.y))
            self.colors.append(Float32(color.z))

    def box(mut self, start: Vec3d, end: Vec3d, size: Float64, color: Vec3d):
        """Add a square bar from one point to another.

        Args:
            start: One end of the bar's axis.
            end: The other end.
            size: The bar's width and depth.
            color: The linear color.
        """
        var axis = end - start
        var along = axis.normalized()
        var helper = Vec3d(0, 0, 1) if abs(along.z) < 0.9 else Vec3d(1, 0, 0)
        var u = along.cross(helper).normalized() * (size / 2)
        var v = along.cross(u).normalized() * (size / 2)
        var c: List[Vec3d] = [
            start - u - v,
            start + u - v,
            start + u + v,
            start - u + v,
        ]
        for k in range(4):
            var p = c[k]
            var q = c[(k + 1) % 4]
            self.triangle(p, q, q + axis, color)
            self.triangle(p, q + axis, p + axis, color)
        self.triangle(c[0], c[2], c[1], color)
        self.triangle(c[0], c[3], c[2], color)
        self.triangle(c[0] + axis, c[1] + axis, c[2] + axis, color)
        self.triangle(c[0] + axis, c[2] + axis, c[3] + axis, color)

    def add_to(
        self, mut scene: Scene, mut assets: Assets, parent: NodeId
    ) raises:
        """Add the triangles as one mesh under a node.

        Args:
            scene: The scene.
            assets: The asset store.
            parent: The node to hang the mesh from.

        Raises:
            Error: If the scene refuses the mesh.
        """
        var geometry = BufferGeometry()
        geometry.set_attribute(
            String(POSITION), BufferAttribute(self.positions.copy(), 3)
        )
        geometry.set_attribute(
            String(NORMAL), BufferAttribute(self.normals.copy(), 3)
        )
        geometry.set_attribute(
            String(COLOR), BufferAttribute(self.colors.copy(), 3)
        )
        var node = Object3D()
        node.parent = parent
        var id = scene.add(node^)
        scene.add_mesh(
            Mesh(
                assets.geometries.add(geometry^),
                assets.materials.add(
                    Material(Color(255, 255, 255), vertex_colors=True)
                ),
                id,
            )
        )


def heat_color(t: Float64) -> Vec3d:
    """Return blue for zero, through white, to red for one.

    Args:
        t: The value, from zero to one.

    Returns:
        The linear color.
    """
    var s = max(0.0, min(1.0, t))
    if s < 0.5:
        var k = s * 2
        return Vec3d(0.1 + 0.85 * k, 0.25 + 0.7 * k, 0.9)
    var k = (s - 0.5) * 2
    return Vec3d(0.95, 0.95 - 0.75 * k, 0.9 - 0.8 * k)


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


def _light(mut scene: Scene) raises:
    """Add a sky fill and a sun.

    Args:
        scene: The scene to light.

    Raises:
        Error: If the scene refuses a node.
    """
    scene.add_light(ambient_light(Color(214, 222, 232), 0.55))
    var sun = Object3D()
    sun.set_position(30, 60, 40)
    scene.add_light(
        directional_light(Color(255, 246, 230), scene.add(sun^), 1.5)
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
        _light(scene)
        scene.update()
        frames.append(renderer.render(scene, assets, camera))
    _write(frames)
