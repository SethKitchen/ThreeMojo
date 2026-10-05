# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The cells of a three-storey cell complex, pulled apart.

    mojo run -I . examples/room_cells.mojo [path.png]

The page is Building topology. `build_storeys` makes one cell per room.
Each cell is drawn shrunk toward its center and lifted by its storey, so
the shared faces between cells show as gaps.
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
from extensions.topology.arrangement import Point2, Region
from extensions.topology.ids import CellId, RegionId
from extensions.topology.storeys import build_storeys
from units.si import Length64

comptime DEFAULT_OUTPUT = "out/building-topology.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 70


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


def _rect(
    id: Int, x0: Float64, y0: Float64, x1: Float64, y1: Float64
) -> Region:
    """Return a rectangular region.

    Args:
        id: The region's id.
        x0: The low x.
        y0: The low y.
        x1: The high x.
        y1: The high y.

    Returns:
        The region, on layer zero.
    """
    var points: List[Point2] = [
        Point2(x0, y0),
        Point2(x1, y0),
        Point2(x1, y1),
        Point2(x0, y1),
    ]
    return Region(0, RegionId(id), points^)


def _build(mut scene: Scene, mut assets: Assets) raises -> NodeId:
    """Add the pulled-apart cells.

    Args:
        scene: The scene.
        assets: The asset store.

    Returns:
        The node the cells hang from.

    Raises:
        Error: If the plans do not make a valid complex.
    """
    var plans = List[List[Region]]()
    plans.append(
        [_rect(0, -4, -2, -1, 2), _rect(1, -1, -2, 4, 0), _rect(2, -1, 0, 4, 2)]
    )
    plans.append([_rect(0, -4, -2, 1, 2), _rect(1, 1, -2, 4, 2)])
    plans.append([_rect(0, -2, -2, 2, 1)])
    var levels: List[Length64] = [
        Length64(0, METER),
        Length64(3, METER),
        Length64(6, METER),
        Length64(9, METER),
    ]
    var built = build_storeys(levels, plans, Length64(1e-6, METER))
    var palette: List[Vec3d] = [
        Vec3d(0.85, 0.45, 0.3),
        Vec3d(0.35, 0.6, 0.85),
        Vec3d(0.5, 0.75, 0.4),
        Vec3d(0.9, 0.75, 0.3),
        Vec3d(0.6, 0.45, 0.8),
        Vec3d(0.4, 0.8, 0.75),
    ]
    var mesh = Triangles()
    for c in range(built.complex.cell_count()):
        var faces = built.complex.faces_of(CellId(c))
        var center = Vec3d(0, 0, 0)
        var count = 0
        for f in range(len(faces)):
            var points = built.complex.face_points(faces[f])
            for k in range(len(points)):
                center = center + points[k]
                count += 1
        center = center * (1.0 / Float64(count))
        var lift = Vec3d(0, 0, Float64(built.cell_storey[c]) * 1.2 - 4.5)
        for f in range(len(faces)):
            var points = built.complex.face_points(faces[f])
            var outward = built.complex.outward_normal(faces[f], CellId(c))
            var shrunk = List[Vec3d]()
            for k in range(len(points)):
                shrunk.append(center + (points[k] - center) * 0.86 + lift)
            for k in range(1, len(shrunk) - 1):
                var a = shrunk[0]
                var b = shrunk[k]
                var d = shrunk[k + 1]
                if (b - a).cross(d - a).dot(outward) < 0:
                    mesh.triangle(a, d, b, palette[c % 6])
                else:
                    mesh.triangle(a, b, d, palette[c % 6])
    var root = scene.add(Object3D())
    mesh.add_to(scene, assets, root)
    return root


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
    camera.place(Vector3(13, 9, 14), Vector3(0, 0.5, 0))
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
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(26, 30, 40))
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
