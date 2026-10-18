# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A whole body, with skin and without it, in a lit studio.

    mojo run -I . examples/torso.mojo [path.png] [quality]

The page is Torso. A six-foot male stands twice on a floor. The left
copy shows the bones, the joint tissues and the muscles of the torso
and its shoulder girdle, the pelvis, both legs and feet, both arms and
hands, and the neck and the head. The right copy shows one skin from
the head down to the wrists, and each hand's own, with the eyes and
the hair. The program also prints the mass of several torso parts.

The optional second argument is the mesh quality: `low`, `medium`,
`high` or `xhigh`. Each level has about twice the triangles of the
level below it. The default is `high`.
"""

from examples.output import example_destination, spin_frame, stand_on_floor
from examples.studio import (
    cast_received_shadows,
    room_lit_scene,
    studio_floor,
    studio_renderer,
    studio_sun,
    tissue_materials,
)
from examples.preview import turn_about_vertical

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
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
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.look import add_complexion
from extensions.humanoid.skeleton.pelvis.assembly import assemble_pelvis
from extensions.humanoid.skeleton.torso.body import add_body
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    L3,
    RIB_7,
    SCAPULA,
    STERNUM,
)
from extensions.humanoid.skeleton.torso.bones.mass import torso_bone_mass
from extensions.humanoid.skeleton.torso.contents import BOTH, SKIN
from extensions.humanoid.skeleton.torso.muscles.dimensions import (
    DIAPHRAGM,
    ERECTOR_SPINAE,
    PECTORALIS_MAJOR,
)
from extensions.humanoid.skeleton.torso.muscles.mass import torso_muscle_mass
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.strands import add_groom
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Framebuffer
from renderers.renderer import available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, GRAM, Length, METER

comptime DEFAULT_OUTPUT = "out/torso.png"
comptime WIDTH = 640
comptime HEIGHT = 360
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DEFAULT_QUALITY = "high"
comptime SPACING = Float32(0.44)


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

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var S = person.stature.value
    print("Torso tissue for a six-foot male:")
    print("  L3", torso_bone_mass(person, L3).mass.to(GRAM), "g")
    print("  seventh rib", torso_bone_mass(person, RIB_7).mass.to(GRAM), "g")
    print("  sternum", torso_bone_mass(person, STERNUM).mass.to(GRAM), "g")
    print("  scapula", torso_bone_mass(person, SCAPULA).mass.to(GRAM), "g")
    print(
        "  erector spinae",
        torso_muscle_mass(person, ERECTOR_SPINAE).mass.to(GRAM),
        "g",
    )
    print(
        "  pectoralis major",
        torso_muscle_mass(person, PECTORALIS_MAJOR).mass.to(GRAM),
        "g",
    )
    print(
        "  diaphragm", torso_muscle_mass(person, DIAPHRAGM).mass.to(GRAM), "g"
    )

    var renderer = studio_renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var paints = tissue_materials(assets)
    var bone = paints.bone
    var cartilage = paints.cartilage
    var ligament = paints.ligament
    var muscle = paints.muscle
    var tendon = paints.tendon
    var looks = add_complexion(assets, person.genome, whole_body=True)
    var scene = room_lit_scene(renderer, assets)

    # The soles' height below the hip joint centers: the leg's origin,
    # its plafond, and the foot's ankle height.
    var pose = assemble_pelvis(person)
    var leg = assemble_leg(person, RIGHT)
    var ground = -(
        pose.leg_origin(RIGHT).y + leg.ankle_center().y - Float32(0.048) * S
    )
    var pivot = scene.add(Object3D())
    var first = len(scene.meshes)
    var anatomy = stand_on_floor(scene, pivot, -SPACING, ground)
    _ = add_body(
        scene,
        assets,
        anatomy,
        person,
        bone,
        cartilage,
        cartilage,
        ligament,
        muscle,
        tendon,
        BOTH,
        detail,
    )
    fit_triangle_budget(scene, assets, first, budget, available_workers())
    var covered = stand_on_floor(scene, pivot, SPACING, ground)
    _ = add_body(
        scene,
        assets,
        covered,
        person,
        bone,
        cartilage,
        cartilage,
        ligament,
        muscle,
        tendon,
        SKIN,
        detail,
        covering,
        hand_covering,
        skin_paint=looks.skin,
        hair_paint=looks.hair,
        eye_paint=looks.eyes,
        workers=available_workers(),
    )
    # The scalp's hair as strands, over the mass of it in shade.
    var hair = add_groom(scene, assets, covered, person, 1200, 5)
    # The skin is meshed smooth and lean already, and carries the face's
    # colors, which decimation would drop: only the anatomy is fitted to
    # the budget.
    cast_received_shadows(scene)
    studio_floor(scene, assets, Length(12.0, METER))
    studio_sun(scene, 1.4, 2.6, 2.2, Length(1.8, METER))

    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(30.0, METER),
    )
    camera.place(Vector3(0.0, 1.05, 5.3), Vector3(0.0, 0.88, 0.0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    # The lamp as the hair sees it, and the camera.
    var toward = Vector3(1.4, 2.6, 2.2)
    toward.normalize()
    var eye = Vector3(0.0, 1.05, 5.3)
    var turned = Float32(0)
    for _ in range(FRAMES):
        # The frame turns the bodies by `step`: carry the camera and the
        # lamp into the covered body's own frame, as it will stand.
        turned += step.value
        var lights = List[HairLight]()
        lights.append(
            HairLight(
                turn_about_vertical(toward, -turned), Vector3(2.2, 1.97, 1.72)
            )
        )
        var camera_at = turn_about_vertical(eye, -turned) - Vector3(
            SPACING, ground, 0
        )
        hair.shade(assets, lights, camera_at, Vector3(0.11, 0.11, 0.12))
        frames.append(spin_frame(renderer, camera, assets, scene, pivot, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
