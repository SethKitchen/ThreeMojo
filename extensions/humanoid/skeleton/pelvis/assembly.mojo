# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Place the pelvis in its frame and attach the selected layers.

The origin is the midpoint of the two hip joint centers. Plus y is
proximal. Plus x is body-right. Plus z is anterior. `leg_origin` says
where each leg's knee origin sits, so its femoral head meets the
socket. `add_lower_body` attaches the pelvis, both legs and both feet
together.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    var pose = assemble_pelvis(person)
    _ = add_pelvis(..., contents=MUSCLES)
    _ = add_pelvis(..., contents=BONES.plus(LIGAMENTS))
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
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    PelvisDimensions,
    named_pelvis_bones,
)
from extensions.humanoid.skeleton.pelvis.bones.geometry import (
    pelvis_bone_from_dimensions,
)
from extensions.humanoid.skeleton.pelvis.contents import BOTH, PelvisContents
from extensions.humanoid.skeleton.pelvis.ligaments.dimensions import (
    ACETABULAR_CARTILAGE,
    ACETABULAR_LABRUM,
    INTERPUBIC_DISC,
    is_midline,
    named_pelvis_ligaments,
)
from extensions.humanoid.skeleton.pelvis.ligaments.geometry import (
    pelvis_ligament_from_dimensions,
)
from extensions.humanoid.skeleton.pelvis.lymph.dimensions import (
    named_pelvis_lymph,
)
from extensions.humanoid.skeleton.pelvis.lymph.geometry import (
    pelvis_lymph_from_dimensions,
)
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    PelvisMuscleDimensions,
    named_pelvis_muscles,
    pelvis_muscle_dimensions,
)
from extensions.humanoid.skeleton.pelvis.muscles.geometry import (
    pelvis_muscle_from_dimensions,
)
from extensions.humanoid.skeleton.pelvis.nerves.dimensions import (
    named_pelvis_nerves,
)
from extensions.humanoid.skeleton.pelvis.nerves.geometry import (
    pelvis_nerve_from_dimensions,
)
from extensions.humanoid.skeleton.pelvis.skin.geometry import (
    pelvis_skin_from_dimensions,
)
from extensions.humanoid.skeleton.pelvis.vessels.dimensions import (
    is_pelvic_artery,
    is_unpaired_vessel,
    named_pelvis_vessels,
)
from extensions.humanoid.skeleton.pelvis.vessels.geometry import (
    pelvis_vessel_from_dimensions,
)
from materials.material import Material, MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh

# Optional `add_pelvis` paint. A negative id asks the assembler to create
# the default look for that layer.
comptime UNSET_PAINT = MaterialId(-1)


@fieldwise_init
struct PelvisAssembly(ImplicitlyCopyable):
    """Pelvic landmarks and the soft-tissue landmarks in one frame."""

    var spec: HumanoidSpec
    var bones: PelvisDimensions
    var muscles: PelvisMuscleDimensions

    def hip_center(self, side: BodySide) raises -> Vector3:
        """Return one hip joint center in the pelvis frame.

        Args:
            side: `RIGHT` or `LEFT`.

        Returns:
            The center of that femoral head, in meters.

        Raises:
            Error: If `side` is not valid.
        """
        return self.bones.hip_center(side)

    def leg_origin(self, side: BodySide) raises -> Vector3:
        """Return where one leg's knee origin sits in the pelvis frame.

        Args:
            side: `RIGHT` or `LEFT`.

        Returns:
            The offset to pass as that leg's position, in meters.

        Raises:
            Error: If `side` is not valid.
        """
        return self.muscles.leg_origin_at(side)


def assemble_pelvis(spec: HumanoidSpec) raises -> PelvisAssembly:
    """Return a connected pelvis sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.

    Returns:
        Bone landmarks and soft-tissue landmarks in the pelvis frame.

    Raises:
        Error: If `spec` is refused by a bone or muscle template.
    """
    var muscles = pelvis_muscle_dimensions(spec)
    return PelvisAssembly(spec, muscles.pelvis, muscles)


