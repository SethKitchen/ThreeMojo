# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Place one foot in the plafond frame and attach the selected layers.

The origin is the tibial plafond. Plus y is proximal. Plus x is
body-right. Plus z is anterior. Pass `ankle_center()` from a leg as
`origin` to meet that limb. This module does not move the leg.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    var pose = assemble_foot(person)
    _ = add_foot(..., contents=MUSCLES)
    _ = add_foot(..., contents=BONES.plus(LIGAMENTS))
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    FootDimensions,
    named_foot_bones,
)
from extensions.humanoid.skeleton.foot.bones.geometry import (
    bone_from_dimensions,
)
from extensions.humanoid.skeleton.foot.contents import BOTH, FootContents
from extensions.humanoid.skeleton.foot.hair.dimensions import named_foot_hair
from extensions.humanoid.skeleton.foot.hair.geometry import hair_from_dimensions
from extensions.humanoid.skeleton.foot.ligaments.dimensions import (
    named_foot_ligaments,
)
from extensions.humanoid.skeleton.foot.ligaments.geometry import (
    ligament_from_dimensions,
)
from extensions.humanoid.skeleton.foot.lymph.dimensions import named_foot_lymph
from extensions.humanoid.skeleton.foot.lymph.geometry import (
    lymph_from_dimensions,
)
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    FootMuscleDimensions,
    foot_muscle_dimensions,
    is_tendon,
    named_foot_muscles,
)
from extensions.humanoid.skeleton.foot.muscles.geometry import (
    muscle_from_dimensions,
)
from extensions.humanoid.skeleton.foot.nerves.dimensions import (
    named_foot_nerves,
)
from extensions.humanoid.skeleton.foot.nerves.geometry import (
    nerve_from_dimensions,
)
from extensions.humanoid.skeleton.foot.skin.geometry import skin_from_dimensions
from extensions.humanoid.skeleton.foot.vessels.dimensions import (
    is_artery,
    named_foot_vessels,
)
from extensions.humanoid.skeleton.foot.vessels.geometry import (
    vessel_from_dimensions,
)
from extensions.humanoid.skeleton.look import (
    artery_phong,
    hair_phong,
    lymph_phong,
    nerve_phong,
    skin_phong,
    vein_phong,
)
from materials.material import Material, MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh

# Optional `add_foot` paint. A negative id asks the assembler to create
# the default look for that layer.
comptime UNSET_PAINT = MaterialId(-1)


@fieldwise_init
struct FootAssembly(ImplicitlyCopyable):
    """Bones and muscle landmarks of one foot in the plafond frame."""

    var spec: HumanoidSpec
    var side: BodySide
    var bones: FootDimensions
    var muscles: FootMuscleDimensions

    def plafond(self) -> Vector3:
        """Return the tibial plafond, which is the origin of this frame."""
        return Vector3(0, 0, 0)


def assemble_foot(
    spec: HumanoidSpec, side: BodySide = RIGHT
) raises -> FootAssembly:
    """Return a connected foot sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        side: `RIGHT` or `LEFT`. A right foot is the default.

    Returns:
        Bone landmarks and muscle landmarks in the foot frame.

    Raises:
        Error: If `spec` or `side` is refused by a bone or muscle template.
    """
    var muscles = foot_muscle_dimensions(spec, side)
    return FootAssembly(spec, side, muscles.foot, muscles)


