# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Attach the selected layers of one arm.

The arm shares the pelvis frame: the origin is the midpoint of the two
hip joint centers, plus y is proximal, plus x is body-right and plus z
is anterior. Hang it from the same node as the torso and it hangs from
the torso's scapula.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    _ = add_arm(..., side=LEFT, contents=BONES.plus(MUSCLES))
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.arm.bones.dimensions import named_arm_bones
from extensions.humanoid.skeleton.arm.bones.geometry import (
    arm_bone_from_dimensions,
)
from extensions.humanoid.skeleton.arm.contents import BOTH, ArmContents
from extensions.humanoid.skeleton.arm.frame import arm_muscle_dimensions
from extensions.humanoid.skeleton.arm.hair.dimensions import named_arm_hair
from extensions.humanoid.skeleton.arm.hair.geometry import (
    arm_hair_from_dimensions,
)
from extensions.humanoid.skeleton.arm.ligaments.dimensions import (
    ARTICULAR_CARTILAGE,
    GLENOID_LABRUM,
    named_arm_ligaments,
)
from extensions.humanoid.skeleton.arm.ligaments.geometry import (
    arm_ligament_from_dimensions,
)
from extensions.humanoid.skeleton.arm.lymph.dimensions import named_arm_lymph
from extensions.humanoid.skeleton.arm.lymph.geometry import (
    arm_lymph_from_dimensions,
)
from extensions.humanoid.skeleton.arm.muscles.dimensions import (
    named_arm_muscles,
)
from extensions.humanoid.skeleton.arm.muscles.geometry import (
    arm_muscle_from_dimensions,
)
from extensions.humanoid.skeleton.arm.nerves.dimensions import named_arm_nerves
from extensions.humanoid.skeleton.arm.nerves.geometry import (
    arm_nerve_from_dimensions,
)
from extensions.humanoid.skeleton.arm.skin.geometry import (
    arm_skin_from_dimensions,
)
from extensions.humanoid.skeleton.arm.vessels.dimensions import (
    is_arm_artery,
    named_arm_vessels,
)
from extensions.humanoid.skeleton.arm.vessels.geometry import (
    arm_vessel_from_dimensions,
)
from extensions.humanoid.skeleton.look import (
    artery_phong,
    hair_phong,
    lymph_phong,
    nerve_phong,
    skin_phong,
    vein_phong,
)
from extensions.humanoid.spec import HumanoidSpec
from materials.material import Material, MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh

# Optional `add_arm` paint. A negative id asks the assembler to create
# the default look for that layer.
comptime UNSET_PAINT = MaterialId(-1)


