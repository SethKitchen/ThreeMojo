# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Attach the selected layers of the neck and the head.

The neck and the head share the pelvis frame: the origin is the
midpoint of the two hip joint centers, plus y is proximal, plus x is
body-right and plus z is anterior. Hang them from the same node as the
torso and the neck stands on its first thoracic vertebra.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    _ = add_head(..., contents=BONES.plus(MUSCLES))
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.arm.assembly import (
    UNSET_PAINT,
    place_mesh,
    resolved_paint,
)
from extensions.humanoid.skeleton.head.bones.dimensions import (
    named_head_bones,
)
from extensions.humanoid.skeleton.head.bones.geometry import (
    head_bone_from_dimensions,
)
from extensions.humanoid.skeleton.head.contents import BOTH, HeadContents
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.head.hair.dimensions import SCALP_HAIR
from extensions.humanoid.skeleton.head.hair.geometry import (
    head_hair_from_dimensions,
)
from extensions.humanoid.skeleton.head.ligaments.dimensions import (
    is_head_cartilage,
    is_paired_head_ligament,
    named_head_ligaments,
)
from extensions.humanoid.skeleton.head.ligaments.geometry import (
    head_ligament_from_dimensions,
)
from extensions.humanoid.skeleton.head.lymph.dimensions import (
    named_head_lymph,
)
from extensions.humanoid.skeleton.head.lymph.geometry import (
    head_lymph_from_dimensions,
)
from extensions.humanoid.skeleton.head.muscles.dimensions import (
    is_paired_head_muscle,
    named_head_muscles,
)
from extensions.humanoid.skeleton.head.muscles.geometry import (
    head_muscle_from_dimensions,
)
from extensions.humanoid.skeleton.head.nerves.dimensions import (
    is_paired_head_nerve,
    named_head_nerves,
)
from extensions.humanoid.skeleton.head.nerves.geometry import (
    head_nerve_from_dimensions,
)
from extensions.humanoid.skeleton.head.skin.geometry import (
    head_skin_from_dimensions,
)
from extensions.humanoid.skeleton.head.vessels.dimensions import (
    is_head_artery,
    named_head_vessels,
)
from extensions.humanoid.skeleton.head.vessels.geometry import (
    head_vessel_from_dimensions,
)
from extensions.humanoid.skeleton.complexion import iris_albedo
from extensions.humanoid.skeleton.head.eyes import eyeball_mesh
from extensions.humanoid.skeleton.look import (
    artery_phong,
    eye_physical,
    hair_phong,
    lymph_phong,
    nerve_phong,
    skin_phong,
    vein_phong,
)
from extensions.humanoid.spec import HumanoidSpec
from materials.material import MaterialId
from math.vector3 import Vector3


