# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A pelvis on two legs, with skin and without it, in a lit studio.

    mojo run -I . examples/pelvis.mojo [path.png] [quality]

The page is Pelvis. A six-foot male lower body stands twice on a floor.
The left copy shows the pelvis's bones, ligaments and muscles, and the
same layers of both legs and feet. The right copy shows one skin over
all of it. The program also prints the mass of several pelvic parts.

The optional second argument is the mesh quality: `low`, `medium`,
`high` or `xhigh`. Each level has about twice the triangles of the
level below it. The default is `high`.
"""

from examples.output import example_destination, spin_gallery, stand_on_floor
from examples.studio import room_lit_scene, studio_renderer, tissue_materials

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
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
from extensions.humanoid.side import RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.look import skin_albedo, skin_physical
from extensions.humanoid.skeleton.pelvis.assembly import assemble_pelvis
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    RIGHT_HIP_BONE,
    SACRUM,
)
from extensions.humanoid.skeleton.pelvis.bones.mass import pelvis_bone_mass
from extensions.humanoid.skeleton.pelvis.contents import BOTH, SKIN
from extensions.humanoid.skeleton.pelvis.ligaments.dimensions import (
    SACROTUBEROUS,
)
from extensions.humanoid.skeleton.pelvis.ligaments.mass import (
    pelvis_ligament_mass,
)
from extensions.humanoid.skeleton.pelvis.lower_body import add_lower_body
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    ILIACUS,
    PIRIFORMIS,
    PSOAS_MAJOR,
)
from extensions.humanoid.skeleton.pelvis.muscles.mass import (
    pelvis_muscle_mass,
)
from geometries.plane import plane
from lights.light import directional_light
from materials.material import standard_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import available_workers
from std.sys import argv
from units.si import Angle, DEGREE, FOOT, GRAM, Length, METER

comptime DEFAULT_OUTPUT = "out/pelvis.png"
comptime WIDTH = 640
comptime HEIGHT = 360
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DEFAULT_QUALITY = "high"
comptime SPACING = Float32(0.30)


def main() raises:
    var args = argv()
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var level = quality_named(String(DEFAULT_QUALITY))
    if len(args) > 2:
        level = quality_named(String(args[2]))
    var budget = triangle_budget(level)
    var detail = anatomy_detail(level)
    var covering = skin_detail(level)

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var S = person.stature.value
    print("Pelvic tissue for a six-foot male:")
    print(
        "  right hip bone",
        pelvis_bone_mass(person, RIGHT_HIP_BONE).mass.to(GRAM),
        "g",
    )
    print("  sacrum", pelvis_bone_mass(person, SACRUM).mass.to(GRAM), "g")
    print("  iliacus", pelvis_muscle_mass(person, ILIACUS).mass.to(GRAM), "g")
    print(
        "  psoas major",
        pelvis_muscle_mass(person, PSOAS_MAJOR).mass.to(GRAM),
        "g",
    )
    print(
        "  piriformis",
        pelvis_muscle_mass(person, PIRIFORMIS).mass.to(GRAM),
        "g",
    )
    print(
        "  sacrotuberous ligament",
        pelvis_ligament_mass(person, SACROTUBEROUS).mass.to(GRAM),
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
    _ = add_lower_body(
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
    first = len(scene.meshes)
    var covered = stand_on_floor(scene, pivot, SPACING, ground)
    _ = add_lower_body(
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
        skin_paint=skin,
    )
    fit_triangle_budget(scene, assets, first, budget, available_workers())
    for index in range(len(scene.meshes)):
        scene.meshes[index].cast_shadow = True
        scene.meshes[index].receive_shadow = True

    var floor = Object3D()
    floor.rotate_x(Angle(-90.0, DEGREE))
    var ground_shape = assets.geometries.add(
        plane(Length(6.0, METER), Length(6.0, METER))
    )
    var ground_look = assets.materials.add(
        standard_material(Color(92, 90, 86), roughness=0.85)
    )
    scene.add_mesh(
        Mesh(ground_shape, ground_look, scene.add(floor^), receive_shadow=True)
    )

    var lamp = Object3D()
    lamp.set_position(1.4, 2.6, 2.2)
    var lamp_node = scene.add(lamp^)
    var sun = directional_light(Color(255, 244, 228), lamp_node, 2.2)
    sun.cast_shadow = True
    sun.shadow.map_size = 1024
    sun.shadow.bias = -0.0005
    sun.shadow.normal_bias = 0.01
    sun.shadow.set_extent(Length(1.4, METER))
    sun.shadow.near = Length(0.5, METER)
    sun.shadow.far = Length(8.0, METER)
    scene.add_light(sun)

    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(30.0, METER),
    )
    camera.place(Vector3(0.0, 0.70, 3.2), Vector3(0.0, 0.58, 0.0))

    spin_gallery(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
