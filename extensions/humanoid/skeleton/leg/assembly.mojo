# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Place the leg bones, tissues and remaining layers in one connected frame.

The origin is the tibiofemoral joint line. Plus y is proximal. Plus x is
body-right. Plus z is anterior. Each bone keeps its own osteological
frame. This module stores the origin of that frame in the leg frame.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    var pose = assemble_leg(person)
    var hip = pose.hip_center()
    _ = add_leg(..., contents=MUSCLES)
    _ = add_leg(..., contents=BONES.plus(VESSELS))
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.contents import BOTH, LegContents
from extensions.humanoid.skeleton.leg.femur.dimensions import (
    FemurDimensions,
    femur_dimensions,
)
from extensions.humanoid.skeleton.leg.femur.geometry import (
    femur_from_dimensions,
)
from extensions.humanoid.skeleton.leg.fibula.dimensions import (
    FibulaDimensions,
    fibula_dimensions,
)
from extensions.humanoid.skeleton.leg.fibula.geometry import (
    fibula_from_dimensions,
)
from extensions.humanoid.skeleton.leg.hair.dimensions import named_hair_parts
from extensions.humanoid.skeleton.leg.hair.geometry import hair_from_dimensions
from extensions.humanoid.skeleton.leg.knee.dimensions import (
    KneeDimensions,
    femur_origin,
    fibula_origin,
    knee_dimensions_from_bones,
    patella_origin,
    tibia_origin,
)
from extensions.humanoid.skeleton.leg.knee.geometry import (
    articular_cartilage,
    lateral_collateral,
    lateral_meniscus,
    medial_collateral,
    medial_meniscus,
)
from extensions.humanoid.skeleton.leg.lymph.dimensions import named_lymph_parts
from extensions.humanoid.skeleton.leg.lymph.geometry import (
    lymph_from_dimensions,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    MuscleDimensions,
    is_tendon,
    muscle_dimensions_from_bones,
    named_muscle_parts,
)
from extensions.humanoid.skeleton.leg.muscles.geometry import (
    muscle_from_dimensions,
)
from extensions.humanoid.skeleton.leg.nerves.dimensions import named_nerve_parts
from extensions.humanoid.skeleton.leg.nerves.geometry import (
    nerve_from_dimensions,
)
from extensions.humanoid.skeleton.leg.patella.dimensions import (
    PatellaDimensions,
    patella_dimensions,
)
from extensions.humanoid.skeleton.leg.patella.geometry import (
    patella_from_dimensions,
)
from extensions.humanoid.skeleton.leg.skin.geometry import skin_from_dimensions
from extensions.humanoid.skeleton.leg.tibia.dimensions import (
    TibiaDimensions,
    tibia_dimensions,
)
from extensions.humanoid.skeleton.leg.tibia.geometry import (
    tibia_from_dimensions,
)
from extensions.humanoid.skeleton.leg.vessels.dimensions import (
    is_artery,
    named_vessel_parts,
)
from extensions.humanoid.skeleton.leg.vessels.geometry import (
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

# Optional `add_leg` paint. A negative id asks the assembler to create
# the default look for that layer.
comptime UNSET_PAINT = MaterialId(-1)


@fieldwise_init
struct LegAssembly(ImplicitlyCopyable):
    """Bones, knee tissues, muscles and origins in one leg frame."""

    var spec: HumanoidSpec
    var side: BodySide
    var femur: FemurDimensions
    var tibia: TibiaDimensions
    var fibula: FibulaDimensions
    var patella: PatellaDimensions
    var knee: KneeDimensions
    var muscles: MuscleDimensions
    var femur_origin: Vector3
    var tibia_origin: Vector3
    var fibula_origin: Vector3
    var patella_origin: Vector3

    def hip_center(self) -> Vector3:
        """Return the femoral head center in the leg frame."""
        return self.femur_origin + self.femur.head_center

    def ankle_center(self) -> Vector3:
        """Return the tibial plafond center in the leg frame."""
        return self.tibia_origin + self.tibia.plafond


def assemble_leg(
    spec: HumanoidSpec, side: BodySide = RIGHT
) raises -> LegAssembly:
    """Return a connected leg sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        side: `RIGHT` or `LEFT`. A right leg is the default.

    Returns:
        Bone dimensions, knee dimensions, muscle dimensions and origins
        in the leg frame.

    Raises:
        Error: If `spec` or `side` is refused by a bone or muscle template.
    """
    var femur = femur_dimensions(spec.stature, spec.sex, side)
    var tibia = tibia_dimensions(spec.stature, spec.sex, side)
    var fibula = fibula_dimensions(spec.stature, spec.sex, side)
    var patella = patella_dimensions(spec.stature, spec.sex, side)
    var knee = knee_dimensions_from_bones(femur, tibia, fibula, patella)
    var f_origin = femur_origin(femur, knee.femoral_thickness)
    var t_origin = tibia_origin(tibia, knee.tibial_thickness)
    var fi_origin = fibula_origin(tibia, t_origin, fibula)
    var p_origin = patella_origin(
        femur, f_origin, patella, knee.patellar_thickness
    )
    var muscles = muscle_dimensions_from_bones(
        spec.athleticism,
        femur,
        tibia,
        fibula,
        patella,
        f_origin,
        t_origin,
        fi_origin,
        p_origin,
    )
    return LegAssembly(
        spec,
        side,
        femur,
        tibia,
        fibula,
        patella,
        knee,
        muscles,
        f_origin,
        t_origin,
        fi_origin,
        p_origin,
    )


def add_leg(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    spec: HumanoidSpec,
    bone_paint: MaterialId,
    cartilage_paint: MaterialId,
    meniscus_paint: MaterialId,
    ligament_paint: MaterialId,
    muscle_paint: MaterialId,
    tendon_paint: MaterialId,
    side: BodySide = RIGHT,
    contents: LegContents = BOTH,
    detail: Int = 16,
    artery_paint: MaterialId = UNSET_PAINT,
    vein_paint: MaterialId = UNSET_PAINT,
    lymph_paint: MaterialId = UNSET_PAINT,
    nerve_paint: MaterialId = UNSET_PAINT,
    skin_paint: MaterialId = UNSET_PAINT,
    hair_paint: MaterialId = UNSET_PAINT,
) raises -> NodeId:
    """Attach one connected leg under `parent` and return the root node.

    Args:
        scene: The scene that receives the nodes and the meshes.
        assets: Geometry store for the new meshes.
        parent: Node the knee origin hangs from.
        spec: Standing height, osteological sex and athleticism.
        bone_paint: Material id of the cortical look.
        cartilage_paint: Material id of the cartilage look.
        meniscus_paint: Material id of the meniscus look.
        ligament_paint: Material id of the ligament look.
        muscle_paint: Material id of the muscle look.
        tendon_paint: Material id of the tendon and fascia look.
        side: `RIGHT` or `LEFT`. A right leg is the default.
        contents: Named layer bits. Bones and muscles are the default.
        detail: Cells along each solid.
        artery_paint: Arterial look, or the default artery Phong.
        vein_paint: Venous look, or the default vein Phong.
        lymph_paint: Lymph look, or the default lymph Phong.
        nerve_paint: Nerve look, or the default nerve Phong.
        skin_paint: Skin look, or the default skin Phong.
        hair_paint: Hair look, or the default hair Phong.

    Returns:
        The knee-origin node.

    Raises:
        Error: If the spec, a mesh, `contents` or the scene is invalid.
    """
    if not contents.is_valid():
        raise Error("Leg contents must be a named layer set")
    var pose = assemble_leg(spec, side)
    var root = Object3D()
    var root_id = scene.attach(root^, parent)
    if contents.includes_bones():
        _place(
            scene,
            assets,
            root_id,
            femur_from_dimensions(pose.femur, detail),
            pose.femur_origin,
            bone_paint,
        )
        _place(
            scene,
            assets,
            root_id,
            tibia_from_dimensions(pose.tibia, detail),
            pose.tibia_origin,
            bone_paint,
        )
        _place(
            scene,
            assets,
            root_id,
            fibula_from_dimensions(pose.fibula, detail),
            pose.fibula_origin,
            bone_paint,
        )
        _place(
            scene,
            assets,
            root_id,
            patella_from_dimensions(pose.patella, detail),
            pose.patella_origin,
            bone_paint,
        )
        _place(
            scene,
            assets,
            root_id,
            articular_cartilage(spec, side, detail),
            Vector3(0, 0, 0),
            cartilage_paint,
        )
        _place(
            scene,
            assets,
            root_id,
            medial_meniscus(spec, side, detail),
            Vector3(0, 0, 0),
            meniscus_paint,
        )
        _place(
            scene,
            assets,
            root_id,
            lateral_meniscus(spec, side, detail),
            Vector3(0, 0, 0),
            meniscus_paint,
        )
        _place(
            scene,
            assets,
            root_id,
            medial_collateral(spec, side, detail),
            Vector3(0, 0, 0),
            ligament_paint,
        )
        _place(
            scene,
            assets,
            root_id,
            lateral_collateral(spec, side, detail),
            Vector3(0, 0, 0),
            ligament_paint,
        )
    if contents.includes_muscles():
        var parts = named_muscle_parts()
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
                Vector3(0, 0, 0),
                paint,
            )
            index += 1
    if contents.includes_vessels():
        var artery = _resolved_paint(assets, artery_paint, artery_phong())
        var vein = _resolved_paint(assets, vein_paint, vein_phong())
        var vessels = named_vessel_parts()
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
                vessel_from_dimensions(pose.muscles, vessel, detail),
                Vector3(0, 0, 0),
                paint,
            )
            v_index += 1
    if contents.includes_lymph():
        var lymph = _resolved_paint(assets, lymph_paint, lymph_phong())
        var nodes = named_lymph_parts()
        var l_index = 0
        while l_index < len(nodes):
            _place(
                scene,
                assets,
                root_id,
                lymph_from_dimensions(pose.muscles, nodes[l_index], detail),
                Vector3(0, 0, 0),
                lymph,
            )
            l_index += 1
    if contents.includes_nerves():
        var nerve = _resolved_paint(assets, nerve_paint, nerve_phong())
        var trunks = named_nerve_parts()
        var n_index = 0
        while n_index < len(trunks):
            _place(
                scene,
                assets,
                root_id,
                nerve_from_dimensions(pose.muscles, trunks[n_index], detail),
                Vector3(0, 0, 0),
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
            Vector3(0, 0, 0),
            skin,
        )
    if contents.includes_hair():
        var keratin = _resolved_paint(assets, hair_paint, hair_phong())
        var groups = named_hair_parts()
        var h_index = 0
        while h_index < len(groups):
            _place(
                scene,
                assets,
                root_id,
                hair_from_dimensions(pose.muscles, groups[h_index], detail),
                Vector3(0, 0, 0),
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
    origin: Vector3,
    paint: MaterialId,
) raises:
    """Attach one mesh at `origin` under `parent`.

    Args:
        scene: The scene that receives the node and the mesh.
        assets: Geometry store for the new mesh.
        parent: Node the part hangs from.
        geometry: The solid to draw.
        origin: Position of the solid's frame in the parent, in meters.
        paint: Material id.

    Raises:
        Error: If the scene refuses the node or the mesh.
    """
    var node = Object3D()
    node.set_position(origin.x, origin.y, origin.z)
    var nid = scene.attach(node^, parent)
    var shape = assets.geometries.add(geometry^)
    scene.add_mesh(Mesh(shape, paint, nid))
