# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A hand and its fingers, with skin and without it, in a lit studio.

    mojo run -I . examples/hand.mojo [path.png] [quality]

The page is Hand. A six-foot male right hand hangs twice, each turning
about its own length. The left copy shows the bones, the joint tissues,
the hand's muscles and the long tendons to the fingers. The right copy
shows the skin and the hair. The program also prints the mass of
several hand parts.

The optional second argument is the mesh quality: `low`, `medium`,
`high` or `xhigh`. Each level has about twice the triangles of the
level below it. The default is `xhigh`.
"""

from examples.output import (
    example_destination,
    hang_centered,
    spin_pair_gallery,
)
from examples.studio import (
    cast_received_shadows,
    room_lit_scene,
    studio_floor,
    studio_renderer,
    studio_sun,
    tissue_materials,
)

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.quality import (
    anatomy_detail,
    hand_skin_detail,
    quality_named,
    triangle_budget,
)
from extensions.humanoid.skeleton.simplify import (
    fit_triangle_budget,
)
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.arm.frame import arm_dimensions
from extensions.humanoid.skeleton.hand.assembly import add_hand
from extensions.humanoid.skeleton.hand.bones.dimensions import (
    CAPITATE,
    METACARPAL_1,
    PROXIMAL_PHALANX_3,
)
from extensions.humanoid.skeleton.hand.bones.mass import hand_bone_mass
from extensions.humanoid.skeleton.hand.contents import BOTH, HAIR, SKIN
from extensions.humanoid.skeleton.hand.muscles.dimensions import (
    ADDUCTOR_POLLICIS,
    DORSAL_INTEROSSEI,
    FLEXOR_TENDONS,
)
from extensions.humanoid.skeleton.hand.muscles.mass import hand_muscle_mass
from extensions.humanoid.skeleton.look import (
    hair_phong,
    skin_albedo,
    skin_physical,
)
from math.vector3 import Vector3
from renderers.renderer import available_workers
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, GRAM, Length, METER

comptime DEFAULT_OUTPUT = "out/hand.png"
comptime WIDTH = 640
comptime HEIGHT = 360
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DEFAULT_QUALITY = "xhigh"
comptime SPACING = Float32(0.09)


def main() raises:
    var args = argv()
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var level = quality_named(String(DEFAULT_QUALITY))
    if len(args) > 2:
        level = quality_named(String(args[2]))
    var budget = triangle_budget(level)
    var detail = anatomy_detail(level)
    var hand_covering = hand_skin_detail(level)

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    print("Hand tissue for a six-foot toned male:")
    print("  capitate", hand_bone_mass(person, CAPITATE).mass.to(GRAM), "g")
    print(
        "  first metacarpal",
        hand_bone_mass(person, METACARPAL_1).mass.to(GRAM),
        "g",
    )
    print(
        "  middle finger's proximal phalanx",
        hand_bone_mass(person, PROXIMAL_PHALANX_3).mass.to(GRAM),
        "g",
    )
    print(
        "  adductor pollicis",
        hand_muscle_mass(person, ADDUCTOR_POLLICIS).mass.to(GRAM),
        "g",
    )
    print(
        "  dorsal interossei",
        hand_muscle_mass(person, DORSAL_INTEROSSEI).mass.to(GRAM),
        "g",
    )
    print(
        "  flexor tendons",
        hand_muscle_mass(person, FLEXOR_TENDONS).mass.to(GRAM),
        "g",
    )

    var renderer = studio_renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var paints = tissue_materials(assets)
    var bone = paints.bone
    var cartilage = paints.cartilage
    var ligament = paints.ligament
    var muscle = paints.muscle
    var tendon = paints.tendon
    var skin = assets.materials.add(
        skin_physical(assets.textures.add(skin_albedo(64)))
    )
    var hair = assets.materials.add(hair_phong())
    var scene = room_lit_scene(renderer, assets)

    # The hand's middle: halfway from the wrist to the fingertips.
    var f = arm_dimensions(person.stature, person.sex).frame
    var center = f.hand(0.4, -10, 0.8)
    var height = Float32(0.9)
    var first = len(scene.meshes)
    var anatomy = hang_centered(scene, -SPACING, height, center)
    _ = add_hand(
        scene,
        assets,
        anatomy[1],
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        RIGHT,
        BOTH,
        detail,
        tendon_paint=tendon,
    )
    fit_triangle_budget(scene, assets, first, budget, available_workers())
    first = len(scene.meshes)
    var covered = hang_centered(scene, SPACING, height, center)
    _ = add_hand(
        scene,
        assets,
        covered[1],
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        RIGHT,
        SKIN.plus(HAIR),
        detail,
        hand_covering,
        skin_paint=skin,
        hair_paint=hair,
    )
    fit_triangle_budget(scene, assets, first, budget, available_workers())
    cast_received_shadows(scene)
    studio_floor(scene, assets, Length(12.0, METER))
    studio_sun(scene, 1.2, 2.2, 2.0, Length(0.6, METER))

    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(30.0, METER),
    )
    camera.place(Vector3(0.0, 0.94, 0.62), Vector3(0.0, 0.9, 0.0))

    spin_pair_gallery(
        renderer,
        camera,
        assets,
        scene,
        anatomy[0],
        covered[0],
        FRAMES,
        DELAY_MS,
        destination,
    )
