# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One connected stature-scaled leg, with bones and vessels.

    mojo run -I . examples/vessels.mojo [path.png]

The page is Vessels. A six-foot male right leg stands with bones, knee
tissues, arteries and veins.
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
from extensions.humanoid.skeleton.bone import bone_albedo, bone_phong
from extensions.humanoid.skeleton.leg.assembly import add_leg
from extensions.humanoid.skeleton.leg.contents import BONES, VESSELS
from extensions.humanoid.skeleton.look import (
    artery_phong,
    cartilage_phong,
    ligament_phong,
    meniscus_phong,
    muscle_phong,
    tendon_phong,
    vein_phong,
)
from math.vector3 import Vector3
from render.framebuffer import Color
from units.si import Angle, DEGREE, FOOT, Length, METER

comptime DEFAULT_OUTPUT = "out/vessels.png"
comptime WIDTH = 320
comptime HEIGHT = 240
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DETAIL = 12


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
    var artery_paint = assets.materials.add(artery_phong())
    var vein_paint = assets.materials.add(vein_phong())

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
        contents=BONES.plus(VESSELS),
        detail=DETAIL,
        artery_paint=artery_paint,
        vein_paint=vein_paint,
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
