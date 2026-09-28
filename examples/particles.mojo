# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A compute kernel walks points around a sphere.

    mojo run -I . examples/particles.mojo [path.png]

The page is Compute nodes. Each point's position gains the cross product
of up and itself, so the cloud orbits. The new positions are copied into
the point geometry. One orbit brings every point home.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.compute_nodes import (
    ComputeKernel,
    ComputeNode,
    HostCompute,
    StorageBufferNode,
    StorageBufferStore,
)
from materials.nodes import NODE_VEC3
from materials.material import Material, PointSize, points_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.points import Points
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/computenodes.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime COUNT = 72


def _ring() -> List[Float32]:
    """Return points on three rings around the origin.

    Returns:
        Three floats a point.
    """
    var numbers = List[Float32]()
    for index in range(COUNT):
        var band = index % 3
        var radius = Float32(0.52)
        var y = Float32(-0.12)
        if band == 1:
            radius = 0.7
            y = 0.1
        if band == 2:
            radius = 0.9
            y = 0.28
        var turn = (
            Float32(2) * Float32(pi) * Float32(index // 3) / Float32(COUNT // 3)
        )
        numbers.append(cos(turn) * radius)
        numbers.append(y)
        numbers.append(sin(turn) * radius)
    return numbers^


def _orbit(positions: StorageBufferNode) raises -> ComputeNode:
    """Compile one orbit step for every position.

    Args:
        positions: The buffer of positions.

    Returns:
        The step. Run it once a frame.

    Raises:
        Error: If a node has the wrong type, or the count is refused.
    """
    var kernel = ComputeKernel()
    var i = kernel.instance_index()
    var place = kernel.element(positions, i)
    var spin = kernel.graph.cross(kernel.graph.vec3(0, 1, 0), place)
    var speed = Float32(2) * Float32(pi) / Float32(FRAMES)
    kernel.add_assign(
        positions, i, kernel.graph.mul(spin, kernel.graph.float(speed))
    )
    return kernel.compute(COUNT)


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    mut assets: Assets,
    mut scene: Scene,
    mut host: HostCompute,
    mut store: StorageBufferStore,
    positions: StorageBufferNode,
    step_node: ComputeNode,
    shape: GeometryId,
) raises -> Framebuffer:
    """Step the points, copy them into the geometry, and render.

    Args:
        renderer: The renderer to draw with.
        camera: The camera, placed in front of the cloud.
        assets: The point geometry lives here and is rewritten.
        scene: The persistent scene.
        host: The runner.
        store: The position buffer.
        positions: Which buffer holds the positions.
        step_node: The compiled orbit step.
        shape: The point geometry to rewrite.

    Returns:
        The rendered frame.

    Raises:
        Error: If the compute step or the render is invalid.
    """
    host.compute(store, step_node)
    var moved = store.array(positions)
    ref geometry = assets.geometries.geometries[shape.value]
    geometry.set_attribute(POSITION, BufferAttribute(moved^, 3))
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(14, 16, 22))

    var numbers = _ring()
    var store = StorageBufferStore()
    var copied = numbers.copy()
    var positions = store.instanced_array(numbers^, NODE_VEC3)
    var step_node = _orbit(positions)

    var assets = Assets()
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(copied^, 3))
    var shape = assets.geometries.add(geometry^)
    var dots = assets.materials.add(
        points_material(Color(255, 176, 64), PointSize(0.16))
    )
    var core = assets.geometries.add(sphere(Length(0.4, METER), 24, 16))
    var paint = assets.materials.add(Material(Color(86, 104, 150)))

    var scene = Scene()
    scene.add_mesh(Mesh(core, paint, scene.add(Object3D())))
    scene.add_points(Points(shape, dots, scene.add(Object3D())))
    var lamp = Object3D()
    lamp.set_position(1.2, 1.8, 1.4)
    scene.add_light(ambient_light(Color(200, 206, 220), 0.4))
    scene.add_light(
        directional_light(Color(255, 248, 236), scene.add(lamp^), 1.6)
    )

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.2, 0.95, 3.15), Vector3(0, 0.08, 0))

    var host = HostCompute()
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(
            frame_at(
                renderer,
                camera,
                assets,
                scene,
                host,
                store,
                positions,
                step_node,
                shape,
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
