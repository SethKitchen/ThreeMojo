# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One connected stature-scaled foot, turning under a lamp.

    mojo run -I . examples/foot.mojo [path.png]

The page is Foot. A six-foot male right foot stands with bones,
ligaments and muscles. The program also prints tissue mass and Earth
weight.
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
from extensions.humanoid.skeleton.foot.assembly import add_foot
from extensions.humanoid.skeleton.foot.bones.dimensions import CALCANEUS
from extensions.humanoid.skeleton.foot.bones.mass import foot_bone_mass
from extensions.humanoid.skeleton.foot.ligaments.dimensions import DELTOID
from extensions.humanoid.skeleton.foot.ligaments.mass import ligament_mass
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    ABDUCTOR_HALLUCIS,
)
from extensions.humanoid.skeleton.foot.muscles.mass import foot_muscle_mass
from extensions.humanoid.skeleton.look import (
    ligament_phong,
    muscle_albedo,
    muscle_phong,
    tendon_phong,
)
from math.vector3 import Vector3
from render.framebuffer import Color
from units.si import (
    Angle,
    DEGREE,
    FOOT,
    GRAM,
    Length,
    METER,
    NEWTON,
    POUND_FORCE,
)

comptime DEFAULT_OUTPUT = "out/foot.png"
comptime WIDTH = 320
comptime HEIGHT = 220
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DETAIL = 8


def _print_mass(label: String, grams: Float32, newtons: Float32, lbf: Float32):
    """Print one tissue mass line."""
    print(label, "-", grams, "g,", newtons, "N,", lbf, "lbf on Earth")


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var bone = foot_bone_mass(person, CALCANEUS)
    _print_mass(
        "calcaneus",
        bone.mass.to(GRAM),
        bone.weight().to(NEWTON),
        bone.weight().to(POUND_FORCE),
    )
    var band = ligament_mass(person, DELTOID)
    _print_mass(
        "deltoid",
        band.mass.to(GRAM),
        band.weight().to(NEWTON),
        band.weight().to(POUND_FORCE),
    )
    var belly = foot_muscle_mass(person, ABDUCTOR_HALLUCIS)
    _print_mass(
        "abductor hallucis",
        belly.mass.to(GRAM),
        belly.weight().to(NEWTON),
        belly.weight().to(POUND_FORCE),
    )

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(18, 16, 14))

    var assets = Assets()
    var map = assets.textures.add(bone_albedo(64))
    var muscle_map = assets.textures.add(muscle_albedo(64))
    var bone_paint = assets.materials.add(bone_phong(map))
    var ligament_paint = assets.materials.add(ligament_phong())
    var muscle_paint = assets.materials.add(muscle_phong(muscle_map))
    var tendon_paint = assets.materials.add(tendon_phong())

    var scene = Scene()
    var pivot = scene.add(Object3D())
    _ = add_foot(
        scene,
        assets,
        pivot,
        person,
        bone_paint,
        ligament_paint,
        muscle_paint,
        tendon_paint,
        detail=DETAIL,
    )

    fill_and_key(
        scene,
        0.28,
        0.22,
        0.36,
        Color(255, 248, 235),
        0.55,
        Color(255, 244, 220),
        2.4,
    )

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0.16, 0.05, 0.38),
        Vector3(0.0, -0.045, 0.04),
        field_of_view=Angle(32.0, DEGREE),
        near=Length(0.02, METER),
        far=Length(8.0, METER),
    )

    spin_gallery(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
