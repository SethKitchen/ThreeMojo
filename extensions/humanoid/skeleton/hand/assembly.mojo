# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Attach the selected layers of one hand.

The hand shares the pelvis frame: the origin is the midpoint of the two
hip joint centers, plus y is proximal, plus x is body-right and plus z
is anterior. Hang it from the same node as the arm and it hangs from
the arm's wrist.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    _ = add_hand(..., side=LEFT, contents=BONES.plus(MUSCLES))
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.arm.assembly import (
    UNSET_PAINT,
    place_mesh,
    resolved_paint,
)
from extensions.humanoid.skeleton.arm.frame import arm_muscle_dimensions
from extensions.humanoid.skeleton.hand.bones.dimensions import (
    named_hand_bones,
)
from extensions.humanoid.skeleton.hand.bones.geometry import (
    hand_bone_from_dimensions,
)
from extensions.humanoid.skeleton.hand.contents import BOTH, HandContents
from extensions.humanoid.skeleton.hand.hair.dimensions import named_hand_hair
from extensions.humanoid.skeleton.hand.hair.geometry import (
    hand_hair_from_dimensions,
)
from extensions.humanoid.skeleton.hand.ligaments.dimensions import (
    JOINT_CARTILAGE,
    TRIANGULAR_FIBROCARTILAGE,
    named_hand_ligaments,
)
from extensions.humanoid.skeleton.hand.ligaments.geometry import (
    hand_ligament_from_dimensions,
)
from extensions.humanoid.skeleton.hand.lymph.dimensions import (
    named_hand_lymph,
)
from extensions.humanoid.skeleton.hand.lymph.geometry import (
    hand_lymph_from_dimensions,
)
from extensions.humanoid.skeleton.hand.muscles.dimensions import (
    is_hand_tendon,
    named_hand_muscles,
)
from extensions.humanoid.skeleton.hand.muscles.geometry import (
    hand_muscle_from_dimensions,
)
from extensions.humanoid.skeleton.hand.nerves.dimensions import (
    named_hand_nerves,
)
from extensions.humanoid.skeleton.hand.nerves.geometry import (
    hand_nerve_from_dimensions,
)
from extensions.humanoid.skeleton.hand.skin.geometry import (
    hand_skin_from_dimensions,
)
from extensions.humanoid.skeleton.hand.vessels.dimensions import (
    is_hand_artery,
    named_hand_vessels,
)
from extensions.humanoid.skeleton.hand.vessels.geometry import (
    hand_vessel_from_dimensions,
)
from extensions.humanoid.skeleton.look import (
    artery_phong,
    hair_phong,
    lymph_phong,
    nerve_phong,
    skin_phong,
    tendon_phong,
    vein_phong,
)
from extensions.humanoid.spec import HumanoidSpec
from materials.material import MaterialId
from math.vector3 import Vector3


