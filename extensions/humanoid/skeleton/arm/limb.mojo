# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One arm and its hand, drawn together.

The arm and the hand share the pelvis frame, so the hand hangs from
the arm's wrist without an offset. The hand's layer bits are the arm's.
The arm's skin and the hand's skin are meshed apart, each at its own
detail: a finger is too slim for a grid that spans the whole limb.
They overlap across the wrist, so no gap shows between them.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    _ = add_upper_limb(..., side=LEFT, contents=ALL)
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.arm.assembly import UNSET_PAINT, add_arm
from extensions.humanoid.skeleton.arm.contents import BOTH, ArmContents
from extensions.humanoid.skeleton.hand.assembly import add_hand
from extensions.humanoid.skeleton.hand.contents import HandContents
from extensions.humanoid.spec import HumanoidSpec
from materials.material import MaterialId
from math.vector3 import Vector3


def add_upper_limb(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    spec: HumanoidSpec,
    bone_paint: MaterialId,
    ligament_paint: MaterialId,
    cartilage_paint: MaterialId,
    muscle_paint: MaterialId,
    side: BodySide = RIGHT,
    contents: ArmContents = BOTH,
    detail: Int = 16,
    skin_detail: Int = 32,
    hand_skin_detail: Int = 48,
    origin: Vector3 = Vector3(0, 0, 0),
    tendon_paint: MaterialId = UNSET_PAINT,
    artery_paint: MaterialId = UNSET_PAINT,
    vein_paint: MaterialId = UNSET_PAINT,
    lymph_paint: MaterialId = UNSET_PAINT,
    nerve_paint: MaterialId = UNSET_PAINT,
    skin_paint: MaterialId = UNSET_PAINT,
    hair_paint: MaterialId = UNSET_PAINT,
) raises -> NodeId:
    """Attach one arm and its hand under `parent` and return their node.

    Args:
        scene: The scene that receives the nodes and the meshes.
        assets: Geometry store for the new meshes.
        parent: Node the limb hangs from.
        spec: Standing height, osteological sex and athleticism.
        bone_paint: Material id of the cortical look.
        ligament_paint: Material id of the ligament look.
        cartilage_paint: Material id of the cartilage look.
        muscle_paint: Material id of the muscle look.
        side: `RIGHT` or `LEFT`. A right limb is the default.
        contents: Named layer bits, for the arm and the hand alike.
            Bones, ligaments and muscles are the default.
        detail: Cells along each anatomical solid.
        skin_detail: Cells along the arm for its skin.
        hand_skin_detail: Cells along the hand for its skin.
        origin: Position of the pelvis origin in the parent, in meters.
        tendon_paint: The hand's tendon look, or the default.
        artery_paint: Arterial look, or the default artery Phong.
        vein_paint: Venous look, or the default vein Phong.
        lymph_paint: Lymph look, or the default lymph Phong.
        nerve_paint: Nerve look, or the default nerve Phong.
        skin_paint: Skin look, or the default skin Phong.
        hair_paint: Hair look, or the default hair Phong.

    Returns:
        The limb's node.

    Raises:
        Error: If the spec, `side`, a mesh, `contents` or the scene is
            invalid.
    """
    if not contents.is_valid():
        raise Error("Arm contents must be a named layer set")
    var root = Object3D()
    root.set_position(origin.x, origin.y, origin.z)
    var root_id = scene.attach(root^, parent)
    _ = add_arm(
        scene,
        assets,
        root_id,
        spec,
        bone_paint,
        ligament_paint,
        cartilage_paint,
        muscle_paint,
        side,
        contents,
        detail,
        skin_detail,
        artery_paint=artery_paint,
        vein_paint=vein_paint,
        lymph_paint=lymph_paint,
        nerve_paint=nerve_paint,
        skin_paint=skin_paint,
        hair_paint=hair_paint,
    )
    _ = add_hand(
        scene,
        assets,
        root_id,
        spec,
        bone_paint,
        ligament_paint,
        cartilage_paint,
        muscle_paint,
        side,
        HandContents(contents.value),
        detail,
        hand_skin_detail,
        tendon_paint=tendon_paint,
        artery_paint=artery_paint,
        vein_paint=vein_paint,
        lymph_paint=lymph_paint,
        nerve_paint=nerve_paint,
        skin_paint=skin_paint,
        hair_paint=hair_paint,
    )
    return root_id
