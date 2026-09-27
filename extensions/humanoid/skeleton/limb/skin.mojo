# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One skin over a leg and its foot.

The leg and the foot each fit their own skin. Drawn together, the two
surfaces meet at the ankle and cross each other there. This file meshes
their smooth union instead, so a whole limb has one surface.

    var skin = limb_skin_mesh(HumanoidSpec(Length(6.0, FOOT), MALE))

The solid lives in the leg frame. The origin is the tibiofemoral joint
line. Plus y is proximal. Plus x is body-right. Plus z is anterior.
"""

from core.buffer_geometry import BufferGeometry
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import (
    DistanceField,
    field_gradient,
    smin,
)
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    foot_muscle_dimensions,
)
from extensions.humanoid.skeleton.foot.skin.dimensions import (
    SkinField as FootSkinField,
)
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.leg.skin.dimensions import (
    SkinField as LegSkinField,
)
from materials.material import MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import max, min


struct LimbSkinField(Copyable, DistanceField, Movable):
    """The smooth union of a leg's skin and its foot's skin."""

    var leg: LegSkinField
    var foot: FootSkinField
    # The tibial plafond in the leg frame: where the foot's frame sits.
    var ankle: Vector3
    var blend: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, spec: HumanoidSpec, side: BodySide = RIGHT) raises:
        """Fit both skins for `spec` and join them at the ankle.

        Args:
            spec: Standing height, osteological sex and athleticism.
            side: `RIGHT` or `LEFT`. A right limb is the default.

        Raises:
            Error: If `spec` or `side` is refused.
        """
        var pose = assemble_leg(spec, side)
        self.ankle = pose.ankle_center()
        self.leg = LegSkinField(pose.muscles)
        self.foot = FootSkinField(foot_muscle_dimensions(spec, side))
        var S = spec.stature.value
        # A centimeter of blend: the two skins meet in one fold.
        self.blend = Float32(0.005) * S
        self.epsilon = self.foot.epsilon
        var foot_low = self.foot.low + self.ankle
        var foot_high = self.foot.high + self.ankle
        self.low = Vector3(
            min(self.leg.low.x, foot_low.x),
            min(self.leg.low.y, foot_low.y),
            min(self.leg.low.z, foot_low.z),
        )
        self.high = Vector3(
            max(self.leg.high.x, foot_high.x),
            max(self.leg.high.y, foot_high.y),
            max(self.leg.high.z, foot_high.z),
        )

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the limb's skin, in meters.

        Negative is inside. Zero is the surface.
        """
        return smin(
            self.leg.distance(point),
            self.foot.distance(point - self.ankle),
            self.blend,
        )

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def limb_skin_mesh(
    spec: HumanoidSpec, side: BodySide = RIGHT, detail: Int = 48
) raises -> BufferGeometry:
    """Return one skin over a leg and its foot, in the leg frame.

    Args:
        spec: Standing height, osteological sex and athleticism.
        side: `RIGHT` or `LEFT`. A right limb is the default.
        detail: Cells along the limb, eight through sixty-four,
            forty-eight by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec` or `side` is refused, if `detail` is out of
            range, or if the field produces no surface.
    """
    check_detail(detail, "limb skin")
    var field = LimbSkinField(spec, side)
    return mesh_field(field, field.low, field.high, detail, "limb skin")


def add_limb_skin(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    spec: HumanoidSpec,
    paint: MaterialId,
    side: BodySide = RIGHT,
    detail: Int = 48,
) raises -> NodeId:
    """Attach one skin over a leg and its foot under `parent`.

    Draw the leg and the foot without their `SKIN` layers, and this
    skin once. The origin is the leg frame's, as `add_leg` uses.

    Args:
        scene: The scene that receives the node and the mesh.
        assets: Geometry store for the new mesh.
        parent: Node the limb hangs from.
        spec: Standing height, osteological sex and athleticism.
        paint: Material id of the skin look.
        side: `RIGHT` or `LEFT`. A right limb is the default.
        detail: Cells along the limb, eight through sixty-four.

    Returns:
        The node that holds the skin.

    Raises:
        Error: If `spec`, `side` or `detail` is refused, or the scene
            refuses the node or the mesh.
    """
    var shape = assets.geometries.add(limb_skin_mesh(spec, side, detail))
    var nid = scene.attach(Object3D(), parent)
    scene.add_mesh(Mesh(shape, paint, nid))
    return nid
