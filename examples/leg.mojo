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

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
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
    muscle_phong,
    tendon_phong,
)
from lights.light import ambient_light, directional_light
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
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


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the leg by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        node: The parent of the leg.
        step: How much further to turn this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(node).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def _print_mass(label: String, grams: Float32, newtons: Float32, lbf: Float32):
    """Print one tissue mass line."""
    print(label, "-", grams, "g,", newtons, "N,", lbf, "lbf on Earth")


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

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

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(18, 16, 14))

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
        detail=DETAIL,
    )

    var lamp = Object3D()
    lamp.set_position(0.55, 0.65, 1.1)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 248, 235), 0.52))
    scene.add_light(directional_light(Color(255, 244, 220), lamp_node, 2.55))

    var camera = PerspectiveCamera(
        Angle(32.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.42, 0.12, 1.85), Vector3(0.0, 0.04, 0.0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, pivot, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
