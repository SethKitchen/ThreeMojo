# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Both stature-scaled legs, turning under a lamp.

    mojo run -I . examples/legs.mojo [path.png]

The page is Leg. A six-foot male stands on both legs. Femoral heads sit
at plus and minus ten centimeters. Each leg carries bones, knee tissues
and skeletal muscles.
"""

from examples.output import (
    example_destination,
    gallery_camera,
    gallery_renderer,
    spin_gallery,
    warm_lamp,
)

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_albedo, bone_phong
from extensions.humanoid.skeleton.leg.assembly import add_leg, assemble_leg
from extensions.humanoid.skeleton.leg.contents import BOTH
from extensions.humanoid.skeleton.look import (
    cartilage_phong,
    ligament_phong,
    meniscus_phong,
    muscle_albedo,
    muscle_phong,
    tendon_phong,
)
from math.vector3 import Vector3
from render.framebuffer import Color
from units.si import Angle, DEGREE, FOOT, Length, METER

comptime DEFAULT_OUTPUT = "out/legs.png"
comptime WIDTH = 320
comptime HEIGHT = 240
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DETAIL = 12
comptime HIP_HALF = Float32(0.10)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(18, 16, 14))

    var assets = Assets()
    var map = assets.textures.add(bone_albedo(64))
    var muscle_map = assets.textures.add(muscle_albedo(64))
    var bone_paint = assets.materials.add(bone_phong(map))
    var cartilage_paint = assets.materials.add(cartilage_phong())
    var meniscus_paint = assets.materials.add(meniscus_phong())
    var ligament_paint = assets.materials.add(ligament_phong())
    var muscle_paint = assets.materials.add(muscle_phong(muscle_map))
    var tendon_paint = assets.materials.add(tendon_phong())

    var scene = Scene()
    var pivot = scene.add(Object3D())

    var right_pose = assemble_leg(person, RIGHT)
    var right_hip = right_pose.hip_center()
    var right_holder = Object3D()
    right_holder.set_position(HIP_HALF - right_hip.x, 0, 0)
    var right_parent = scene.attach(right_holder^, pivot)
    _ = add_leg(
        scene,
        assets,
        right_parent,
        person,
        bone_paint,
        cartilage_paint,
        meniscus_paint,
        ligament_paint,
        muscle_paint,
        tendon_paint,
        RIGHT,
        BOTH,
        DETAIL,
    )

    var left_pose = assemble_leg(person, LEFT)
    var left_hip = left_pose.hip_center()
    var left_holder = Object3D()
    left_holder.set_position(-HIP_HALF - left_hip.x, 0, 0)
    var left_parent = scene.attach(left_holder^, pivot)
    _ = add_leg(
        scene,
        assets,
        left_parent,
        person,
        bone_paint,
        cartilage_paint,
        meniscus_paint,
        ligament_paint,
        muscle_paint,
        tendon_paint,
        LEFT,
        BOTH,
        DETAIL,
    )

    warm_lamp(scene, 0.65, 0.70, 1.2)
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0.24, 0.06, 2.55),
        Vector3(0.0, 0.02, 0.0),
        field_of_view=Angle(34.0, DEGREE),
        far=Length(20.0, METER),
    )

    spin_gallery(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
