# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A wolf walks one stride, seen from the side.

    mojo run -I . examples/walk.mojo [path.png]

The page is Animals. Each frame turns the wolf's bones to one phase of
the walk and meshes its sculpt again, so the elbows, the knees and the
hocks keep their shape as they bend. The planted feet stay on the floor.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.animals.build import (
    Animal,
    animal_materials,
    create_animal,
    mesh_animal,
)
from extensions.animals.gait import walk_pose
from extensions.anatomy.locomotion import WALK_FROUDE, stride_frequency
from extensions.animals.options import MEDIUM, animal_options
from extensions.animals.registry import WOLF
from geometries.plane import plane
from lights.light import directional_light, hemisphere_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from materials.material import Material, MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/walk.png"
comptime WIDTH = 320
comptime HEIGHT = 200
comptime FRAMES = 16


def frame_at(
    renderer: Renderer, animal: Animal, phase: Float64
) raises -> Framebuffer:
    """Pose the wolf at one phase of its stride and render it.

    Args:
        renderer: The renderer to draw with.
        animal: The wolf.
        phase: How far through the stride, from zero to one.

    Returns:
        The rendered frame.

    Raises:
        Error: If the mesh or the render fails.
    """
    var geometry = mesh_animal(animal, walk_pose(animal.rig, phase), workers=0)
    var assets = Assets()
    var shape = assets.geometries.add(geometry^)
    var materials = List[MaterialId]()
    for m in animal_materials():
        materials.append(assets.materials.add(m.copy()))
    var ground = assets.geometries.add(
        plane(Length(12.0, METER), Length(12.0, METER))
    )
    var soil = assets.materials.add(Material(Color(118, 112, 100)))
    var scene = Scene()
    var body = scene.add(Object3D())
    scene.add_mesh(
        Mesh(shape, materials, body, cast_shadow=True, receive_shadow=True)
    )
    var floor = Object3D()
    floor.rotate_x(Angle(-90.0, DEGREE))
    scene.add_mesh(Mesh(ground, soil, scene.add(floor^), receive_shadow=True))
    var lamp = Object3D()
    lamp.set_position(2.5, 5.0, 3.5)
    var sun = directional_light(Color(255, 243, 228), scene.add(lamp^), 2.4)
    sun.cast_shadow = True
    sun.shadow.map_size = 1024
    sun.shadow.bias = -0.0005
    sun.shadow.normal_bias = 0.01
    sun.shadow.set_extent(Length(1.4, METER))
    sun.shadow.near = Length(0.5, METER)
    sun.shadow.far = Length(15.0, METER)
    scene.add_light(sun)
    var sky = Object3D()
    sky.set_position(0, 10, 0)
    scene.add_light(
        hemisphere_light(
            Color(221, 230, 242), Color(95, 90, 82), scene.add(sky^), 1.1
        )
    )
    var camera = PerspectiveCamera(
        Angle(32.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(30.0, METER),
    )
    camera.place(Vector3(2.6, 0.75, 0.6), Vector3(0, 0.42, 0.0))
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(170, 190, 215))
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP
    var wolf = create_animal(WOLF, animal_options(3, quality=MEDIUM))
    var frames = List[Framebuffer]()
    for i in range(FRAMES):
        frames.append(frame_at(renderer, wolf, Float64(i) / Float64(FRAMES)))
    # One full visual cycle uses this individual's reference frequency,
    # with the APNG frame delay rounded to the nearest millisecond.
    var hip = Length(Float32(wolf.rig.j("hipL").y), METER)
    var frequency = Float64(stride_frequency(WALK_FROUDE, hip).value)
    var delay = max(1, Int(1000.0 / (frequency * Float64(FRAMES)) + 0.5))
    Path(destination).write_bytes(encode(frames, delay_ms=delay))
    print("Wrote", destination, "-", FRAMES, "frames")
