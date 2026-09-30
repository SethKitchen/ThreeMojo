# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Attach the selected layers of the torso.

The torso shares the pelvis frame: the origin is the midpoint of the
two hip joint centers, plus y is proximal, plus x is body-right and plus
z is anterior. Hang it from the same node as the pelvis and it stands
on the sacrum.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    _ = add_torso(..., contents=BONES.plus(LIGAMENTS))
    _ = add_torso(..., contents=MUSCLES)
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.look import (
    artery_phong,
    lymph_phong,
    nerve_phong,
    skin_phong,
    vein_phong,
)
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    is_paired_bone,
    named_torso_bones,
)
from extensions.humanoid.skeleton.torso.bones.geometry import (
    torso_bone_from_dimensions,
)
from extensions.humanoid.skeleton.torso.contents import BOTH, TorsoContents
from extensions.humanoid.skeleton.torso.ligaments.dimensions import (
    COSTAL_CARTILAGES,
    INTERVERTEBRAL_DISCS,
    is_paired_ligament,
    named_torso_ligaments,
)
from extensions.humanoid.skeleton.torso.ligaments.geometry import (
    torso_ligament_from_dimensions,
)
from extensions.humanoid.skeleton.torso.lymph.dimensions import (
    is_paired_lymph,
    named_torso_lymph,
)
from extensions.humanoid.skeleton.torso.lymph.geometry import (
    torso_lymph_from_dimensions,
)
from extensions.humanoid.skeleton.torso.muscles.dimensions import (
    is_paired_muscle,
    named_torso_muscles,
    torso_muscle_dimensions,
)
from extensions.humanoid.skeleton.torso.muscles.geometry import (
    torso_muscle_from_dimensions,
)
from extensions.humanoid.skeleton.torso.nerves.dimensions import (
    is_paired_nerve,
    named_torso_nerves,
)
from extensions.humanoid.skeleton.torso.nerves.geometry import (
    torso_nerve_from_dimensions,
)
from extensions.humanoid.skeleton.torso.skin.geometry import (
    torso_skin_from_dimensions,
)
from extensions.humanoid.skeleton.torso.vessels.dimensions import (
    is_paired_vessel,
    is_torso_artery,
    named_torso_vessels,
)
from extensions.humanoid.skeleton.torso.vessels.geometry import (
    torso_vessel_from_dimensions,
)
from materials.material import Material, MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh

# Optional `add_torso` paint. A negative id asks the assembler to create
# the default look for that layer.
comptime UNSET_PAINT = MaterialId(-1)


