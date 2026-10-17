# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A neck and a head, with skin and without it, in a lit studio.

    mojo run -I . examples/head.mojo [path.png] [quality]

The page is Head. A six-foot male neck and head stand twice, each
turning about its own axis. The left copy shows the cervical vertebrae,
the skull, the mandible, the teeth and the hyoid, the joint tissues and
the cartilages of the larynx, and the muscles of the neck, the jaw and
the face. The right copy shows the skin, the hair and the eyes. The program also
prints the mass of several head parts.

The optional second argument is the mesh quality: `low`, `medium`,
`high` or `xhigh`. Each level has about twice the triangles of the
level below it. The default is `xhigh`.
"""

from tools._example_output import (
    example_destination,
    gallery_camera,
    hang_centered,
    spin_pair,
)
from tools._example_studio import (
    cast_received_shadows,
    room_lit_scene,
    studio_floor,
    studio_renderer,
    studio_sun,
)
from tools._example_preview import turn_about_vertical

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.quality import (
    anatomy_detail,
    quality_named,
    skin_detail,
    triangle_budget,
)
from extensions.humanoid.skeleton.simplify import (
    fit_triangle_budget,
)
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.head.assembly import add_head
from extensions.humanoid.skeleton.head.bones.dimensions import (
    C2,
    MANDIBLE,
    SKULL,
)
from extensions.humanoid.skeleton.head.bones.mass import head_bone_mass
from extensions.humanoid.skeleton.head.contents import BOTH, EYES, HAIR, SKIN
from extensions.humanoid.skeleton.head.frame import head_dimensions
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.strands import add_groom
from extensions.humanoid.skeleton.head.muscles.dimensions import (
    MASSETER,
    STERNOCLEIDOMASTOID,
    TEMPORALIS,
)
from extensions.humanoid.skeleton.head.muscles.mass import head_muscle_mass
from extensions.humanoid.skeleton.bone import bone_albedo, bone_physical
from extensions.humanoid.skeleton.look import (
    add_complexion,
    cartilage_physical,
    ligament_physical,
    muscle_albedo,
    muscle_physical,
)
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Framebuffer
from renderers.renderer import available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, GRAM, Length, METER

comptime DEFAULT_OUTPUT = "out/head.png"
comptime WIDTH = 640
comptime HEIGHT = 360
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DEFAULT_QUALITY = "xhigh"
comptime SPACING = Float32(0.16)


def main() raises:
    var args = argv()
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var level = quality_named(String(DEFAULT_QUALITY))
    if len(args) > 2:
        level = quality_named(String(args[2]))
    var budget = triangle_budget(level)
    var detail = anatomy_detail(level)
    var covering = skin_detail(level)

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    print("Head tissue for a six-foot toned male:")
    print("  skull", head_bone_mass(person, SKULL).mass.to(GRAM), "g")
    print("  mandible", head_bone_mass(person, MANDIBLE).mass.to(GRAM), "g")
    print("  axis", head_bone_mass(person, C2).mass.to(GRAM), "g")
    print("  masseter", head_muscle_mass(person, MASSETER).mass.to(GRAM), "g")
    print(
        "  temporalis", head_muscle_mass(person, TEMPORALIS).mass.to(GRAM), "g"
    )
    print(
        "  sternocleidomastoid",
        head_muscle_mass(person, STERNOCLEIDOMASTOID).mass.to(GRAM),
        "g",
    )

    var renderer = studio_renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var bone = assets.materials.add(
        bone_physical(assets.textures.add(bone_albedo(64)))
    )
    var cartilage = assets.materials.add(cartilage_physical())
    var ligament = assets.materials.add(ligament_physical())
    var muscle = assets.materials.add(
        muscle_physical(assets.textures.add(muscle_albedo(64)))
    )
    var looks = add_complexion(assets, person.genome)
    var scene = room_lit_scene(renderer, assets)

    # The head's middle: between the ears, a little below the eyes. The
    # floor meets the neck at its base, where the torso would go on.
    var center = head_dimensions(person.stature, person.sex).at(0, 70.0, 0)
    var height = Float32(0.17)
    var first = len(scene.meshes)
    var anatomy = hang_centered(scene, -SPACING, height, center)
    _ = add_head(
        scene,
        assets,
        anatomy[1],
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        BOTH,
        detail,
    )
    fit_triangle_budget(scene, assets, first, budget, available_workers())
    var covered = hang_centered(scene, SPACING, height, center)
    _ = add_head(
        scene,
        assets,
        covered[1],
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        SKIN.plus(HAIR).plus(EYES),
        detail,
        covering,
        skin_paint=looks.skin,
        hair_paint=looks.hair,
        eye_paint=looks.eyes,
        workers=available_workers(),
    )
    # The scalp's hair as strands, over the mass of it in shade.
    var hair = add_groom(scene, assets, covered[1], person, 1500, 6)
    # The skin is meshed smooth and lean already, and carries the face's
    # colors, which decimation would drop: only the anatomy is fitted to
    # the budget.
    cast_received_shadows(scene)
    studio_floor(scene, assets, Length(12.0, METER))
    studio_sun(scene, 1.2, 2.2, 2.0, Length(0.6, METER))

    var camera = gallery_camera(
        WIDTH, HEIGHT, Vector3(0.0, 0.26, 1.05), Vector3(0.0, 0.2, 0.0)
    )

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    # The lamp as the hair sees it, and the camera.
    var toward = Vector3(1.2, 2.2, 2.0)
    toward.normalize()
    var eye = Vector3(0.0, 0.26, 1.05)
    var turned = Float32(0)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        # The frame turns the head by `step`: carry the camera and the
        # lamp into its own frame, as it will stand.
        turned += step.value
        var lights = List[HairLight]()
        lights.append(
            HairLight(
                turn_about_vertical(toward, -turned), Vector3(2.2, 1.97, 1.72)
            )
        )
        var camera_at = (
            turn_about_vertical(eye - Vector3(SPACING, height, 0), -turned)
            + center
        )
        hair.shade(assets, lights, camera_at, Vector3(0.11, 0.11, 0.12))
        frames.append(
            spin_pair(
                renderer, camera, assets, scene, anatomy[0], covered[0], step
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
