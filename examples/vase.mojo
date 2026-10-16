# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A lofted vase turns under a lamp.

    mojo run -I . examples/vase.mojo [path.png]

The page is Lofts and clipping groups. `loft` skins a surface through
rings whose radius swells and narrows. Both ends are capped. The vase
turns one whole turn.
"""

from examples.output import example_destination, gallery_camera, spin_clip

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from geometries.loft import loft
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/lofts.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime RINGS = 12
comptime POINTS = 28


def _vase() raises -> BufferGeometry:
    """Return a capped loft whose rings make a vase.

    Returns:
        The surface, with positions and normals.

    Raises:
        Error: If `loft` refuses a section.
    """
    var sections = List[List[Vector3]]()
    for step in range(RINGS):
        var t = Float32(step) / Float32(RINGS - 1)
        var belly = sin(t * Float32(pi))
        var neck = sin(t * Float32(pi) * 2)
        var radius = 0.18 + belly * 0.28 + neck * 0.06
        var y = -0.9 + t * 1.8
        var ring = List[Vector3]()
        for point in range(POINTS):
            var angle = Float32(point) / Float32(POINTS) * 2 * Float32(pi)
            # Wider in x than in z, so a turn changes the silhouette.
            ring.append(
                Vector3(sin(angle) * radius * 1.35, y, cos(angle) * radius)
            )
        sections.append(ring^)
    return loft(sections^, cap_start=True, cap_end=True)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))

    var assets = Assets()
    var shape = assets.geometries.add(_vase())
    var clay = assets.materials.add(Material(Color(214, 148, 96)))

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(shape, clay, node))
    var lamp = Object3D()
    lamp.set_position(1.2, 1.8, 1.6)
    scene.add_light(ambient_light(Color(220, 214, 206), 0.36))
    scene.add_light(
        directional_light(Color(255, 246, 232), scene.add(lamp^), 1.9)
    )

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(1.15, 0.35, 2.7),
        Vector3(0, 0.05, 0),
        field_of_view=Angle(38.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(20.0, METER),
    )

    spin_clip(
        renderer, camera, assets, scene, node, FRAMES, DELAY_MS, destination
    )