def add_arm(
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
    origin: Vector3 = Vector3(0, 0, 0),
    artery_paint: MaterialId = UNSET_PAINT,
    vein_paint: MaterialId = UNSET_PAINT,
    lymph_paint: MaterialId = UNSET_PAINT,
    nerve_paint: MaterialId = UNSET_PAINT,
    skin_paint: MaterialId = UNSET_PAINT,
    hair_paint: MaterialId = UNSET_PAINT,
) raises -> NodeId:
    """Attach one arm under `parent` and return its node.

    Args:
        scene: The scene that receives the nodes and the meshes.
        assets: Geometry store for the new meshes.
        parent: Node the arm hangs from.
        spec: Standing height, osteological sex and athleticism.
        bone_paint: Material id of the cortical look.
        ligament_paint: Material id of the ligament look.
        cartilage_paint: Material id of the labrum and the cartilage.
        muscle_paint: Material id of the muscle look.
        side: `RIGHT` or `LEFT`. A right arm is the default.
        contents: Named layer bits. Bones, ligaments and muscles are
            the default.
        detail: Cells along each solid.
        skin_detail: Cells along the arm for its skin.
        origin: Position of the pelvis origin in the parent, in meters.
        artery_paint: Arterial look, or the default artery Phong.
        vein_paint: Venous look, or the default vein Phong.
        lymph_paint: Lymph look, or the default lymph Phong.
        nerve_paint: Nerve look, or the default nerve Phong.
        skin_paint: Skin look, or the default skin Phong.
        hair_paint: Hair look, or the default hair Phong.

    Returns:
        The arm's node.

    Raises:
        Error: If the spec, `side`, a mesh, `contents` or the scene is
            invalid.
    """
    if not contents.is_valid():
        raise Error("Arm contents must be a named layer set")
    if not side.is_valid():
        raise Error("An arm side must be RIGHT or LEFT")
    var dims = arm_muscle_dimensions(spec)
    var root = Object3D()
    root.set_position(origin.x, origin.y, origin.z)
    var root_id = scene.attach(root^, parent)
    if contents.includes_bones():
        var bones = named_arm_bones()
        for index in range(len(bones)):  # pragma: no branch
            place_mesh(
                scene,
                assets,
                root_id,
                arm_bone_from_dimensions(dims.arm, bones[index], side, detail),
                bone_paint,
            )
    if contents.includes_ligaments():
        var parts = named_arm_ligaments()
        for index in range(len(parts)):  # pragma: no branch
            var paint = ligament_paint
            if (
                parts[index] == GLENOID_LABRUM
                or parts[index] == ARTICULAR_CARTILAGE
            ):
                paint = cartilage_paint
            place_mesh(
                scene,
                assets,
                root_id,
                arm_ligament_from_dimensions(
                    dims.arm, parts[index], side, detail
                ),
                paint,
            )
    if contents.includes_muscles():
        var parts = named_arm_muscles()
        for index in range(len(parts)):  # pragma: no branch
            place_mesh(
                scene,
                assets,
                root_id,
                arm_muscle_from_dimensions(dims, parts[index], side, detail),
                muscle_paint,
            )
    if contents.includes_vessels():
        var artery = resolved_paint(assets, artery_paint, artery_phong())
        var vein = resolved_paint(assets, vein_paint, vein_phong())
        var parts = named_arm_vessels()
        for index in range(len(parts)):  # pragma: no branch
            var paint = vein
            if is_arm_artery(parts[index]):
                paint = artery
            place_mesh(
                scene,
                assets,
                root_id,
                arm_vessel_from_dimensions(dims, parts[index], side, detail),
                paint,
            )
    if contents.includes_lymph():
        var lymph = resolved_paint(assets, lymph_paint, lymph_phong())
        var parts = named_arm_lymph()
        for index in range(len(parts)):  # pragma: no branch
            place_mesh(
                scene,
                assets,
                root_id,
                arm_lymph_from_dimensions(dims, parts[index], side, detail),
                lymph,
            )
    if contents.includes_nerves():
        var nerve = resolved_paint(assets, nerve_paint, nerve_phong())
        var parts = named_arm_nerves()
        for index in range(len(parts)):  # pragma: no branch
            place_mesh(
                scene,
                assets,
                root_id,
                arm_nerve_from_dimensions(dims, parts[index], side, detail),
                nerve,
            )
    if contents.includes_skin():
        var skin = resolved_paint(assets, skin_paint, skin_phong(genome=spec.genome))
        place_mesh(
            scene,
            assets,
            root_id,
            arm_skin_from_dimensions(dims, side, skin_detail),
            skin,
        )
    if contents.includes_hair():
        var hair = resolved_paint(assets, hair_paint, hair_phong(spec.genome))
        var parts = named_arm_hair()
        for index in range(len(parts)):  # pragma: no branch
            place_mesh(
                scene,
                assets,
                root_id,
                arm_hair_from_dimensions(dims, parts[index], side, detail),
                hair,
            )
    return root_id


def resolved_paint(
    mut assets: Assets, paint: MaterialId, var material: Material
) raises -> MaterialId:
    """Return `paint`, or store `material` when `paint` is unset.

    Args:
        assets: Material store for a new default look.
        paint: Caller paint, or `UNSET_PAINT`.
        material: Default look for this layer.

    Returns:
        A stored material id.

    Raises:
        Error: If the store refuses the material.
    """
    if paint.value >= 0:
        return paint
    return assets.materials.add(material^)


def place_mesh(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    var geometry: BufferGeometry,
    paint: MaterialId,
) raises:
    """Attach one mesh at its parent's origin.

    Args:
        scene: The scene that receives the node and the mesh.
        assets: Geometry store for the new mesh.
        parent: Node the part hangs from.
        geometry: The solid to draw.
        paint: Material id.

    Raises:
        Error: If the scene refuses the node or the mesh.
    """
    var nid = scene.attach(Object3D(), parent)
    var shape = assets.geometries.add(geometry^)
    scene.add_mesh(Mesh(shape, paint, nid))
