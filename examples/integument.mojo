# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One connected stature-scaled leg, as skin and hair.

    mojo run -I . examples/integument.mojo [path.png]

The page is Integument. A six-foot male right leg stands as a skin
envelope with short thigh and calf hair.
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
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_phong
from extensions.humanoid.skeleton.leg.assembly import add_leg
from extensions.humanoid.skeleton.leg.contents import INTEGUMENT
from extensions.humanoid.skeleton.look import (
    cartilage_phong,
    hair_phong,
    ligament_phong,
    meniscus_phong,
    muscle_phong,
    skin_albedo,
    skin_phong,
    tendon_phong,
)
from math.vector3 import Vector3
from render.framebuffer import Color
from units.si import Angle, DEGREE, FOOT, Length, METER

comptime DEFAULT_OUTPUT = "out/integument.png"
comptime WIDTH = 320
comptime HEIGHT = 240
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DETAIL = 16


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(18, 16, 14))

    var assets = Assets()
    var skin_map = assets.textures.add(skin_albedo(64))
    var bone_paint = assets.materials.add(bone_phong())
    var cartilage_paint = assets.materials.add(cartilage_phong())
    var meniscus_paint = assets.materials.add(meniscus_phong())
    var ligament_paint = assets.materials.add(ligament_phong())
    var muscle_paint = assets.materials.add(muscle_phong())
    var tendon_paint = assets.materials.add(tendon_phong())
    var dermis = assets.materials.add(skin_phong(skin_map))
    var keratin = assets.materials.add(hair_phong())

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
        contents=INTEGUMENT,
        detail=DETAIL,
        skin_paint=dermis,
        hair_paint=keratin,
    )

    warm_lamp(scene, 0.55, 0.65, 1.1)
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0.35, 0.06, 2.45),
        Vector3(0.0, 0.02, 0.0),
        field_of_view=Angle(36.0, DEGREE),
        far=Length(20.0, METER),
    )

    spin_gallery(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
