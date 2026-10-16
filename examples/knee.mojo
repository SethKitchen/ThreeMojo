# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A close view of one connected knee, turning under a lamp.

    mojo run -I . examples/knee.mojo [path.png]

The page is Knee. A six-foot male right knee shows articular cartilage,
both menisci and both collateral ligaments on the assembled bones.
"""

from examples.output import (
    example_destination,
    fill_and_key,
    gallery_camera,
    gallery_renderer,
    spin_gallery,
)

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_albedo, bone_phong
from extensions.humanoid.skeleton.leg.assembly import add_leg
from extensions.humanoid.skeleton.leg.contents import BONES
from extensions.humanoid.skeleton.look import (
    cartilage_phong,
    ligament_phong,
    meniscus_phong,
    muscle_phong,
    tendon_phong,
)
from math.vector3 import Vector3
from render.framebuffer import Color
from units.si import Angle, DEGREE, FOOT, Length, METER

comptime DEFAULT_OUTPUT = "out/knee.png"
comptime WIDTH = 320
comptime HEIGHT = 240
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DETAIL = 20


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(18, 16, 14))

    var assets = Assets()
    var map = assets.textures.add(bone_albedo(64))
    var bone_paint = assets.materials.add(bone_phong(map))
    var cartilage_paint = assets.materials.add(cartilage_phong())
    var meniscus_paint = assets.materials.add(meniscus_phong())
    var ligament_paint = assets.materials.add(ligament_phong())
    var muscle_paint = assets.materials.add(muscle_phong())
    var tendon_paint = assets.materials.add(tendon_phong())

    var scene = Scene()
    var pivot = scene.add(Object3D())
    _ = add_leg(
        scene,
        assets,
        pivot,
        person,
        bone_paint,
        cartilage_paint,
        meniscus_paint,
        ligament_paint,
        muscle_paint,
        tendon_paint,
        contents=BONES,
        detail=DETAIL,
    )

    fill_and_key(
        scene,
        0.22,
        0.18,
        0.35,
        Color(255, 248, 235),
        0.55,
        Color(255, 244, 220),
        2.70,
    )

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0.04, 0.04, 0.28),
        Vector3(0.0, 0.0, 0.01),
        field_of_view=Angle(38.0, DEGREE),
        near=Length(0.02, METER),
        far=Length(8.0, METER),
    )

    spin_gallery(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
