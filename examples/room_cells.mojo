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

from examples.output import example_destination, spin_gallery
from examples.preview import Triangles, add_sky_and_sun

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from generators.utils import Vec3d
from math.vector3 import Vector3
from render.framebuffer import Color
from renderers.renderer import Renderer, available_workers
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


def main() raises:
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(26, 30, 40))
    var assets = Assets()
    var scene = Scene()
    var root = _build(scene, assets)
    add_sky_and_sun(scene, 0.55, 1.5)
    var camera = _camera()
    var destination = example_destination(String(DEFAULT_OUTPUT))
    spin_gallery(
        renderer,
        camera,
        assets,
        scene,
        root,
        FRAMES,
        DELAY_MS,
        destination,
    )
