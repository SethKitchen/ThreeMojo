# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One leg and its foot, with skin and without it, in a lit studio.

    mojo run -I . examples/limb.mojo [path.png]

The pages are Leg, Foot and Integument. A six-foot male right limb
stands twice on a floor. The left copy shows bones, knee tissues,
muscles and foot ligaments. The right copy shows one skin over the leg
and the foot. The surfaces are physically based, lit by a room
environment and a lamp that casts soft shadows, and tone mapped.
"""

from tools._example_output import (
    example_destination,
    gallery_camera,
    spin_gallery,
)
from tools._example_studio import (
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
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.foot.assembly import add_foot
from extensions.humanoid.skeleton.foot.contents import BOTH as FOOT_BOTH
from extensions.humanoid.skeleton.leg.assembly import add_leg, assemble_leg
from extensions.humanoid.skeleton.leg.contents import BOTH as LEG_BOTH
from extensions.humanoid.skeleton.limb.skin import add_limb_skin
from extensions.humanoid.skeleton.look import skin_albedo, skin_physical
from math.vector3 import Vector3
from units.si import Angle, DEGREE, FOOT, Length, METER

comptime DEFAULT_OUTPUT = "out/limb.png"
comptime WIDTH = 640
comptime HEIGHT = 360
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime ANATOMY_DETAIL = 24
comptime SKIN_DETAIL = 64
comptime SPACING = Float32(0.42)


def _stand(
    mut scene: Scene, parent: NodeId, x: Float32, ground: Float32
) raises -> NodeId:
    """Return a node that stands a limb at `x` with its sole on the floor.

    Args:
        scene: The scene that receives the node.
        parent: Shared parent that turns both limbs.
        x: Position along the row, in meters.
        ground: Height of the sole below the leg frame's origin.

    Returns:
        The limb's node, turned to show the foot from the side.

    Raises:
        Error: If the scene refuses the node.
    """
    var holder = Object3D()
    holder.set_position(x, ground, 0)
    holder.rotate_y(Angle(90.0, DEGREE))
    return scene.attach(holder^, parent)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
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

    var pose = assemble_leg(person, RIGHT)
    # The sole's height below the knee's joint line: the plafond, less
    # the foot's ankle height.
    var ground = -(
        pose.ankle_center().y - Float32(0.048) * person.stature.value
    )
    var pivot = scene.add(Object3D())
    var anatomy = _stand(scene, pivot, -SPACING, ground)
    _ = add_leg(
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
        RIGHT,
        LEG_BOTH,
        ANATOMY_DETAIL,
    )
    _ = add_foot(
        scene,
        assets,
        anatomy,
        person,
        bone,
        ligament,
        muscle,
        tendon,
        RIGHT,
        FOOT_BOTH,
        ANATOMY_DETAIL,
        pose.ankle_center(),
    )
    var covered = _stand(scene, pivot, SPACING, ground)
    _ = add_limb_skin(scene, assets, covered, person, skin, RIGHT, SKIN_DETAIL)
    cast_received_shadows(scene)
    studio_floor(scene, assets, Length(6.0, METER))
    studio_sun(scene, 1.4, 2.6, 2.2, Length(1.4, METER))

    var camera = gallery_camera(
        WIDTH, HEIGHT, Vector3(0.0, 0.62, 3.3), Vector3(0.0, 0.50, 0.0)
    )

    spin_gallery(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
