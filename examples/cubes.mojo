# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two cubes orbiting on a scene graph, drawn with a depth buffer.

    mojo run -I . examples/cubes.mojo [path.png]

A small cube orbits a large one and passes behind it, so the correct image
depends on comparing depth per pixel. Back faces are culled as an
optimization, but the depth buffer is what decides the picture.

The orbit is not computed here. The small cube is a child of a spinning pivot,
so rotating the pivot carries it around; that is what a transform hierarchy is
for. Nothing in this file does arithmetic on a position.

The scene is built once and edited in place each frame, the way a three.js
scene is: turn the pivot, update, render. This example used to rebuild every
node every frame, because editing one meant copying it out and putting it
back; `Scene.node` is what made the persistent scene the easy version.

Each frame turns the nodes a little further rather than setting them to an
angle, which is three.js's `rotateY` and what a quaternion is for: `rotate_y`
is one multiply, about the node's *own* y, so the large cube's tilt is set
once and its spin follows the tilted axis from then on. For this particular
tilt `rotation.y += 0.01` in the `XYZ` order would come to the same turn; it
does not in general, and `core.object3d` says why.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER, RADIAN

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
    mut scene: Scene,
    pivot: NodeId,
    center: NodeId,
    moon: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Advance the orbit by `step` and render one frame.

    Only three rotations change between frames, so only three nodes are
    touched. Everything else -- the geometry, the materials, the meshes, the
    lamp -- is built once by the caller and left alone.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The stores owning both cubes and their materials.
        scene: The persistent scene, edited in place.
        pivot: The node the moon orbits about.
        center: The large cube's node.
        moon: The small cube's node, a child of `pivot`.
        step: How much further round the orbit goes this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(pivot).rotate_y(step)
    scene.node(center).rotate_y(Angle(step.value / 2, RADIAN))
    scene.node(moon).rotate_z(Angle(step.value * 2, RADIAN))
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 1.2, 4.5), Vector3(0, 0, 0))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())

    # Built once and shared by every frame.
    var assets = Assets()
    var large = assets.geometries.add(cube(Length(1.1, METER)))
    var small = assets.geometries.add(cube(Length(0.44, METER)))
    var orange = assets.materials.add(Material(Color(255, 140, 40)))
    var blue = assets.materials.add(Material(Color(90, 190, 255)))

    # The pivot spins; the moon is parented to it and comes along.
    var scene = Scene()
    var pivot = scene.add(Object3D())
    # Tilted once; every later turn is about the tilted y.
    var large_node = Object3D()
    large_node.set_euler(
        Angle(20.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var center = scene.add(large_node^)
    var moon_node = Object3D()
    moon_node.set_position(ORBIT_RADIUS, 0, 0)
    var moon = scene.attach(moon_node^, pivot)

    # The lamp is a node like any other, so it could be parented to something
    # that moves.
    var lamp = Object3D()
    lamp.set_position(0.4, 0.8, 0.5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 0.75))

    scene.add_mesh(Mesh(large, orange, center))
    scene.add_mesh(Mesh(small, blue, moon))

    # One full orbit over the loop, so the animation repeats seamlessly.
    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(
            frame_at(renderer, camera, assets, scene, pivot, center, moon, step)
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