def add_pelvis(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    spec: HumanoidSpec,
    bone_paint: MaterialId,
    ligament_paint: MaterialId,
    cartilage_paint: MaterialId,
    muscle_paint: MaterialId,
    contents: PelvisContents = BOTH,
    detail: Int = 16,
    origin: Vector3 = Vector3(0, 0, 0),
    artery_paint: MaterialId = UNSET_PAINT,
    vein_paint: MaterialId = UNSET_PAINT,
    lymph_paint: MaterialId = UNSET_PAINT,
    nerve_paint: MaterialId = UNSET_PAINT,
    skin_paint: MaterialId = UNSET_PAINT,
) raises -> NodeId:
    """Attach one connected pelvis under `parent` and return its node.

    Args:
        scene: The scene that receives the nodes and the meshes.
        assets: Geometry store for the new meshes.
        parent: Node the pelvis hangs from.
        spec: Standing height, osteological sex and athleticism.
        bone_paint: Material id of the cortical look.
        ligament_paint: Material id of the ligament look.
        cartilage_paint: Material id of the labrum, socket cartilage and
            interpubic disc.
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
        The pelvis origin node.

    Raises:
        Error: If the spec, a mesh, `contents` or the scene is invalid.
    """
    if not contents.is_valid():
        raise Error("Pelvis contents must be a named layer set")
    var pose = assemble_pelvis(spec)
    var root = Object3D()
    root.set_position(origin.x, origin.y, origin.z)
    var root_id = scene.attach(root^, parent)
    var sides = List[BodySide]()
    sides.append(RIGHT)
    sides.append(LEFT)
    if contents.includes_bones():
        var bones = named_pelvis_bones()
        for index in range(len(bones)):  # pragma: no branch
            _place(
                scene,
                assets,
                root_id,
                pelvis_bone_from_dimensions(pose.bones, bones[index], detail),
                bone_paint,
            )
    if contents.includes_ligaments():
        var bands = named_pelvis_ligaments()
        for index in range(len(bands)):  # pragma: no branch
            var band = bands[index]
            var paint = ligament_paint
            if (
                band == ACETABULAR_LABRUM
                or band == ACETABULAR_CARTILAGE
                or band == INTERPUBIC_DISC
            ):
                paint = cartilage_paint
            for s in range(2):  # pragma: no branch
                if s == 1 and is_midline(band):
                    continue
                _place(
                    scene,
                    assets,
                    root_id,
                    pelvis_ligament_from_dimensions(
                        pose.muscles, band, sides[s], detail
                    ),
                    paint,
                )
    if contents.includes_muscles():
        var parts = named_pelvis_muscles()
        for index in range(len(parts)):  # pragma: no branch
            for s in range(2):  # pragma: no branch
                _place(
                    scene,
                    assets,
                    root_id,
                    pelvis_muscle_from_dimensions(
                        pose.muscles, parts[index], sides[s], detail
                    ),
                    muscle_paint,
                )
    if contents.includes_vessels():
        var artery = _resolved_paint(assets, artery_paint, artery_phong())
        var vein = _resolved_paint(assets, vein_paint, vein_phong())
        var vessels = named_pelvis_vessels()
        for index in range(len(vessels)):  # pragma: no branch
            var vessel = vessels[index]
            var paint = vein
            if is_pelvic_artery(vessel):
                paint = artery
            for s in range(2):  # pragma: no branch
                if s == 1 and is_unpaired_vessel(vessel):
                    continue
                _place(
                    scene,
                    assets,
                    root_id,
                    pelvis_vessel_from_dimensions(
                        pose.muscles, vessel, sides[s], detail
                    ),
                    paint,
                )
    if contents.includes_lymph():
        var lymph = _resolved_paint(assets, lymph_paint, lymph_phong())
        var groups = named_pelvis_lymph()
        for index in range(len(groups)):  # pragma: no branch
            for s in range(2):  # pragma: no branch
                _place(
                    scene,
                    assets,
                    root_id,
                    pelvis_lymph_from_dimensions(
                        pose.muscles, groups[index], sides[s], detail
                    ),
                    lymph,
                )
    if contents.includes_nerves():
        var nerve = _resolved_paint(assets, nerve_paint, nerve_phong())
        var trunks = named_pelvis_nerves()
        for index in range(len(trunks)):  # pragma: no branch
            for s in range(2):  # pragma: no branch
                _place(
                    scene,
                    assets,
                    root_id,
                    pelvis_nerve_from_dimensions(
                        pose.muscles, trunks[index], sides[s], detail
                    ),
                    nerve,
                )
    if contents.includes_skin():
        var skin = _resolved_paint(assets, skin_paint, skin_phong(genome=spec.genome))
        _place(
            scene,
            assets,
            root_id,
            pelvis_skin_from_dimensions(pose.muscles, detail),
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
    """Attach one mesh at the pelvis origin under `parent`.

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
