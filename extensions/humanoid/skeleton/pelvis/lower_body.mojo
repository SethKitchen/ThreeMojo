# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The pelvis, both legs and both feet in one frame, under one skin.

Each leg hangs from the pelvis at the offset that puts its femoral head
in its socket. Each foot hangs from its leg at the ankle. The pelvis
and the two limbs each fit their own skin. This file meshes their
smooth union, so the whole lower body has one surface.

The solid lives in the pelvis frame. The origin is the midpoint of the
two hip joint centers. Plus y is proximal. Plus x is body-right. Plus z
is anterior.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    _ = add_lower_body(..., contents=BONES.plus(MUSCLES))
    var skin = lower_body_skin_mesh(person)
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import (
    DistanceField,
    field_gradient,
    smax,
    smin,
)
from extensions.humanoid.skeleton.foot.assembly import add_foot
from extensions.humanoid.skeleton.foot.contents import FootContents
from extensions.humanoid.skeleton.isosurface import check_detail
from extensions.humanoid.skeleton.surface_nets import mesh_surface
from extensions.humanoid.skeleton.leg.assembly import add_leg, assemble_leg
from extensions.humanoid.skeleton.leg.contents import LegContents
from extensions.humanoid.skeleton.limb.skin import LimbSkinField
from extensions.humanoid.skeleton.look import (
    artery_phong,
    lymph_phong,
    nerve_phong,
    skin_phong,
    vein_phong,
)
from extensions.humanoid.skeleton.pelvis.assembly import add_pelvis
from extensions.humanoid.skeleton.pelvis.contents import (
    BOTH,
    SKIN,
    PelvisContents,
)
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    pelvis_muscle_dimensions,
)
from extensions.humanoid.skeleton.pelvis.skin.dimensions import PelvisSkinField
from materials.material import Material, MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import max, min

# Optional `add_lower_body` paint. A negative id asks the assembler to
# create the default look for that layer.
comptime UNSET_PAINT = MaterialId(-1)
# The crotch, as shares of the stature: how far below the pubic
# symphysis the thighs part, how wide the crease between them is, and
# how round the fork is where they part.
comptime CROTCH_DROP = Float32(0.018)
comptime CROTCH_HALF = Float32(0.0012)
comptime CROTCH_ROUND = Float32(0.004)