def add_torso(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    spec: HumanoidSpec,
    bone_paint: MaterialId,
    ligament_paint: MaterialId,
    cartilage_paint: MaterialId,
    muscle_paint: MaterialId,
    contents: TorsoContents = BOTH,
    detail: Int = 16,
    origin: Vector3 = Vector3(0, 0, 0),
    artery_paint: MaterialId = UNSET_PAINT,
    vein_paint: MaterialId = UNSET_PAINT,
    lymph_paint: MaterialId = UNSET_PAINT,
    nerve_paint: MaterialId = UNSET_PAINT,
    skin_paint: MaterialId = UNSET_PAINT,
) raises -> NodeId:
    """Attach one connected torso under `parent` and return its node.

    Args:
        scene: The scene that receives the nodes and the meshes.
        assets: Geometry store for the new meshes.
        parent: Node the torso hangs from.
        spec: Standing height, osteological sex and athleticism.
        bone_paint: Material id of the cortical look.
        ligament_paint: Material id of the ligament look.
        cartilage_paint: Material id of the discs and costal cartilages.
        muscle_paint: Material id of the muscle look.
        contents: Named layer bits. Bones, ligaments and muscles are
            the default.
        detail: Cells along each solid.
        origin: Position of the pelvis origin in the parent, in meters.
        artery_paint: Arterial look, or the default artery Phong.
        vein_paint: Venous look, or the default vein Phong.
        lymph_paint: Lymph look, or the default lymph Phong.
        nerve_paint: Nerve look, or the default nerve Phong.
        skin_paint: Skin look, or the default skin Phong.

    Returns:
        The torso's node.

    Raises:
        Error: If the spec, a mesh, `contents` or the scene is invalid.
    """
    if not contents.is_valid():
        raise Error("Torso contents must be a named layer set")
    var dims = torso_muscle_dimensions(spec)
    var root = Object3D()
    root.set_position(origin.x, origin.y, origin.z)
    var root_id = scene.attach(root^, parent)
    var sides = List[BodySide]()
    sides.append(RIGHT)
    sides.append(LEFT)
    if contents.includes_bones():
        var bones = named_torso_bones()
        for index in range(len(bones)):  # pragma: no branch
            for s in range(2):  # pragma: no branch
                if s == 1 and not is_paired_bone(bones[index]):
                    continue
                _place(
                    scene,
                    assets,
                    root_id,
                    torso_bone_from_dimensions(
                        dims.torso, bones[index], sides[s], detail
                    ),
                    bone_paint,
                )
    if contents.includes_ligaments():
        var bands = named_torso_ligaments()
        for index in range(len(bands)):  # pragma: no branch
            var band = bands[index]
            var paint = ligament_paint
            if band == INTERVERTEBRAL_DISCS or band == COSTAL_CARTILAGES:
                paint = cartilage_paint
            for s in range(2):  # pragma: no branch
                if s == 1 and not is_paired_ligament(band):
                    continue
                _place(
                    scene,
                    assets,
                    root_id,
                    torso_ligament_from_dimensions(
                        dims.torso, band, sides[s], detail
                    ),
                    paint,
                )
    if contents.includes_muscles():
        var parts = named_torso_muscles()
        for index in range(len(parts)):  # pragma: no branch
            for s in range(2):  # pragma: no branch
                if s == 1 and not is_paired_muscle(parts[index]):
                    continue
                _place(
                    scene,
                    assets,
                    root_id,
                    torso_muscle_from_dimensions(
                        dims, parts[index], sides[s], detail
                    ),
                    muscle_paint,
                )
    if contents.includes_vessels():
        var artery = _resolved_paint(assets, artery_paint, artery_phong())
        var vein = _resolved_paint(assets, vein_paint, vein_phong())
        var vessels = named_torso_vessels()
        for index in range(len(vessels)):  # pragma: no branch
            var vessel = vessels[index]
            var paint = vein
            if is_torso_artery(vessel):
                paint = artery
            for s in range(2):  # pragma: no branch
                if s == 1 and not is_paired_vessel(vessel):
                    continue
                _place(
                    scene,
                    assets,
                    root_id,
                    torso_vessel_from_dimensions(
                        dims, vessel, sides[s], detail
                    ),
                    paint,
                )
    if contents.includes_lymph():
        var lymph = _resolved_paint(assets, lymph_paint, lymph_phong())
        var groups = named_torso_lymph()
        for index in range(len(groups)):  # pragma: no branch
            for s in range(2):  # pragma: no branch
                if s == 1 and not is_paired_lymph(groups[index]):
                    continue
                _place(
                    scene,
                    assets,
                    root_id,
                    torso_lymph_from_dimensions(
                        dims, groups[index], sides[s], detail
                    ),
                    lymph,
                )
    if contents.includes_nerves():
        var nerve = _resolved_paint(assets, nerve_paint, nerve_phong())
        var trunks = named_torso_nerves()
        for index in range(len(trunks)):  # pragma: no branch
            for s in range(2):  # pragma: no branch
                if s == 1 and not is_paired_nerve(trunks[index]):
                    continue
                _place(
                    scene,
                    assets,
                    root_id,
                    torso_nerve_from_dimensions(
                        dims, trunks[index], sides[s], detail
                    ),
                    nerve,
                )
    if contents.includes_skin():
        var skin = _resolved_paint(
            assets, skin_paint, skin_phong(genome=spec.genome)
        )
        _place(
            scene,
            assets,
            root_id,
            torso_skin_from_dimensions(dims, detail),
            skin,
        )
    return root_id


def _resolved_paint(
    mut assets: Assets, paint: MaterialId, var material: Material
) raises -> MaterialId:
    """Return `paint`, or store `material` when `paint` is unset.

    Args:
        assets: Material store for a new default look.
        paint: Caller paint, or `UNSET_PAINT`.
        material: Default Phong for this layer.

    Returns:
        A stored material id.

    Raises:
        Error: If the store refuses the material.
    """
    if paint.value >= 0:
        return paint
    return assets.materials.add(material^)


def _place(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    var geometry: BufferGeometry,
    paint: MaterialId,
) raises:
    """Attach one mesh at the torso origin under `parent`.

    Args:
        scene: The scene that receives the node and the mesh.
        assets: Geometry store for the new mesh.
        parent: Node the part hangs from.
        geometry: The solid to draw.
        paint: Material id.

    Raises:
        Error: If the scene refuses the node or the mesh.
    """
    var node = Object3D()
    var nid = scene.attach(node^, parent)
    var shape = assets.geometries.add(geometry^)
    scene.add_mesh(Mesh(shape, paint, nid))
