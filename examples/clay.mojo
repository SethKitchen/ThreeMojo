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

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.sculptor import SCULPT_INFLATE, Sculptor
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.ray import Ray
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
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


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    ball: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the sphere by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera, placed in front of the sphere.
        assets: The sculpted geometry and the material.
        scene: The persistent scene, edited in place.
        ball: The node the sphere rides.
        step: How much further the sphere turns.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(ball).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))

    var assets = Assets()
    var shape = assets.geometries.add(sphere(Length(0.9, METER), 32, 20))
    var clay = assets.materials.add(Material(Color(186, 142, 108)))

    var scene = Scene()
    var ball = scene.add(Object3D())
    scene.add_mesh(Mesh(shape, clay, ball))
    var lamp = Object3D()
    lamp.set_position(1.4, 2.4, 1.8)
    scene.add_light(ambient_light(Color(210, 206, 198), 0.34))
    scene.add_light(
        directional_light(Color(255, 244, 228), scene.add(lamp^), 1.8)
    )
    scene.update()
    _raise_knob(scene, assets)
    # Turn the knob toward the side so the silhouette shows it.
    scene.node(ball).rotate_y(Angle(75.0, DEGREE))
    scene.update()

    var camera = PerspectiveCamera(
        Angle(38.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(1.75, 0.85, 3.1), Vector3(0, 0.05, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, ball, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
