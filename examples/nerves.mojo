# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One connected stature-scaled leg, with bones and nerves.

    mojo run -I . examples/nerves.mojo [path.png]

The page is Nerves. A six-foot male right leg stands with bones, knee
tissues and the named peripheral nerves.
"""

from examples.output import example_destination, spin_gallery

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_albedo, bone_phong
from extensions.humanoid.skeleton.leg.assembly import add_leg
from extensions.humanoid.skeleton.leg.contents import BONES, NERVES
from extensions.humanoid.skeleton.look import (
    cartilage_phong,
    ligament_phong,
    meniscus_phong,
    muscle_phong,
    nerve_phong,
    tendon_phong,
)
from lights.light import ambient_light, directional_light
from math.vector3 import Vector3
from render.framebuffer import Color
from renderers.renderer import Renderer, available_workers
from units.si import Angle, DEGREE, FOOT, Length, METER

comptime DEFAULT_OUTPUT = "out/nerves.png"
comptime WIDTH = 320
comptime HEIGHT = 240
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DETAIL = 12


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
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
    var nerve_paint = assets.materials.add(nerve_phong())

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
        contents=BONES.plus(NERVES),
        detail=DETAIL,
        nerve_paint=nerve_paint,
    )

    var lamp = Object3D()
    lamp.set_position(0.55, 0.65, 1.1)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 248, 235), 0.52))
    scene.add_light(directional_light(Color(255, 244, 220), lamp_node, 2.55))

    var camera = PerspectiveCamera(
        Angle(36.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.35, 0.06, 2.45), Vector3(0.0, 0.02, 0.0))

    spin_gallery(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
