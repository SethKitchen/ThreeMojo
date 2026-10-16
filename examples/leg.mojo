# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One connected stature-scaled leg, turning under a lamp.

    mojo run -I . examples/leg.mojo [path.png]

The page is Leg. A six-foot male right leg stands with bones, knee
tissues and skeletal muscles. The program also prints tissue mass and
Earth weight.
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
from extensions.humanoid.skeleton.leg.femur.mass import femur_mass
from extensions.humanoid.skeleton.leg.fibula.mass import fibula_mass
from extensions.humanoid.skeleton.leg.knee.mass import (
    articular_cartilage_mass,
    lateral_collateral_mass,
    lateral_meniscus_mass,
    medial_collateral_mass,
    medial_meniscus_mass,
)
from extensions.humanoid.skeleton.leg.patella.mass import patella_mass
from extensions.humanoid.skeleton.leg.tibia.mass import tibia_mass
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

comptime DEFAULT_OUTPUT = "out/leg.png"
comptime WIDTH = 320
comptime HEIGHT = 240
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DETAIL = 12


def _print_mass(label: String, grams: Float32, newtons: Float32, lbf: Float32):
    """Print one tissue mass line."""
    print(label, "-", grams, "g,", newtons, "N,", lbf, "lbf on Earth")


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var femur_report = femur_mass(person)
    _print_mass(
        "femur",
        femur_report.mass.to(GRAM),
        femur_report.weight().to(NEWTON),
        femur_report.weight().to(POUND_FORCE),
    )
    var tibia_report = tibia_mass(person)
    _print_mass(
        "tibia",
        tibia_report.mass.to(GRAM),
        tibia_report.weight().to(NEWTON),
        tibia_report.weight().to(POUND_FORCE),
    )
    var fibula_report = fibula_mass(person)
    _print_mass(
        "fibula",
        fibula_report.mass.to(GRAM),
        fibula_report.weight().to(NEWTON),
        fibula_report.weight().to(POUND_FORCE),
    )
    var patella_report = patella_mass(person)
    _print_mass(
        "patella",
        patella_report.mass.to(GRAM),
        patella_report.weight().to(NEWTON),
        patella_report.weight().to(POUND_FORCE),
    )
    var cartilage_report = articular_cartilage_mass(person)
    _print_mass(
        "articular cartilage",
        cartilage_report.mass.to(GRAM),
        cartilage_report.weight().to(NEWTON),
        cartilage_report.weight().to(POUND_FORCE),
    )
    var med_report = medial_meniscus_mass(person)
    _print_mass(
        "medial meniscus",
        med_report.mass.to(GRAM),
        med_report.weight().to(NEWTON),
        med_report.weight().to(POUND_FORCE),
    )
    var lat_report = lateral_meniscus_mass(person)
    _print_mass(
        "lateral meniscus",
        lat_report.mass.to(GRAM),
        lat_report.weight().to(NEWTON),
        lat_report.weight().to(POUND_FORCE),
    )
    var mcl_report = medial_collateral_mass(person)
    _print_mass(
        "MCL",
        mcl_report.mass.to(GRAM),
        mcl_report.weight().to(NEWTON),
        mcl_report.weight().to(POUND_FORCE),
    )
    var lcl_report = lateral_collateral_mass(person)
    _print_mass(
        "LCL",
        lcl_report.mass.to(GRAM),
        lcl_report.weight().to(NEWTON),
        lcl_report.weight().to(POUND_FORCE),
    )

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
        detail=DETAIL,
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