struct LowerBodySkinField(Copyable, DistanceField, Movable):
    """The smooth union of the pelvic skin and both limbs' skins."""

    var pelvis: PelvisSkinField
    var right: LimbSkinField
    var left: LimbSkinField
    # Each leg frame's origin in the pelvis frame.
    var right_origin: Vector3
    var left_origin: Vector3
    var blend: Float32
    # Below `band_bottom` the two limbs' skins are the surface; above
    # `band_top` the pelvic skin is. Between them one morphs into the
    # other.
    var band_bottom: Float32
    var band_top: Float32
    # How far the band drops per meter outside `band_inner` of the
    # midline.
    var band_dip: Float32
    var band_inner: Float32
    # Below `crotch_top` a narrow slot parts the thighs: a crease where
    # they touch, and a gap where they do not.
    var crotch_top: Float32
    var crotch_half: Float32
    var crotch_round: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, spec: HumanoidSpec) raises:
        """Fit the three skins for `spec` and join them at the hips.

        Args:
            spec: Standing height, osteological sex and athleticism.

        Raises:
            Error: If `spec` is refused.
        """
        var dims = pelvis_muscle_dimensions(spec)
        self.pelvis = PelvisSkinField(dims)
        self.right = LimbSkinField(spec, RIGHT)
        self.left = LimbSkinField(spec, LEFT)
        self.right_origin = dims.leg_origin_at(RIGHT)
        self.left_origin = dims.leg_origin_at(LEFT)
        # Where the two thighs or knees touch, their skins meet in one
        # soft fold.
        self.blend = Float32(0.009) * spec.stature.value
        # From the gluteal fold to just below the hip joint centers.
        var S = spec.stature.value
        self.band_bottom = dims.pelvis.hip.y - Float32(0.068) * S
        self.band_top = dims.pelvis.hip.y - Float32(0.020) * S
        self.band_dip = Float32(0.35)
        self.band_inner = Float32(0.035) * S
        self.crotch_top = dims.pelvis.symphysis_bottom.y - CROTCH_DROP * S
        self.crotch_half = CROTCH_HALF * S
        self.crotch_round = CROTCH_ROUND * S
        self.epsilon = self.pelvis.epsilon
        var low = self.pelvis.low
        var high = self.pelvis.high
        _grow(low, high, self.right.low + self.right_origin)
        _grow(low, high, self.right.high + self.right_origin)
        _grow(low, high, self.left.low + self.left_origin)
        _grow(low, high, self.left.high + self.left_origin)
        self.low = low
        self.high = high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the lower body's skin.

        Negative is inside. Zero is the surface.
        """
        # The band dips toward the sides, so the gluteal fold is deepest
        # near the midline and fades out over the lateral thigh.
        var dip = self.band_dip * max(abs(point.x) - self.band_inner, 0)
        var top = self.band_top - dip
        var bottom = self.band_bottom - dip
        if point.y >= top:
            return self._parted(self.pelvis.distance(point), point)
        var limbs = smin(
            self.right.distance(point - self.right_origin),
            self.left.distance(point - self.left_origin),
            self.blend,
        )
        if point.y <= bottom:
            return self._parted(limbs, point)
        # Across the band the surface morphs from the two thighs to the
        # one pelvis, so the crotch forms without a seam.
        var t = (point.y - bottom) / (top - bottom)
        var w = t * t * (3 - 2 * t)
        return self._parted(
            limbs + (self.pelvis.distance(point) - limbs) * w, point
        )

    def _parted(self, d: Float32, point: Vector3) -> Float32:
        """Return `d` with the crotch's slot cut out below its top.

        A section of the pelvis's loft is one closed curve, and the two
        thighs' skins blend where they touch, so neither parts the legs.
        The slot does, in a round fork under the pubic symphysis.
        """
        var slot = max(
            abs(point.x) - self.crotch_half, point.y - self.crotch_top
        )
        return smax(d, -slot, self.crotch_round)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def lower_body_skin_mesh(
    spec: HumanoidSpec, detail: Int = 48
) raises -> BufferGeometry:
    """Return one skin over the pelvis and both limbs, in the pelvis frame.

    Args:
        spec: Standing height, osteological sex and athleticism.
        detail: Cells along the body, eight through sixty-four,
            forty-eight by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec` is refused, if `detail` is out of range, or if
            the field produces no surface.
    """
    check_detail(detail, "lower body skin")
    var field = LowerBodySkinField(spec)
    return mesh_surface(field, field.low, field.high, detail, "lower body skin")


def add_lower_body(
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
    contents: PelvisContents = BOTH,
    detail: Int = 16,
    skin_detail: Int = 48,
    origin: Vector3 = Vector3(0, 0, 0),
    artery_paint: MaterialId = UNSET_PAINT,
    vein_paint: MaterialId = UNSET_PAINT,
    lymph_paint: MaterialId = UNSET_PAINT,
    nerve_paint: MaterialId = UNSET_PAINT,
    skin_paint: MaterialId = UNSET_PAINT,
) raises -> NodeId:
    """Attach the pelvis, both legs and both feet under `parent`.

    The pelvis, the legs and the feet draw the same layers. The skin is
    one surface over all of them.

    Args:
        scene: The scene that receives the nodes and the meshes.
        assets: Geometry store for the new meshes.
        parent: Node the pelvis hangs from.
        spec: Standing height, osteological sex and athleticism.
        bone_paint: Material id of the cortical look.
        cartilage_paint: Material id of the articular cartilage.
        meniscus_paint: Material id of the knee's menisci.
        ligament_paint: Material id of the ligament look.
        muscle_paint: Material id of the muscle look.
        tendon_paint: Material id of the tendon look.
        contents: Named layer bits. Bones, ligaments and muscles are
            the default.
        detail: Cells along each anatomical solid.
        skin_detail: Cells along the body for the one skin.
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
    var artery = _resolved_paint(assets, artery_paint, artery_phong())
    var vein = _resolved_paint(assets, vein_paint, vein_phong())
    var lymph = _resolved_paint(assets, lymph_paint, lymph_phong())
    var nerve = _resolved_paint(assets, nerve_paint, nerve_phong())
    var root = Object3D()
    root.set_position(origin.x, origin.y, origin.z)
    var root_id = scene.attach(root^, parent)
    var inner = contents.value & (SKIN.value ^ 127)
    if inner != 0:
        _ = add_pelvis(
            scene,
            assets,
            root_id,
            spec,
            bone_paint,
            ligament_paint,
            cartilage_paint,
            muscle_paint,
            PelvisContents(inner),
            detail,
            Vector3(0, 0, 0),
            artery,
            vein,
            lymph,
            nerve,
        )
    var leg_bits = _leg_bits(contents)
    var foot_bits = _foot_bits(contents)
    var dims = pelvis_muscle_dimensions(spec)
    var sides = List[BodySide]()
    sides.append(RIGHT)
    sides.append(LEFT)
    for s in range(2):  # pragma: no branch
        var side = sides[s]
        var at = dims.leg_origin_at(side)
        var holder = Object3D()
        holder.set_position(at.x, at.y, at.z)
        var holder_id = scene.attach(holder^, root_id)
        if leg_bits != 0:
            _ = add_leg(
                scene,
                assets,
                holder_id,
                spec,
                bone_paint,
                cartilage_paint,
                meniscus_paint,
                ligament_paint,
                muscle_paint,
                tendon_paint,
                side,
                LegContents(leg_bits),
                detail,
                artery,
                vein,
                lymph,
                nerve,
            )
        if foot_bits != 0:
            _ = add_foot(
                scene,
                assets,
                holder_id,
                spec,
                bone_paint,
                ligament_paint,
                muscle_paint,
                tendon_paint,
                side,
                FootContents(foot_bits),
                detail,
                assemble_leg(spec, side).ankle_center(),
                artery,
                vein,
                lymph,
                nerve,
            )
    if contents.includes_skin():
        var skin = _resolved_paint(
            assets, skin_paint, skin_phong(genome=spec.genome)
        )
        var shape = assets.geometries.add(
            lower_body_skin_mesh(spec, skin_detail)
        )
        var nid = scene.attach(Object3D(), root_id)
        scene.add_mesh(Mesh(shape, skin, nid))
    return root_id


def _leg_bits(contents: PelvisContents) -> Int:
    """Return the leg's layer bits for the pelvis's, less the skin.

    The leg has no ligament bit; its bones bring the knee's tissues. Its
    muscle, vessel, lymph and nerve bits are the pelvis's, one place
    lower.
    """
    return (contents.value & 1) | ((contents.value >> 1) & 30)


def _foot_bits(contents: PelvisContents) -> Int:
    """Return the foot's layer bits for the pelvis's, less the skin.

    The foot's bones, ligaments, muscles, vessels, lymph and nerves use
    the same bits as the pelvis's.
    """
    return contents.value & 63


def _grow(mut low: Vector3, mut high: Vector3, point: Vector3):
    """Grow a box to hold `point`."""
    low = Vector3(min(low.x, point.x), min(low.y, point.y), min(low.z, point.z))
    high = Vector3(
        max(high.x, point.x), max(high.y, point.y), max(high.z, point.z)
    )


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
