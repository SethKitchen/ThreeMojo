# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cylinder bent by two bones, one at each end.

    mojo run -I . examples/skinning.mojo [path.png]

Vertices near the top follow the turning bone. Vertices near the bottom
stay with the root. That is skinning: the mesh is not parented, the bones
carry it.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.cylinder import cylinder
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.skeleton import bind_skeleton
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/skinning.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime HEIGHT_M = Float32(2)


def skin_along_y(mut geometry: BufferGeometry) raises:
    """Weight each vertex between bone zero at the bottom and bone one at
    the top.

    Args:
        geometry: A cylinder standing on y, centered on the origin.

    Raises:
        Error: If the geometry has no positions.
    """
    var placed = geometry.clone_attribute(String(POSITION))
    var count = placed.count()
    var indices = List[Float32]()
    var weights = List[Float32]()
    for index in range(count):
        var t = (placed.vector3(index).y + HEIGHT_M / 2) / HEIGHT_M
        if t < 0:
            t = 0
        if t > 1:
            t = 1
        indices.append(0)
        indices.append(1)
        indices.append(0)
        indices.append(0)
        weights.append(1 - t)
        weights.append(t)
        weights.append(0)
        weights.append(0)
    geometry.set_attribute(String(SKIN_INDEX), BufferAttribute(indices^, 4))
    geometry.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    tip: NodeId,
    bend: Angle,
) raises -> Framebuffer:
    """Pose the tip bone and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry and materials.
        scene: The persistent scene, edited in place.
        tip: The bone that bends the top of the cylinder.
        bend: How far that bone is turned about z.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(tip).set_euler(Angle(0.0, DEGREE), Angle(0.0, DEGREE), bend)
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
    var arm = cylinder(
        Length(0.18, METER),
        Length(0.22, METER),
        Length(HEIGHT_M, METER),
        14,
        10,
    )
    skin_along_y(arm)
    var paint = assets.materials.add(Material(Color(255, 150, 70)))

    var scene = Scene()
    var body = scene.add(Object3D())
    var root = scene.add(Object3D())
    var tip = scene.add(Object3D())
    scene.update()
    var skeleton = bind_skeleton(
        [root, tip],
        [scene.world_matrix(root), scene.world_matrix(tip)],
    )
    scene.add_skinned_mesh(
        SkinnedMesh(assets.geometries.add(arm^), paint, body, skeleton^)
    )

    var lamp = Object3D()
    lamp.set_position(0.6, 0.8, 0.8)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.69))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.67))

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(2.4, 0.2, 3.2), Vector3(0, 0, 0))

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var turn = Float32(2) * Float32(pi) * Float32(index) / Float32(FRAMES)
        var bend = Angle(55.0 * cos(turn), DEGREE)
        frames.append(frame_at(renderer, camera, assets, scene, tip, bend))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
