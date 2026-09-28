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

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.loft import loft
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin
from std.pathlib import Path
from std.sys import argv
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


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the vase by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera, placed in front of the vase.
        assets: The geometry and the material.
        scene: The persistent scene, edited in place.
        node: The node the vase rides.
        step: How much further the vase turns.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(node).rotate_y(step)
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

    var camera = PerspectiveCamera(
        Angle(38.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(1.15, 0.35, 2.7), Vector3(0, 0.05, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, node, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
