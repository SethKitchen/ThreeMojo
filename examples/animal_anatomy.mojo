# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Game mode beside engineering mode, walking at their real size.

    mojo run -I . examples/animal_anatomy.mojo [path.png]

Each row is one species, scaled to a reference shoulder height and
sampled for mass. This gallery explicitly opts into design estimates. The left tile is game mode: the painted coat, with the muscle
bellies bulging as they shorten. The right tile is engineering mode:
the translucent skin over the skeleton and the muscles, each belly its
own volume. Both sample the same physical timeline, with each
animal's reference frequency at a Froude number of 0.25. The visual
stride is capped by the rig's reach. This is an in-place kinematic
illustration, not a validated physical gait. The program
prints each animal's mass, center of mass, stride, and the static load
on each joint of its standing limbs.
"""

from examples.output import example_destination, blit, gallery_camera

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from extensions.anatomy.locomotion import (
    WALK_FROUDE,
    speed_at,
    stride_frequency,
    stride_length,
)
from extensions.animals.anatomy.body import species_body
from extensions.animals.anatomy.engineering import (
    calibrate,
    calibrated_animal,
    calibrated_mass,
)
from extensions.animals.anatomy.flex import flexed_animal
from extensions.animals.anatomy.muscles import species_muscles
from extensions.animals.anatomy.render import (
    BONE_LAYER,
    MUSCLE_LAYER,
    SKIN_LAYER,
    anatomy_layers,
    anatomy_materials,
)
from extensions.animals.anatomy.stance import standing_loads
from extensions.animals.build import (
    animal_materials,
    create_animal,
    mesh_animal,
)
from extensions.animals.gait import walk_pose_at, walk_stride
from extensions.animals.options import (
    ADULT,
    MALE,
    MEDIUM,
    Variant,
    animal_options,
)
from extensions.animals.registry import species_name, species_of
from geometries.plane import plane
from lights.light import directional_light, hemisphere_light
from materials.material import Material, MaterialId
from math.utils import max3
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import max
from std.pathlib import Path
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length

comptime DEFAULT_OUTPUT = "out/animal_anatomy.png"
comptime TILE_W = 320
comptime TILE_H = 240
comptime FRAMES = 10
comptime DELAY_MS = 100
comptime SEED = 3
comptime BACKGROUND = Color(170, 190, 215)


def scene_of(
    var meshes: List[BufferGeometry],
    materials: List[List[Material]],
    floor_y: Float32,
    reach: Float32,
    mut assets: Assets,
) raises -> Scene:
    """Light a few meshes on a floor.

    Args:
        meshes: The meshes.
        materials: Each mesh's materials.
        floor_y: The floor's height.
        reach: The animal's largest extent, in meters.
        assets: Where the meshes and materials go.

    Returns:
        The scene.

    Raises:
        Error: If a mesh or a material is refused.
    """
    var scene = Scene()
    var body = scene.add(Object3D())
    for i in range(len(materials)):
        var shape = assets.geometries.add(meshes.pop(0))
        var ids = List[MaterialId]()
        for m in materials[i]:
            ids.append(assets.materials.add(m.copy()))
        scene.add_mesh(Mesh(shape, ids, body))
    var floor_size = Length(reach * 12.0, METER)
    var ground = assets.geometries.add(plane(floor_size, floor_size))
    var soil = assets.materials.add(Material(Color(128, 122, 110)))
    var floor = Object3D()
    floor.rotate_x(Angle(-90.0, DEGREE))
    floor.set_position(0, floor_y, 0)
    scene.add_mesh(Mesh(ground, soil, scene.add(floor^)))
    var lamp = Object3D()
    lamp.set_position(reach * 2.0, reach * 4.0, reach * 2.6)
    scene.add_light(
        directional_light(Color(255, 243, 228), scene.add(lamp^), 2.3)
    )
    var sky = Object3D()
    sky.set_position(0, 10, 0)
    scene.add_light(
        hemisphere_light(
            Color(221, 230, 242), Color(95, 90, 82), scene.add(sky^), 1.15
        )
    )
    return scene^


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var names: List[String] = ["horse", "dog", "cheetah"]
    var renderer = Renderer(TILE_W, TILE_H, workers=available_workers())
    renderer.set_background(BACKGROUND)
    var sheets = List[Framebuffer]()
    for _ in range(FRAMES):
        sheets.append(Framebuffer(TILE_W * 2, TILE_H * len(names), BACKGROUND))
    for row in range(len(names)):
        var id = species_of(names[row])
        var body = species_body(id)
        var cal = calibrate(id, Variant(-1), allow_estimates=True)
        var base = create_animal(
            id,
            animal_options(
                SEED,
                quality=MEDIUM,
                sex=MALE,
                age=ADULT,
                variant=Variant(max(body.variant, 0)),
            ),
        )
        var real = calibrated_animal(base, cal)
        var mass = calibrated_mass(base, cal)
        var total = mass.total()
        var muscles = species_muscles(real.rig, id, total.mass)
        var hip = Length(Float32(real.rig.j("hipL").y), METER)
        var f = stride_frequency(WALK_FROUDE, hip)
        print(species_name(id), "-", body.kind)
        print(
            "  mass",
            total.mass.value,
            "kg; center of mass",
            total.center.y,
            "m up; reference walk",
            speed_at(WALK_FROUDE, hip).value,
            "m/s, stride",
            stride_length(WALK_FROUDE, hip).value,
            "m at",
            f.value,
            "Hz",
        )
        var visual_stride = walk_stride(real.rig)
        print(
            "  reach-limited visual stride",
            visual_stride.value,
            "m; equivalent translation speed",
            visual_stride.value * f.value,
            "m/s (in-place illustration)",
        )
        for load in standing_loads(real, mass, muscles):
            print(
                "  ",
                load.joint,
                "moment",
                load.moment.value,
                "N m; EMA",
                load.advantage,
                "; activation",
                load.activation,
                "; held" if load.held else "; passive",
            )
        var reach = Float32(0)
        var center = Vector3(0, 0, 0)
        var floor_y = Float32(0)
        for frame in range(FRAMES):
            var elapsed = Duration(Float32(frame * DELAY_MS) / 1000.0, SECOND)
            var pose = walk_pose_at(real.rig, elapsed)
            var game = mesh_animal(flexed_animal(real, muscles, pose), pose)
            if frame == 0:
                var box = game.bounding_box()
                var size = box.max - box.min
                center = (box.max + box.min) * 0.5
                reach = max3(size.x, size.y, size.z)
                floor_y = box.min.y
            var layers = anatomy_layers(real, muscles, pose)
            var camera = gallery_camera(
                TILE_W,
                TILE_H,
                center + Vector3(1.35, 0.25, 0.35) * (reach * 1.4),
                center,
                field_of_view=Angle(30.0, DEGREE),
                near=Length(reach * 0.05, METER),
                far=Length(reach * 30.0, METER),
            )
            var assets = Assets()
            var game_meshes: List[BufferGeometry] = [game^]
            var game_scene = scene_of(
                game_meshes^, [animal_materials()], floor_y, reach, assets
            )
            game_scene.update()
            blit(
                sheets[frame],
                renderer.render(game_scene, assets, camera),
                0,
                row * TILE_H,
            )
            var look = anatomy_materials()
            var inner = Assets()
            # The skin last, so the translucent layer draws over the rest.
            var skin = layers.pop(SKIN_LAYER)
            layers.append(skin^)
            var engineering = scene_of(
                layers^,
                [
                    [look[BONE_LAYER].copy()],
                    [look[MUSCLE_LAYER].copy()],
                    [look[SKIN_LAYER].copy()],
                ],
                floor_y,
                reach,
                inner,
            )
            engineering.update()
            blit(
                sheets[frame],
                renderer.render(engineering, inner, camera),
                TILE_W,
                row * TILE_H,
            )
    # The species have different periods. Play this shared-time clip once
    # instead of jumping every species back to phase zero at a loop seam.
    Path(destination).write_bytes(encode(sheets, delay_ms=DELAY_MS, plays=1))
    print("Wrote", destination)
