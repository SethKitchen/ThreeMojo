# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two cubes orbiting on a scene graph, drawn with a depth buffer.

    mojo run -I . examples/cubes.mojo [path.png]

A small cube orbits a large one and passes behind it, so the correct image
depends on comparing depth per pixel. The renderer does no backface culling at
all, so the depth buffer carries the whole result.

The orbit is not computed here. The small cube is a child of a spinning pivot,
so rotating the pivot carries it around; that is what a transform hierarchy is
for. Nothing in this file does arithmetic on a position.

This example used to be twice as long, with its own cube vertices, its own
projection loop and its own per-face colour table. Those became
`geometries.box`, `renderers.renderer` and real Lambert shading, and what is
left is the scene itself.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.object3d import Object3D
from core.assets import Assets
from materials.material import Material
from core.assets import Assets
from materials.material import Material
from core.scene import Scene
from geometries.box import cube
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METRE

comptime DEFAULT_OUTPUT = "out/cubes.png"
comptime WIDTH = 260
comptime HEIGHT = 200
comptime FRAMES = 48
comptime DELAY_MS = 50
comptime ORBIT_RADIUS = Float32(1.6)


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    centre_mesh: Mesh,
    moon_mesh: Mesh,
    turn: Float32,
) raises -> Framebuffer:
    """Render one frame with the orbit advanced to `turn` degrees.

    The geometries, materials and meshes are built once by the caller. Only
    the transforms change between frames, so rebuilding two cubes forty-eight
    times would be forty-eight times the work for the same vertices.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The stores owning both cubes and their materials.
        centre_mesh: The cube at the centre, bound to node 1.
        moon_mesh: The smaller orbiting cube, bound to node 2.
        turn: How far round the orbit has gone, in degrees.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    var scene = Scene()

    # The pivot spins; the moon is parented to it and comes along.
    var pivot = Object3D()
    pivot.set_euler(Angle(0.0, DEGREE), Angle(turn, DEGREE), Angle(0.0, DEGREE))
    var pivot_node = scene.add(pivot^)

    var centre = Object3D()
    centre.set_euler(
        Angle(20.0, DEGREE), Angle(turn / 2, DEGREE), Angle(0.0, DEGREE)
    )
    var centre_node = scene.add(centre^)

    var moon = Object3D()
    moon.set_position(ORBIT_RADIUS, 0, 0)
    moon.set_euler(
        Angle(0.0, DEGREE), Angle(0.0, DEGREE), Angle(turn * 2, DEGREE)
    )
    var moon_node = scene.attach(moon^, pivot_node)

    scene.update()

    var meshes = List[Mesh]()
    meshes.append(centre_mesh)
    meshes.append(moon_mesh)
    return renderer.render(scene, assets, meshes, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METRE),
        Length(100.0, METRE),
    )
    camera.place(Vector3(0, 1.2, 4.5), Vector3(0, 0, 0))

    var renderer = Renderer(WIDTH, HEIGHT)

    # Built once and shared by every frame.
    var assets = Assets()
    var centre_mesh = Mesh(
        assets.geometries.add(cube(Length(1.1, METRE))),
        assets.materials.add(Material(Color(255, 140, 40))),
        1,
    )
    var moon_mesh = Mesh(
        assets.geometries.add(cube(Length(0.44, METRE))),
        assets.materials.add(Material(Color(90, 190, 255))),
        2,
    )

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        frames.append(
            frame_at(
                renderer,
                camera,
                assets,
                centre_mesh,
                moon_mesh,
                Float32(360) * Float32(index) / Float32(FRAMES),
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
