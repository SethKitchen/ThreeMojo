# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The whole body: the torso, the pelvis, both legs and feet, both arms
and hands, and the neck and the head.

The torso and the pelvis share a frame; the legs and feet hang from
the pelvis, the arms and hands hang from the torso's scapulae, and the
neck stands on the torso's first thoracic vertebra. The lower body's
skin and the torso's skin overlap over the waist. Across that band one
surface morphs into the other. Each arm's skin joins that surface in a
smooth union at the shoulder, and the head's skin joins it at the base
of the neck, so the whole body, down to the wrists, has one skin. Each
hand's skin is meshed on its own, at its own detail, and overlaps the
arm's across the wrist.

The solid lives in the pelvis frame. The origin is the midpoint of the
two hip joint centers. Plus y is proximal. Plus x is body-right. Plus z
is anterior.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    _ = add_body(..., contents=BONES.plus(MUSCLES))
    var skin = body_skin_mesh(person)
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.arm.assembly import add_arm
from extensions.humanoid.skeleton.arm.contents import ArmContents
from extensions.humanoid.skeleton.arm.frame import arm_muscle_dimensions
from extensions.humanoid.skeleton.arm.skin.dimensions import ArmSkinField
from extensions.humanoid.skeleton.field import (
    DistanceField,
    field_gradient,
    smin,
)
from extensions.humanoid.skeleton.hand.assembly import add_hand
from extensions.humanoid.skeleton.head.assembly import add_head
from extensions.humanoid.skeleton.head.contents import HeadContents
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.head.skin.dimensions import HeadSkinField
from extensions.humanoid.skeleton.hand.contents import HandContents
from extensions.humanoid.skeleton.hand.skin.geometry import (
    hand_skin_from_dimensions,
)
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.look import skin_phong
from extensions.humanoid.skeleton.pelvis.contents import PelvisContents
from extensions.humanoid.skeleton.pelvis.lower_body import (
    LowerBodySkinField,
    add_lower_body,
)
from extensions.humanoid.skeleton.torso.assembly import add_torso
from extensions.humanoid.skeleton.torso.contents import (
    BOTH,
    SKIN,
    TorsoContents,
)
from extensions.humanoid.skeleton.torso.muscles.dimensions import (
    torso_muscle_dimensions,
)
from extensions.humanoid.skeleton.torso.skin.dimensions import TorsoSkinField
from materials.material import MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import max, min

# Optional `add_body` paint. A negative id asks the assembler to create
# the default look for that layer.
comptime UNSET_PAINT = MaterialId(-1)