def add_head(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    spec: HumanoidSpec,
    bone_paint: MaterialId,
    ligament_paint: MaterialId,
    cartilage_paint: MaterialId,
    muscle_paint: MaterialId,
    contents: HeadContents = BOTH,
    detail: Int = 16,
    skin_detail: Int = 32,
    origin: Vector3 = Vector3(0, 0, 0),
    artery_paint: MaterialId = UNSET_PAINT,
    vein_paint: MaterialId = UNSET_PAINT,
    lymph_paint: MaterialId = UNSET_PAINT,
    nerve_paint: MaterialId = UNSET_PAINT,
    skin_paint: MaterialId = UNSET_PAINT,
    hair_paint: MaterialId = UNSET_PAINT,
    eye_paint: MaterialId = UNSET_PAINT,
    workers: Int = 1,
) raises -> NodeId:
    """Attach the neck and the head under `parent` and return their node.

    A paired part is drawn on both sides.

    Args:
        scene: The scene that receives the nodes and the meshes.
        assets: Geometry store for the new meshes.
        parent: Node the head hangs from.
        spec: Standing height, osteological sex and athleticism.
        bone_paint: Material id of the cortical look, and the teeth's.
        ligament_paint: Material id of the ligament look.
        cartilage_paint: Material id of the discs, the jaw joints, the
            larynx and the trachea.
        muscle_paint: Material id of the muscle look.
        contents: Named layer bits. Bones, ligaments and muscles are
            the default. `EYES` draws the eyeballs.
        detail: Cells along each solid.
        skin_detail: Cells along the head for its skin and its hair.
        origin: Position of the pelvis origin in the parent, in meters.
        artery_paint: Arterial look, or the default artery Phong.
        vein_paint: Venous look, or the default vein Phong.
        lymph_paint: Lymph look, or the default lymph Phong.
        nerve_paint: Nerve look, or the default nerve Phong.
        skin_paint: Skin look, or the default skin Phong in the tone
            the spec's genome asks for.
        hair_paint: Hair look, or the default hair Phong in the color
            the spec's genome asks for.
        eye_paint: Eyeball look, or the default eye look with an iris
            in the color the spec's genome asks for.
        workers: How many threads mesh the skin and the hair. One by
            default.

    Returns:
        The head's node.

    Raises:
        Error: If the spec, a mesh, `contents` or the scene is invalid.
    """
    if not contents.is_valid():
        raise Error("Head contents must be a named layer set")
    var dims = head_muscle_dimensions(spec)
    var root = Object3D()
    root.set_position(origin.x, origin.y, origin.z)
    var root_id = scene.attach(root^, parent)
    var sides: List[BodySide] = [RIGHT, LEFT]
    if contents.includes_bones():
        var bones = named_head_bones()
        for index in range(len(bones)):  # pragma: no branch
            place_mesh(
                scene,
                assets,
                root_id,
                head_bone_from_dimensions(dims.head, bones[index], detail),
                bone_paint,
            )
    if contents.includes_ligaments():
        var parts = named_head_ligaments()
        for index in range(len(parts)):  # pragma: no branch
            var paint = ligament_paint
            if is_head_cartilage(parts[index]):
                paint = cartilage_paint
            var count = 1
            if is_paired_head_ligament(parts[index]):
                count = 2
            for s in range(count):  # pragma: no branch
                place_mesh(
                    scene,
                    assets,
                    root_id,
                    head_ligament_from_dimensions(
                        dims.head, parts[index], sides[s], detail
                    ),
                    paint,
                )
    if contents.includes_muscles():
        var parts = named_head_muscles()
        for index in range(len(parts)):  # pragma: no branch
            var count = 1
            if is_paired_head_muscle(parts[index]):
                count = 2
            for s in range(count):  # pragma: no branch
                place_mesh(
                    scene,
                    assets,
                    root_id,
                    head_muscle_from_dimensions(
                        dims, parts[index], sides[s], detail
                    ),
                    muscle_paint,
                )
    if contents.includes_vessels():
        var artery = resolved_paint(assets, artery_paint, artery_phong())
        var vein = resolved_paint(assets, vein_paint, vein_phong())
        var parts = named_head_vessels()
        for index in range(len(parts)):  # pragma: no branch
            var paint = vein
            if is_head_artery(parts[index]):
                paint = artery
            for s in range(2):  # pragma: no branch
                place_mesh(
                    scene,
                    assets,
                    root_id,
                    head_vessel_from_dimensions(
                        dims, parts[index], sides[s], detail
                    ),
                    paint,
                )
    if contents.includes_lymph():
        var lymph = resolved_paint(assets, lymph_paint, lymph_phong())
        var parts = named_head_lymph()
        for index in range(len(parts)):  # pragma: no branch
            for s in range(2):  # pragma: no branch
                place_mesh(
                    scene,
                    assets,
                    root_id,
                    head_lymph_from_dimensions(
                        dims, parts[index], sides[s], detail
                    ),
                    lymph,
                )
    if contents.includes_nerves():
        var nerve = resolved_paint(assets, nerve_paint, nerve_phong())
        var parts = named_head_nerves()
        for index in range(len(parts)):  # pragma: no branch
            var count = 1
            if is_paired_head_nerve(parts[index]):
                count = 2
            for s in range(count):  # pragma: no branch
                place_mesh(
                    scene,
                    assets,
                    root_id,
                    head_nerve_from_dimensions(
                        dims, parts[index], sides[s], detail
                    ),
                    nerve,
                )
    if contents.includes_skin():
        var skin = resolved_paint(
            assets, skin_paint, skin_phong(genome=spec.genome, tinted=True)
        )
        place_mesh(
            scene,
            assets,
            root_id,
            head_skin_from_dimensions(dims, skin_detail, workers),
            skin,
        )
    if contents.includes_hair():
        # The brows are painted into the skin's colors, hair by hair,
        # where a solid strip would stand off the curve of the brow
        # ridge: only the scalp's hair is a mesh.
        var hair = resolved_paint(assets, hair_paint, hair_phong(spec.genome))
        place_mesh(
            scene,
            assets,
            root_id,
            head_hair_from_dimensions(
                dims, SCALP_HAIR, RIGHT, skin_detail, workers
            ),
            hair,
        )
    if contents.includes_eyes():
        var eye = eye_paint
        if eye.value < 0:
            var iris = assets.textures.add(iris_albedo(64, spec.genome))
            eye = assets.materials.add(eye_physical(iris))
        for s in range(2):  # pragma: no branch
            place_mesh(
                scene,
                assets,
                root_id,
                eyeball_mesh(dims, sides[s], max(8, detail)),
                eye,
            )
    return root_id
