# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An arm and its hand, with skin and without it, in a lit studio.

    mojo run -I . examples/arm.mojo [path.png] [quality]

The page is Arm. A six-foot male right arm and hand hang twice, each
turning about its own length. The left copy shows the bones, the joint
tissues and the muscles, and the clavicle and the scapula the arm hangs
from. The right copy shows the skin and the hair. The program also
prints the mass of several arm parts.

The optional second argument is the mesh quality: `low`, `medium`,
`high` or `xhigh`. Each level has about twice the triangles of the
level below it. The default is `xhigh`.
"""

from examples.output import (
    example_destination,
    gallery_camera,
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

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.quality import (
    anatomy_detail,
    hand_skin_detail,
    quality_named,
    skin_detail,
    triangle_budget,
)
from extensions.humanoid.skeleton.simplify import (
    fit_triangle_budget,
)
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import RIGHT
from extensions.humanoid.skeleton.arm.assembly import place_mesh
from extensions.humanoid.skeleton.arm.bones.dimensions import (
    HUMERUS,
    RADIUS,
    ULNA,
)
from extensions.humanoid.skeleton.arm.bones.mass import arm_bone_mass
from extensions.humanoid.skeleton.arm.contents import BOTH, HAIR, SKIN
from extensions.humanoid.skeleton.arm.frame import arm_dimensions
from extensions.humanoid.skeleton.arm.limb import add_upper_limb
from extensions.humanoid.skeleton.arm.muscles.dimensions import (
    BICEPS_BRACHII,
    DELTOID,
    TRICEPS_BRACHII,
)
from extensions.humanoid.skeleton.arm.muscles.mass import arm_muscle_mass
from extensions.humanoid.skeleton.look import (
    hair_phong,
    skin_albedo,
    skin_physical,
)
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    CLAVICLE,
    SCAPULA,
    torso_dimensions,
)
from extensions.humanoid.skeleton.torso.bones.geometry import (
    torso_bone_from_dimensions,
)
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from renderers.renderer import available_workers
from std.sys import argv
from units.si import FOOT, GRAM, Length, METER

comptime DEFAULT_OUTPUT = "out/arm.png"
comptime WIDTH = 640
comptime HEIGHT = 360
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DEFAULT_QUALITY = "xhigh"
comptime SPACING = Float32(0.22)


def main() raises:
    var args = argv()
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var level = quality_named(String(DEFAULT_QUALITY))
    if len(args) > 2:
        level = quality_named(String(args[2]))
    var budget = triangle_budget(level)
    var detail = anatomy_detail(level)
    var covering = skin_detail(level)
    var hand_covering = hand_skin_detail(level)

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    print("Arm tissue for a six-foot toned male:")
    print("  humerus", arm_bone_mass(person, HUMERUS).mass.to(GRAM), "g")
    print("  radius", arm_bone_mass(person, RADIUS).mass.to(GRAM), "g")
    print("  ulna", arm_bone_mass(person, ULNA).mass.to(GRAM), "g")
    print("  deltoid", arm_muscle_mass(person, DELTOID).mass.to(GRAM), "g")
    print(
        "  biceps brachii",
        arm_muscle_mass(person, BICEPS_BRACHII).mass.to(GRAM),
        "g",
    )
    print(
        "  triceps brachii",
        arm_muscle_mass(person, TRICEPS_BRACHII).mass.to(GRAM),
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

    # The arm's middle: halfway from the shoulder to the fingertips.
    var f = arm_dimensions(person.stature, person.sex).frame
    var tip = f.hand(0, -20, 0)
    var center = (f.shoulder + tip) * Float32(0.5)
    var height = Float32(0.62)
    var first = len(scene.meshes)
    var anatomy = hang_centered(scene, -SPACING, height, center)
    _ = add_upper_limb(
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
    # The clavicle and the scapula the arm hangs from.
    var torso = torso_dimensions(person.stature, person.sex)
    _ = place_mesh(
        scene,
        assets,
        anatomy[1],
        torso_bone_from_dimensions(torso, CLAVICLE, RIGHT, detail),
        bone,
    )
    _ = place_mesh(
        scene,
        assets,
        anatomy[1],
        torso_bone_from_dimensions(torso, SCAPULA, RIGHT, detail),
        bone,
    )
    fit_triangle_budget(scene, assets, first, budget, available_workers())
    first = len(scene.meshes)
    var covered = hang_centered(scene, SPACING, height, center)
    _ = add_upper_limb(
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
        covering,
        hand_covering,
        skin_paint=skin,
        hair_paint=hair,
    )
    fit_triangle_budget(scene, assets, first, budget, available_workers())
    cast_received_shadows(scene)
    studio_floor(scene, assets, Length(12.0, METER))
    studio_sun(scene, 1.2, 2.2, 2.0, Length(1.2, METER))

    var camera = gallery_camera(
        WIDTH, HEIGHT, Vector3(0.0, 0.66, 2.1), Vector3(0.0, 0.6, 0.0)
    )

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
