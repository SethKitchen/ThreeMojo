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
    camera.place(Vector3(11, 10, 12), Vector3(0, -0.5, 0))
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
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(26, 30, 40))
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
        _light(scene)
        scene.update()
        frames.append(renderer.render(scene, assets, camera))
    _write(frames)
