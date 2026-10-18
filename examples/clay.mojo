# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A brush raises a knob on a sphere, and the sphere turns.

    mojo run -I . examples/clay.mojo [path.png]

The page is Sculptor. `SCULPT_INFLATE` stamps the front of a sphere
before the frames start. Detail stays at zero, so the triangles do not
change. The sphere then turns one whole turn.
"""

from examples.output import (
    example_destination,
    fill_and_key,
    gallery_camera,
    gallery_renderer,
    spin_clip,
)

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.sculptor import SCULPT_INFLATE, Sculptor
from geometries.sphere import sphere
from materials.material import Material
from math.ray import Ray
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/sculptor.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def _raise_knob(mut scene: Scene, mut assets: Assets) raises:
    """Stamp an inflated knob on the sphere's front.

    Args:
        scene: The scene, already updated, whose first mesh is the sphere.
        assets: The geometry the sculptor writes.

    Raises:
        Error: If a stamp misses the sphere, or the sculptor refuses it.
    """
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.set_tool(SCULPT_INFLATE)
    sculptor.set_detail(0)
    sculptor.set_strength(1)
    # One stamp moves a vertex by a tenth of the brush radius. Repeat the
    # same ray so the knob stands out from the sphere.
    var ray = Ray(Vector3(0.05, 0.38, 2.6), Vector3(0, -0.12, -1))
    for _ in range(8):
        if not sculptor.stroke_from_ray(
            scene, assets, ray, Length(0.42, METER)
        ):
            raise Error("The brush missed the sphere")
        # Rebalance between stamps so the next one still finds the vertices.
        sculptor.end_stroke()


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))

    var assets = Assets()
    var shape = assets.geometries.add(sphere(Length(0.9, METER), 32, 20))
    var clay = assets.materials.add(Material(Color(186, 142, 108)))

    var scene = Scene()
    var ball = scene.add(Object3D())
    scene.add_mesh(Mesh(shape, clay, ball))
    fill_and_key(
        scene,
        1.4,
        2.4,
        1.8,
        Color(210, 206, 198),
        0.34,
        Color(255, 244, 228),
        1.8,
    )
    scene.update()
    _raise_knob(scene, assets)
    # Turn the knob toward the side so the silhouette shows it.
    scene.node(ball).rotate_y(Angle(75.0, DEGREE))
    scene.update()

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(1.75, 0.85, 3.1),
        Vector3(0, 0.05, 0),
        field_of_view=Angle(38.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(20.0, METER),
    )

    spin_clip(
        renderer, camera, assets, scene, ball, FRAMES, DELAY_MS, destination
    )