def add_foot(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    spec: HumanoidSpec,
    bone_paint: MaterialId,
    ligament_paint: MaterialId,
    muscle_paint: MaterialId,
    tendon_paint: MaterialId,
    side: BodySide = RIGHT,
    contents: FootContents = BOTH,
    detail: Int = 8,
    origin: Vector3 = Vector3(0, 0, 0),
    artery_paint: MaterialId = UNSET_PAINT,
    vein_paint: MaterialId = UNSET_PAINT,
    lymph_paint: MaterialId = UNSET_PAINT,
    nerve_paint: MaterialId = UNSET_PAINT,
    skin_paint: MaterialId = UNSET_PAINT,
    hair_paint: MaterialId = UNSET_PAINT,
) raises -> NodeId:
    """Attach one connected foot under `parent` and return the root node.

    Args:
        scene: The scene that receives the nodes and the meshes.
        assets: Geometry store for the new meshes.
        parent: Node the plafond hangs from.
        spec: Standing height, osteological sex and athleticism.
        bone_paint: Material id of the cortical look.
        ligament_paint: Material id of the ligament look.
        muscle_paint: Material id of the muscle look.
        tendon_paint: Material id of the tendon look.
        side: `RIGHT` or `LEFT`. A right foot is the default.
        contents: Named layer bits. Bones, ligaments and muscles are
            the default.
        detail: Cells along each solid.
        origin: Position of the plafond in the parent, in meters.
        artery_paint: Arterial look, or the default artery Phong.
        vein_paint: Venous look, or the default vein Phong.
        lymph_paint: Lymph look, or the default lymph Phong.
        nerve_paint: Nerve look, or the default nerve Phong.
        skin_paint: Skin look, or the default skin Phong.
        hair_paint: Hair look, or the default hair Phong.

    Returns:
        The plafond node.

    Raises:
        Error: If the spec, a mesh, `contents` or the scene is invalid.
    """
    if not contents.is_valid():
        raise Error("Foot contents must be a named layer set")
    var pose = assemble_foot(spec, side)
    var root = Object3D()
    root.set_position(origin.x, origin.y, origin.z)
    var root_id = scene.attach(root^, parent)
    if contents.includes_bones():
        var bones = named_foot_bones()
        var b_index = 0
        while b_index < len(bones):
            _place(
                scene,
                assets,
                root_id,
                bone_from_dimensions(pose.bones, bones[b_index], detail),
                bone_paint,
            )
            b_index += 1
    if contents.includes_ligaments():
        var bands = named_foot_ligaments()
        var g_index = 0
        while g_index < len(bands):
            _place(
                scene,
                assets,
                root_id,
                ligament_from_dimensions(pose.bones, bands[g_index], detail),
                ligament_paint,
            )
            g_index += 1
    if contents.includes_muscles():
        var parts = named_foot_muscles()
        var index = 0
        while index < len(parts):
            var part = parts[index]
            var paint = muscle_paint
            if is_tendon(part):
                paint = tendon_paint
            _place(
                scene,
                assets,
                root_id,
                muscle_from_dimensions(pose.muscles, part, detail),
                paint,
            )
            index += 1
    if contents.includes_vessels():
        var artery = _resolved_paint(assets, artery_paint, artery_phong())
        var vein = _resolved_paint(assets, vein_paint, vein_phong())
        var vessels = named_foot_vessels()
        var v_index = 0
        while v_index < len(vessels):
            var vessel = vessels[v_index]
            var paint = vein
            if is_artery(vessel):
                paint = artery
            _place(
                scene,
                assets,
                root_id,
                vessel_from_dimensions(pose.bones, vessel, detail),
                paint,
            )
            v_index += 1
    if contents.includes_lymph():
        var lymph = _resolved_paint(assets, lymph_paint, lymph_phong())
        var nodes = named_foot_lymph()
        var l_index = 0
        while l_index < len(nodes):
            _place(
                scene,
                assets,
                root_id,
                lymph_from_dimensions(pose.bones, nodes[l_index], detail),
                lymph,
            )
            l_index += 1
    if contents.includes_nerves():
        var nerve = _resolved_paint(assets, nerve_paint, nerve_phong())
        var trunks = named_foot_nerves()
        var n_index = 0
        while n_index < len(trunks):
            _place(
                scene,
                assets,
                root_id,
                nerve_from_dimensions(pose.bones, trunks[n_index], detail),
                nerve,
            )
            n_index += 1
    if contents.includes_skin():
        var skin = _resolved_paint(assets, skin_paint, skin_phong())
        _place(
            scene,
            assets,
            root_id,
            skin_from_dimensions(pose.muscles, detail),
            skin,
        )
    if contents.includes_hair():
        var keratin = _resolved_paint(assets, hair_paint, hair_phong())
        var groups = named_foot_hair()
        var h_index = 0
        while h_index < len(groups):
            _place(
                scene,
                assets,
                root_id,
                hair_from_dimensions(pose.muscles, groups[h_index], detail),
                keratin,
            )
            h_index += 1
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
    """Attach one mesh at the foot origin under `parent`.

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
