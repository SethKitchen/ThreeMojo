# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Place the leg bones and the knee tissues in one connected frame.

The origin is the tibiofemoral joint line. Plus y is proximal. Plus x is
body-right. Plus z is anterior. Each bone keeps its own osteological
frame. This module stores the origin of that frame in the leg frame.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var pose = assemble_leg(person)
    var hip = pose.hip_center()
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
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
from extensions.humanoid.skeleton.leg.patella.dimensions import (
    PatellaDimensions,
    patella_dimensions,
)
from extensions.humanoid.skeleton.leg.patella.geometry import (
    patella_from_dimensions,
)
from extensions.humanoid.skeleton.leg.tibia.dimensions import (
    TibiaDimensions,
    tibia_dimensions,
)
from extensions.humanoid.skeleton.leg.tibia.geometry import (
    tibia_from_dimensions,
)
from materials.material import MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh


@fieldwise_init
struct LegAssembly(ImplicitlyCopyable):
    """Bones, knee tissues and their origins in one leg frame."""

    var spec: HumanoidSpec
    var side: BodySide
    var femur: FemurDimensions
    var tibia: TibiaDimensions
    var fibula: FibulaDimensions
    var patella: PatellaDimensions
    var knee: KneeDimensions
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
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`. A right leg is the default.

    Returns:
        Bone dimensions, knee dimensions and origins in the leg frame.

    Raises:
        Error: If `spec` or `side` is refused by a bone template.
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
    return LegAssembly(
        spec,
        side,
        femur,
        tibia,
        fibula,
        patella,
        knee,
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
    side: BodySide = RIGHT,
    detail: Int = 16,
) raises -> NodeId:
    """Attach one connected leg under `parent` and return the root node.

    Args:
        scene: The scene that receives the nodes and the meshes.
        assets: Geometry store for the new meshes.
        parent: Node the knee origin hangs from.
        spec: Standing height and osteological sex.
        bone_paint: Material id of the cortical look.
        cartilage_paint: Material id of the cartilage look.
        meniscus_paint: Material id of the meniscus look.
        ligament_paint: Material id of the ligament look.
        side: `RIGHT` or `LEFT`. A right leg is the default.
        detail: Cells along each solid.

    Returns:
        The knee-origin node.

    Raises:
        Error: If the spec, a mesh or the scene is invalid.
    """
    var pose = assemble_leg(spec, side)
    var root = Object3D()
    var root_id = scene.attach(root^, parent)
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
    return root_id


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