struct BodySkinField(Copyable, DistanceField, Movable):
    """The lower body's skin morphing into the torso's over the waist,
    joined by both arms' skins at the shoulders and the head's at the
    base of the neck."""

    var lower: LowerBodySkinField
    var torso: TorsoSkinField
    var right_arm: ArmSkinField
    var left_arm: ArmSkinField
    var head: HeadSkinField
    # How wide the fold is where an arm's skin meets the torso's.
    var arm_blend: Float32
    # How wide the fold is where the head's skin meets the torso's, and
    # the height below which the head's skin cannot reach the surface.
    var neck_blend: Float32
    var neck_floor: Float32
    # Below `band_bottom` the lower body's skin is the surface; above
    # `band_top` the torso's is.
    var band_bottom: Float32
    var band_top: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, spec: HumanoidSpec) raises:
        """Fit the skins for `spec` and join them at the waist.

        Args:
            spec: Standing height, osteological sex and athleticism.

        Raises:
            Error: If `spec` is refused.
        """
        var dims = torso_muscle_dimensions(spec)
        var f = dims.torso.frame
        self.lower = LowerBodySkinField(spec)
        self.torso = TorsoSkinField(dims)
        var arms = arm_muscle_dimensions(spec)
        self.right_arm = ArmSkinField(arms, RIGHT)
        self.left_arm = ArmSkinField(arms, LEFT)
        self.head = HeadSkinField(head_muscle_dimensions(spec))
        self.arm_blend = f.cm(1.2)
        self.neck_blend = f.cm(1.5)
        self.neck_floor = self.head.low.y - self.neck_blend
        # From the top of the iliac crest to a little above it: both
        # skins hold the whole waist there.
        self.band_bottom = f.at(0, 12.0, 0).y
        self.band_top = f.at(0, 17.0, 0).y
        self.epsilon = self.torso.epsilon
        self.low = Vector3(
            min(self.lower.low.x, self.left_arm.low.x),
            min(self.lower.low.y, self.right_arm.low.y),
            min(self.lower.low.z, min(self.torso.low.z, self.right_arm.low.z)),
        )
        self.high = Vector3(
            max(self.lower.high.x, self.right_arm.high.x),
            max(
                self.head.high.y, max(self.torso.high.y, self.right_arm.high.y)
            ),
            max(
                self.lower.high.z, max(self.torso.high.z, self.right_arm.high.z)
            ),
        )

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the body's skin, in meters.

        Negative is inside. Zero is the surface.
        """
        var trunk = self._trunk(point)
        var arm: Float32
        if point.x < 0:
            arm = self.left_arm.distance(point)
        else:
            arm = self.right_arm.distance(point)
        var body = smin(trunk, arm, self.arm_blend)
        # Below the neck the head's skin is far off, and costs a lot.
        if point.y < self.neck_floor:
            return body
        return smin(body, self.head.distance(point), self.neck_blend)

    def _trunk(self, point: Vector3) -> Float32:
        """Return the distance to the torso's and the lower body's skin."""
        if point.y >= self.band_top:
            return self.torso.distance(point)
        var below = self.lower.distance(point)
        if point.y <= self.band_bottom:
            return below
        var t = (point.y - self.band_bottom) / (
            self.band_top - self.band_bottom
        )
        var w = t * t * (3 - 2 * t)
        return below + (self.torso.distance(point) - below) * w

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def body_skin_mesh(
    spec: HumanoidSpec, detail: Int = 56
) raises -> BufferGeometry:
    """Return one skin over the torso, the pelvis, both legs, both arms,
    the neck and the head, down to the wrists.

    Args:
        spec: Standing height, osteological sex and athleticism.
        detail: Cells along the body, eight through sixty-four,
            fifty-six by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec` is refused, if `detail` is out of range, or if
            the field produces no surface.
    """
    check_detail(detail, "body skin")
    var field = BodySkinField(spec)
    return mesh_field(field, field.low, field.high, detail, "body skin")


def add_body(
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
    contents: TorsoContents = BOTH,
    detail: Int = 16,
    skin_detail: Int = 56,
    hand_skin_detail: Int = 40,
    origin: Vector3 = Vector3(0, 0, 0),
    artery_paint: MaterialId = UNSET_PAINT,
    vein_paint: MaterialId = UNSET_PAINT,
    lymph_paint: MaterialId = UNSET_PAINT,
    nerve_paint: MaterialId = UNSET_PAINT,
    skin_paint: MaterialId = UNSET_PAINT,
) raises -> NodeId:
    """Attach the torso, the pelvis, both legs and feet, both arms and
    hands, and the neck and the head.

    Every part draws the same layers. The skin is one surface down to
    the wrists; each hand's skin is its own mesh.

    Args:
        scene: The scene that receives the nodes and the meshes.
        assets: Geometry store for the new meshes.
        parent: Node the body hangs from.
        spec: Standing height, osteological sex and athleticism.
        bone_paint: Material id of the cortical look.
        cartilage_paint: Material id of the articular cartilage and the
            discs.
        meniscus_paint: Material id of the knee's menisci.
        ligament_paint: Material id of the ligament look.
        muscle_paint: Material id of the muscle look.
        tendon_paint: Material id of the tendon look.
        contents: Named layer bits. Bones, ligaments and muscles are
            the default.
        detail: Cells along each anatomical solid.
        skin_detail: Cells along the body for the one skin.
        hand_skin_detail: Cells along each hand for its skin.
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
        raise Error("Torso contents must be a named layer set")
    var root = Object3D()
    root.set_position(origin.x, origin.y, origin.z)
    var root_id = scene.attach(root^, parent)
    # Every layer but the skin, drawn part by part; the layers use the
    # same bits in the torso and the pelvis.
    var inner = contents.value & (SKIN.value ^ 127)
    if inner != 0:
        _ = add_lower_body(
            scene,
            assets,
            root_id,
            spec,
            bone_paint,
            cartilage_paint,
            meniscus_paint,
            ligament_paint,
            muscle_paint,
            tendon_paint,
            PelvisContents(inner),
            detail,
            skin_detail,
            Vector3(0, 0, 0),
            artery_paint,
            vein_paint,
            lymph_paint,
            nerve_paint,
        )
        _ = add_torso(
            scene,
            assets,
            root_id,
            spec,
            bone_paint,
            ligament_paint,
            cartilage_paint,
            muscle_paint,
            TorsoContents(inner),
            detail,
            Vector3(0, 0, 0),
            artery_paint,
            vein_paint,
            lymph_paint,
            nerve_paint,
        )
        # The arms and the hands use the torso's bits.
        var sides = List[BodySide]()
        sides.append(RIGHT)
        sides.append(LEFT)
        for s in range(2):  # pragma: no branch
            _ = add_arm(
                scene,
                assets,
                root_id,
                spec,
                bone_paint,
                ligament_paint,
                cartilage_paint,
                muscle_paint,
                sides[s],
                ArmContents(inner),
                detail,
                artery_paint=artery_paint,
                vein_paint=vein_paint,
                lymph_paint=lymph_paint,
                nerve_paint=nerve_paint,
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
                sides[s],
                HandContents(inner),
                detail,
                tendon_paint=tendon_paint,
                artery_paint=artery_paint,
                vein_paint=vein_paint,
                lymph_paint=lymph_paint,
                nerve_paint=nerve_paint,
            )
        # The neck and the head use the torso's bits too.
        _ = add_head(
            scene,
            assets,
            root_id,
            spec,
            bone_paint,
            ligament_paint,
            cartilage_paint,
            muscle_paint,
            HeadContents(inner),
            detail,
            artery_paint=artery_paint,
            vein_paint=vein_paint,
            lymph_paint=lymph_paint,
            nerve_paint=nerve_paint,
        )
    if contents.includes_skin():
        var skin = skin_paint
        if skin.value < 0:
            skin = assets.materials.add(skin_phong())
        var shape = assets.geometries.add(body_skin_mesh(spec, skin_detail))
        var nid = scene.attach(Object3D(), root_id)
        scene.add_mesh(Mesh(shape, skin, nid))
        var arms = arm_muscle_dimensions(spec)
        for s in range(2):  # pragma: no branch
            var side = RIGHT
            if s == 1:
                side = LEFT
            var hand = assets.geometries.add(
                hand_skin_from_dimensions(arms, side, hand_skin_detail)
            )
            scene.add_mesh(Mesh(hand, skin, scene.attach(Object3D(), root_id)))
    return root_id