def add_hand(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    spec: HumanoidSpec,
    bone_paint: MaterialId,
    ligament_paint: MaterialId,
    cartilage_paint: MaterialId,
    muscle_paint: MaterialId,
    side: BodySide = RIGHT,
    contents: HandContents = BOTH,
    detail: Int = 16,
    skin_detail: Int = 48,
    origin: Vector3 = Vector3(0, 0, 0),
    tendon_paint: MaterialId = UNSET_PAINT,
    artery_paint: MaterialId = UNSET_PAINT,
    vein_paint: MaterialId = UNSET_PAINT,
    lymph_paint: MaterialId = UNSET_PAINT,
    nerve_paint: MaterialId = UNSET_PAINT,
    skin_paint: MaterialId = UNSET_PAINT,
    hair_paint: MaterialId = UNSET_PAINT,
) raises -> NodeId:
    """Attach one hand under `parent` and return its node.

    Args:
        scene: The scene that receives the nodes and the meshes.
        assets: Geometry store for the new meshes.
        parent: Node the hand hangs from.
        spec: Standing height, osteological sex and athleticism.
        bone_paint: Material id of the cortical look.
        ligament_paint: Material id of the ligament look.
        cartilage_paint: Material id of the cartilage and the
            triangular fibrocartilage.
        muscle_paint: Material id of the muscle look.
        side: `RIGHT` or `LEFT`. A right hand is the default.
        contents: Named layer bits. Bones, ligaments and muscles are
            the default.
        detail: Cells along each solid.
        skin_detail: Cells along the hand for its skin.
        origin: Position of the pelvis origin in the parent, in meters.
        tendon_paint: Tendon look, or the default tendon Phong.
        artery_paint: Arterial look, or the default artery Phong.
        vein_paint: Venous look, or the default vein Phong.
        lymph_paint: Lymph look, or the default lymph Phong.
        nerve_paint: Nerve look, or the default nerve Phong.
        skin_paint: Skin look, or the default skin Phong.
        hair_paint: Hair look, or the default hair Phong.

    Returns:
        The hand's node.

    Raises:
        Error: If the spec, `side`, a mesh, `contents` or the scene is
            invalid.
    """
    if not contents.is_valid():
        raise Error("Hand contents must be a named layer set")
    if not side.is_valid():
        raise Error("A hand side must be RIGHT or LEFT")
    var dims = arm_muscle_dimensions(spec)
    var root = Object3D()
    root.set_position(origin.x, origin.y, origin.z)
    var root_id = scene.attach(root^, parent)
    if contents.includes_bones():
        var bones = named_hand_bones()
        for index in range(len(bones)):  # pragma: no branch
            place_mesh(
                scene,
                assets,
                root_id,
                hand_bone_from_dimensions(dims.arm, bones[index], side, detail),
                bone_paint,
            )
    if contents.includes_ligaments():
        var parts = named_hand_ligaments()
        for index in range(len(parts)):  # pragma: no branch
            var paint = ligament_paint
            if (
                parts[index] == JOINT_CARTILAGE
                or parts[index] == TRIANGULAR_FIBROCARTILAGE
            ):
                paint = cartilage_paint
            place_mesh(
                scene,
                assets,
                root_id,
                hand_ligament_from_dimensions(
                    dims.arm, parts[index], side, detail
                ),
                paint,
            )
    if contents.includes_muscles():
        var tendon = resolved_paint(assets, tendon_paint, tendon_phong())
        var parts = named_hand_muscles()
        for index in range(len(parts)):  # pragma: no branch
            var paint = muscle_paint
            if is_hand_tendon(parts[index]):
                paint = tendon
            place_mesh(
                scene,
                assets,
                root_id,
                hand_muscle_from_dimensions(dims, parts[index], side, detail),
                paint,
            )
    if contents.includes_vessels():
        var artery = resolved_paint(assets, artery_paint, artery_phong())
        var vein = resolved_paint(assets, vein_paint, vein_phong())
        var parts = named_hand_vessels()
        for index in range(len(parts)):  # pragma: no branch
            var paint = vein
            if is_hand_artery(parts[index]):
                paint = artery
            place_mesh(
                scene,
                assets,
                root_id,
                hand_vessel_from_dimensions(dims, parts[index], side, detail),
                paint,
            )
    if contents.includes_lymph():
        var lymph = resolved_paint(assets, lymph_paint, lymph_phong())
        var parts = named_hand_lymph()
        for index in range(len(parts)):  # pragma: no branch
            place_mesh(
                scene,
                assets,
                root_id,
                hand_lymph_from_dimensions(dims, parts[index], side, detail),
                lymph,
            )
    if contents.includes_nerves():
        var nerve = resolved_paint(assets, nerve_paint, nerve_phong())
        var parts = named_hand_nerves()
        for index in range(len(parts)):  # pragma: no branch
            place_mesh(
                scene,
                assets,
                root_id,
                hand_nerve_from_dimensions(dims, parts[index], side, detail),
                nerve,
            )
    if contents.includes_skin():
        var skin = resolved_paint(
            assets, skin_paint, skin_phong(genome=spec.genome)
        )
        place_mesh(
            scene,
            assets,
            root_id,
            hand_skin_from_dimensions(dims, side, skin_detail),
            skin,
        )
    if contents.includes_hair():
        var hair = resolved_paint(assets, hair_paint, hair_phong(spec.genome))
        var parts = named_hand_hair()
        for index in range(len(parts)):  # pragma: no branch
            place_mesh(
                scene,
                assets,
                root_id,
                hand_hair_from_dimensions(dims, parts[index], side, detail),
                hair,
            )
    return root_id
