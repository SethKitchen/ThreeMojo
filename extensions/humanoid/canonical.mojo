# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Canonical anatomy: versioned SI part meshes, tissue labels and properties.

`canonical_body` generates the whole body from the library's own fields.
It never reads a visual, decimated, skinned or baked mesh. The skin
envelope is the union of the body skin field and both hand skin fields.
The skeleton is every named bone field of the template, without the
display widening of a visual mesh.

The body has fourteen regions and two tissue labels, so it has 28 parts.
A grid vertex inside a named bone belongs to that bone's region and to
`BONE_TISSUE`. Any other vertex inside the skin belongs to the region of
its position and to `SOFT_TISSUE`. The parts thus partition the sampled
body volume, and the whole-body properties are the sum of the parts.

| Label | Density |
|---|---|
| `BONE_TISSUE` | The bone family's cortical or trabecular apparent density; marrow uses the adipose proxy |
| `SOFT_TISSUE` | `muscle_tissue` wet density, a proxy for all skin, fat, muscle, organs and airways |

These are template estimates at a recorded grid step. No convergence,
anatomical, biomechanical or clinical validation is claimed.

    var body = canonical_body(person)
    var thigh = body.parts[part_index(RIGHT_THIGH_REGION, BONE_TISSUE)]
    var record = canonical_record(body)

Coordinates are meters in the pelvis frame: right-handed, plus y up,
plus x body-right, plus z anterior, origin between the hip centers.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.user_data import UserData, user_data_of
from extensions.anatomy.inertia import InertiaTally, SegmentInertia
from extensions.anatomy.soft_tissue import adipose_tissue, muscle_tissue
from extensions.anatomy.tissue import cortical_tissue, trabecular_tissue
from extensions.humanoid.fidelity import (
    CANONICAL_PARTS_REVISION,
    FNV1A_OFFSET,
    canonical_inputs,
    fingerprint_hex,
    fnv1a_step,
    json_fingerprint,
    spec_fingerprint,
)
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.arm.bones.dimensions import (
    ARM_SHELL,
    HUMERUS,
    arm_bone_field,
    arm_bone_label,
    named_arm_bones,
)
from extensions.humanoid.skeleton.arm.bones.mass import fill_at
from extensions.humanoid.skeleton.arm.frame import arm_muscle_dimensions
from extensions.humanoid.skeleton.field import DistanceField, flip_x, mix_point
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    FootBoneField,
    bone_part_label,
    named_foot_bones,
)
from extensions.humanoid.skeleton.foot.bones.mass import (
    foot_bone_field_occupancy,
)
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    foot_muscle_dimensions,
)
from extensions.humanoid.skeleton.hand.bones.dimensions import (
    HAND_SHELL,
    hand_bone_field,
    hand_bone_label,
    named_hand_bones,
)
from extensions.humanoid.skeleton.hand.skin.dimensions import HandSkinField
from extensions.humanoid.skeleton.head.bones.dimensions import (
    HEAD_SHELL,
    head_bone_field,
    head_bone_label,
    named_head_bones,
)
from extensions.humanoid.skeleton.head.eyes import eye_center, eye_radius
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.isosurface import (
    SampleGrid,
    mesh_field,
    mesh_samples,
)
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.leg.femur.dimensions import FemurField
from extensions.humanoid.skeleton.leg.femur.mass import femur_field_occupancy
from extensions.humanoid.skeleton.leg.fibula.dimensions import FibulaField
from extensions.humanoid.skeleton.leg.fibula.mass import (
    fibula_field_occupancy,
)
from extensions.humanoid.skeleton.leg.patella.dimensions import PatellaField
from extensions.humanoid.skeleton.leg.patella.mass import (
    patella_field_occupancy,
)
from extensions.humanoid.skeleton.leg.tibia.dimensions import TibiaField
from extensions.humanoid.skeleton.leg.tibia.mass import tibia_field_occupancy
from extensions.humanoid.skeleton.occupancy import (
    EMPTY,
    MARROW,
    BoneOccupancy,
    apparent_density_of,
)
from extensions.humanoid.skeleton.pelvis.assembly import assemble_pelvis
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    PelvisBoneField,
    named_pelvis_bones,
    pelvis_bone_label,
)
from extensions.humanoid.skeleton.pelvis.bones.mass import (
    pelvis_bone_field_occupancy,
)
from extensions.humanoid.skeleton.sculpt import box_gap
from extensions.humanoid.skeleton.torso.body import BodySkinField
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    TORSO_SHELL,
    is_paired_bone,
    named_torso_bones,
    torso_bone_field,
    torso_bone_label,
)
from extensions.humanoid.skeleton.torso.sweep import SweepField
from geometries.utils import merge_geometries
from loaders.json import parse_json
from math.vector3 import Vector3
from std.math import ceil, isfinite, max, min
from std.memory import bitcast
from units.si import (
    CUBIC_METER,
    KILOGRAM,
    KILOGRAM_SQUARE_METER,
    METER,
    MILLIMETER,
    Density,
    Length,
    Volume,
)

comptime CANONICAL_PARTS_KEY = "threemojo_canonical_parts"
comptime CANONICAL_PARTS_SCHEMA = 1
# The property and soft-tissue grid. The limits keep a whole body within
# a bounded amount of work.
comptime CANONICAL_STEP = Length(10.0, MILLIMETER)
comptime MIN_CANONICAL_STEP = Length(5.0, MILLIMETER)
comptime MAX_CANONICAL_STEP = Length(10.0, MILLIMETER)
# Cells along each bone's own marching grid.
comptime BONE_DETAIL = 8
comptime REGION_COUNT = 14
comptime TISSUE_COUNT = 2
comptime PART_COUNT = REGION_COUNT * TISSUE_COUNT
comptime SOFT_DENSITY_RULE = (
    "muscle_tissue wet density for all non-bone tissue; no skin, fat,"
    " organ or airway partition"
)
comptime BONE_DENSITY_RULE = (
    "bone-family cortical shell and trabecular fill at apparent density;"
    " marrow at the adipose proxy"
)
# A vertex this many grid steps outside the skin cannot move a part mesh.
comptime _MARGIN_STEPS = Float32(2)
# The nearest-bone distance of a vertex outside every bone box.
comptime _FAR = Float32(1.0e3)
# A crotch-crease top far below any body: the canonical skin has no
# crease. The crease is a display seam, not a tissue boundary.
comptime _NO_CREASE = Float32(-1.0e3)
# The space kept between each eyeball and the carved canonical orbit.
comptime ORBIT_CLEARANCE = Length(1.0, MILLIMETER)
# Grid vertices along each edge of a coarse block, and how many block
# edges a corner may stand outside the skin before the block is skipped.
comptime _BLOCK = 4
comptime _REACH = Float32(2.2)
# The height of one candidate slab, in meters.
comptime _SLAB = Float32(0.04)
# Femur, patella, tibia, fibula and the 26 foot bones of one side.
comptime _LEG_BONES = 30
comptime _REGION_LABELS: List[String] = [
    "head-neck",
    "trunk",
    "right-upper-arm",
    "right-forearm",
    "right-hand",
    "left-upper-arm",
    "left-forearm",
    "left-hand",
    "right-thigh",
    "right-shank",
    "right-foot",
    "left-thigh",
    "left-shank",
    "left-foot",
]


@fieldwise_init
struct BodyRegion(Equatable, ImplicitlyCopyable, Writable):
    """One region of the canonical body partition.

    The type stops a bare integer at compile time. A value that is not a
    named region is still constructible, and each boundary refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is a named region.

        Returns:
            True for the fourteen named regions.
        """
        return self.value >= 0 and self.value < REGION_COUNT


# The head and the neck, above the center of C7.
comptime HEAD_NECK_REGION = BodyRegion(0)
# The thorax, abdomen and pelvis, from the hip centers to C7.
comptime TRUNK_REGION = BodyRegion(1)
comptime RIGHT_UPPER_ARM_REGION = BodyRegion(2)
comptime RIGHT_FOREARM_REGION = BodyRegion(3)
comptime RIGHT_HAND_REGION = BodyRegion(4)
comptime LEFT_UPPER_ARM_REGION = BodyRegion(5)
comptime LEFT_FOREARM_REGION = BodyRegion(6)
comptime LEFT_HAND_REGION = BodyRegion(7)
comptime RIGHT_THIGH_REGION = BodyRegion(8)
comptime RIGHT_SHANK_REGION = BodyRegion(9)
comptime RIGHT_FOOT_REGION = BodyRegion(10)
comptime LEFT_THIGH_REGION = BodyRegion(11)
comptime LEFT_SHANK_REGION = BodyRegion(12)
comptime LEFT_FOOT_REGION = BodyRegion(13)


@fieldwise_init
struct CanonicalTissue(Equatable, ImplicitlyCopyable, Writable):
    """The tissue label of one canonical part.

    The type stops a bare integer at compile time. A value that is not a
    named label is still constructible, and each boundary refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is a named tissue label.

        Returns:
            True for `SOFT_TISSUE` and `BONE_TISSUE`.
        """
        return self == SOFT_TISSUE or self == BONE_TISSUE


comptime SOFT_TISSUE = CanonicalTissue(0)
comptime BONE_TISSUE = CanonicalTissue(1)


def region_label(region: BodyRegion) raises -> String:
    """Return the stable label of a region.

    Args:
        region: A named region.

    Returns:
        A lowercase label, for example `right-thigh`.

    Raises:
        Error: If the region is not named.
    """
    if not region.is_valid():
        raise Error("A body region must be named")
    return materialize[_REGION_LABELS]()[region.value]


def tissue_label(tissue: CanonicalTissue) raises -> String:
    """Return the stable label of a tissue.

    Args:
        tissue: A named tissue label.

    Returns:
        `soft` or `bone`.

    Raises:
        Error: If the tissue is not named.
    """
    if not tissue.is_valid():
        raise Error("A canonical tissue must be named")
    if tissue == BONE_TISSUE:
        return "bone"
    return "soft"


def named_body_regions() -> List[BodyRegion]:
    """Return every named region in a stable order.

    Returns:
        The fourteen regions, head and neck first.
    """
    var regions = List[BodyRegion]()
    for index in range(REGION_COUNT):  # pragma: no branch
        regions.append(BodyRegion(index))
    return regions^


def part_index(region: BodyRegion, tissue: CanonicalTissue) raises -> Int:
    """Return where a part sits in `CanonicalBody.parts`.

    Args:
        region: A named region.
        tissue: A named tissue label.

    Returns:
        `2 * region + tissue`.

    Raises:
        Error: If the region or the tissue is not named.
    """
    if not region.is_valid():
        raise Error("A body region must be named")
    if not tissue.is_valid():
        raise Error("A canonical tissue must be named")
    return region.value * TISSUE_COUNT + tissue.value


def part_label(region: BodyRegion, tissue: CanonicalTissue) raises -> String:
    """Return the stable ID of a part.

    Args:
        region: A named region.
        tissue: A named tissue label.

    Returns:
        The region label, a period and the tissue label.

    Raises:
        Error: If the region or the tissue is not named.
    """
    return region_label(region) + "." + tissue_label(tissue)


def _side_region(first_right: Int, side: Int) -> BodyRegion:
    """Return a limb region: `first_right` on the right, three on."""
    return BodyRegion(first_right + 3 * side)


def _in_box(low: Vector3, high: Vector3, p: Vector3) -> Bool:
    """Return whether `p` lies in the box from `low` to `high`."""
    return box_gap(low, high, p) <= 0


struct CanonicalEnvelope(Copyable, Movable):
    """The canonical skin and the rule that names each point's region.

    The skin is the union of the body skin field, both hand skin fields
    and both eyeballs. It has no crotch crease and no leg gap: those are
    display seams. The eyeballs stand a little proud of the scanned lids,
    and the union keeps their whole volume in the body. The regions follow
    the template's own landmarks:

    - A point nearest a hand skin is in that hand past the wrist plane,
      and in that forearm before it.
    - A point nearer an arm skin than the trunk skins is in that arm. The
      elbow and wrist planes, normal to the bone axes, split it.
    - Above the center of C7 is the head and neck.
    - From the hip centers to C7 is the trunk.
    - Below, horizontal planes through the femoral-condyle midpoint and
      the lateral malleolus split thigh, shank and foot.
    """

    var body: BodySkinField
    var hands: List[HandSkinField]
    var neck_base: Float32
    var hip: Float32
    var knees: List[Float32]
    var malleoli: List[Float32]
    var elbows: List[Vector3]
    var wrists: List[Vector3]
    var upper_axes: List[Vector3]
    var fore_axes: List[Vector3]
    var eyes: List[Vector3]
    """Both eyeball centers, right first, in meters."""
    var eye_radius: Float32
    """The eyeball radius, in meters."""
    var low: Vector3
    var high: Vector3

    def __init__(out self, spec: HumanoidSpec) raises:
        """Build the skin fields and the landmarks for `spec`.

        Args:
            spec: The canonical input recipe.

        Raises:
            Error: If a field or a landmark refuses the spec.
        """
        self.body = BodySkinField(spec)
        self.body.lower.crotch_top = _NO_CREASE
        var arms = arm_muscle_dimensions(spec)
        var head = head_muscle_dimensions(spec)
        self.eyes = [eye_center(head.head, RIGHT), eye_center(head.head, LEFT)]
        self.eye_radius = eye_radius(head.head)
        self.hands = List[HandSkinField]()
        self.hands.append(HandSkinField(arms, RIGHT))
        self.hands.append(HandSkinField(arms, LEFT))
        self.neck_base = head.head.centers[6].y
        var pelvis = assemble_pelvis(spec)
        self.hip = pelvis.hip_center(RIGHT).y
        self.knees = List[Float32]()
        self.malleoli = List[Float32]()
        self.elbows = List[Vector3]()
        self.wrists = List[Vector3]()
        self.upper_axes = List[Vector3]()
        self.fore_axes = List[Vector3]()
        var frame = arms.arm.frame
        var low = self.body.low
        var high = self.body.high
        for side in [RIGHT, LEFT]:  # pragma: no branch
            var origin = pelvis.leg_origin(side)
            var pose = assemble_leg(spec, side)
            var knee = mix_point(
                pose.muscles.med_condyle, pose.muscles.lat_condyle, 0.5
            )
            self.knees.append(origin.y + knee.y)
            self.malleoli.append(
                origin.y
                + (pose.fibula_origin + pose.fibula.lateral_malleolus).y
            )
            var shoulder = frame.shoulder
            var elbow = frame.elbow
            var wrist = frame.wrist
            if side == LEFT:
                shoulder = flip_x(shoulder)
                elbow = flip_x(elbow)
                wrist = flip_x(wrist)
            self.elbows.append(elbow)
            self.wrists.append(wrist)
            self.upper_axes.append(_unit(elbow - shoulder))
            self.fore_axes.append(_unit(wrist - elbow))
        for index in range(2):  # pragma: no branch
            low = Vector3(
                min(low.x, self.hands[index].low.x),
                min(low.y, self.hands[index].low.y),
                min(low.z, self.hands[index].low.z),
            )
            high = Vector3(
                max(high.x, self.hands[index].high.x),
                max(high.y, self.hands[index].high.y),
                max(high.z, self.hands[index].high.z),
            )
        self.low = low
        self.high = high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the canonical skin.

        Args:
            point: A point in the pelvis frame, in meters.

        Returns:
            The signed distance in meters, negative inside.
        """
        var d = self.body.distance(point)
        for index in range(2):  # pragma: no branch
            d = min(d, (point - self.eyes[index]).length() - self.eye_radius)
            # A hand box farther than the body cannot change the union.
            if (
                box_gap(self.hands[index].low, self.hands[index].high, point)
                < d
            ):
                d = min(d, self.hands[index].distance(point))
        return d

    def region(self, point: Vector3) -> BodyRegion:
        """Return the region a point belongs to under the canonical rule.

        Args:
            point: A point in the pelvis frame, in meters.

        Returns:
            A named region. A point outside the skin still has one.
        """
        var side = 0
        if point.x < 0:
            side = 1
        var past_wrist = (point - self.wrists[side]).dot(
            self.fore_axes[side]
        ) > 0
        var arm = self.body.right_arm.distance(point)
        if side == 1:
            arm = self.body.left_arm.distance(point)
        var trunk = min(
            self.body.torso.distance(point), self.body.lower.distance(point)
        )
        ref hand = self.hands[side]
        if _in_box(hand.low, hand.high, point):
            var d = hand.distance(point)
            # The hand skin is the nearest skin.
            if d < min(arm, trunk):
                if past_wrist:
                    return _side_region(RIGHT_HAND_REGION.value, side)
                return _side_region(RIGHT_FOREARM_REGION.value, side)
        if arm < trunk:
            if past_wrist:
                return _side_region(RIGHT_HAND_REGION.value, side)
            if (point - self.elbows[side]).dot(self.upper_axes[side]) > 0:
                return _side_region(RIGHT_FOREARM_REGION.value, side)
            return _side_region(RIGHT_UPPER_ARM_REGION.value, side)
        if point.y > self.neck_base:
            return HEAD_NECK_REGION
        if point.y >= self.hip:
            return TRUNK_REGION
        if point.y >= self.knees[side]:
            return _side_region(RIGHT_THIGH_REGION.value, side)
        if point.y >= self.malleoli[side]:
            return _side_region(RIGHT_SHANK_REGION.value, side)
        return _side_region(RIGHT_FOOT_REGION.value, side)


def _unit(v: Vector3) -> Vector3:
    """Return `v` scaled to unit length."""
    return v * (Float32(1) / v.length())


@fieldwise_init
struct BoneHit(ImplicitlyCopyable):
    """Which bone holds a point, its fill and the nearest bone surface."""

    var index: Int
    """The first bone that holds the point, or -1."""
    var fill: BoneOccupancy
    """The fill of that bone at the point, or `EMPTY`."""
    var nearest: Float32
    """The least signed distance to a bone whose box holds the point."""


struct CanonicalSkeleton(Copyable, Movable):
    """Every named bone field of one template, placed in the pelvis frame.

    The fields are the library's own, with no display widening. Bones
    have a global order: head, torso, both arms and hands, the pelvis,
    then the right and the left leg and foot.
    """

    var sweeps: List[SweepField]
    var shells: List[Float32]
    var pelvis: List[PelvisBoneField]
    var femurs: List[FemurField]
    var tibias: List[TibiaField]
    var fibulas: List[FibulaField]
    var patellas: List[PatellaField]
    var feet: List[FootBoneField]
    var names: List[String]
    var regions: List[BodyRegion]
    var offsets: List[Vector3]
    var lows: List[Vector3]
    var highs: List[Vector3]
    # Candidate bones per horizontal slab and side, so a point tests only
    # the boxes that can hold it.
    var slab: Float32
    var slab_low: Float32
    var slabs: Int
    var buckets: List[List[Int]]
    # The skull's index, the eyeball centers and the radius carved out of
    # the skull round each of them.
    var skull: Int
    var eyes: List[Vector3]
    var orbit: Float32

    def __init__(out self, spec: HumanoidSpec) raises:
        """Build and place every bone field for `spec`.

        Args:
            spec: The canonical input recipe.

        Raises:
            Error: If a bone template refuses the spec.
        """
        self.sweeps = List[SweepField]()
        self.shells = List[Float32]()
        self.pelvis = List[PelvisBoneField]()
        self.femurs = List[FemurField]()
        self.tibias = List[TibiaField]()
        self.fibulas = List[FibulaField]()
        self.patellas = List[PatellaField]()
        self.feet = List[FootBoneField]()
        self.names = List[String]()
        self.regions = List[BodyRegion]()
        self.offsets = List[Vector3]()
        self.lows = List[Vector3]()
        self.highs = List[Vector3]()
        self.slab = _SLAB
        self.slab_low = 0
        self.slabs = 0
        self.buckets = List[List[Int]]()
        self.skull = -1
        var stature = Float32(spec.stature.value)
        var head = head_muscle_dimensions(spec)
        self.eyes = [eye_center(head.head, RIGHT), eye_center(head.head, LEFT)]
        self.orbit = eye_radius(head.head) + Float32(ORBIT_CLEARANCE.value)
        for part in named_head_bones():  # pragma: no branch
            self._sweep(
                head_bone_field(head.head, part),
                HEAD_SHELL * stature,
                head_bone_label(part),
                HEAD_NECK_REGION,
            )
        var torso = head.head.torso.copy()
        for part in named_torso_bones():  # pragma: no branch
            var paired = is_paired_bone(part)
            for side in [RIGHT, LEFT]:  # pragma: no branch
                if side == LEFT and not paired:
                    continue
                var name = torso_bone_label(part)
                if paired:
                    name += _side_suffix(side)
                self._sweep(
                    torso_bone_field(torso, part, side),
                    TORSO_SHELL * stature,
                    name,
                    TRUNK_REGION,
                )
        var arms = arm_muscle_dimensions(spec)
        for s in range(2):  # pragma: no branch
            var side = RIGHT if s == 0 else LEFT
            for part in named_arm_bones():  # pragma: no branch
                var region = _side_region(RIGHT_FOREARM_REGION.value, s)
                if part == HUMERUS:
                    region = _side_region(RIGHT_UPPER_ARM_REGION.value, s)
                self._sweep(
                    arm_bone_field(arms.arm, part, side),
                    ARM_SHELL * stature,
                    arm_bone_label(part) + _side_suffix(side),
                    region,
                )
            for part in named_hand_bones():  # pragma: no branch
                self._sweep(
                    hand_bone_field(arms.arm, part, side),
                    HAND_SHELL * stature,
                    hand_bone_label(part) + _side_suffix(side),
                    _side_region(RIGHT_HAND_REGION.value, s),
                )
        var pelvis = assemble_pelvis(spec)
        for part in named_pelvis_bones():  # pragma: no branch
            var field = PelvisBoneField(pelvis.bones, part)
            self._place(
                pelvis_bone_label(part),
                TRUNK_REGION,
                Vector3(0, 0, 0),
                field.low,
                field.high,
            )
            self.pelvis.append(field^)
        for s in range(2):  # pragma: no branch
            var side = RIGHT if s == 0 else LEFT
            var origin = pelvis.leg_origin(side)
            var pose = assemble_leg(spec, side)
            var suffix = _side_suffix(side)
            var thigh = _side_region(RIGHT_THIGH_REGION.value, s)
            var shank = _side_region(RIGHT_SHANK_REGION.value, s)
            var femur = FemurField(pose.femur)
            self._place(
                "femur" + suffix,
                thigh,
                origin + pose.femur_origin,
                femur.low,
                femur.high,
            )
            self.femurs.append(femur)
            var patella = PatellaField(pose.patella)
            self._place(
                "patella" + suffix,
                thigh,
                origin + pose.patella_origin,
                patella.low,
                patella.high,
            )
            self.patellas.append(patella)
            var tibia = TibiaField(pose.tibia)
            self._place(
                "tibia" + suffix,
                shank,
                origin + pose.tibia_origin,
                tibia.low,
                tibia.high,
            )
            self.tibias.append(tibia)
            var fibula = FibulaField(pose.fibula)
            self._place(
                "fibula" + suffix,
                shank,
                origin + pose.fibula_origin,
                fibula.low,
                fibula.high,
            )
            self.fibulas.append(fibula)
            var foot = foot_muscle_dimensions(spec, side)
            var ankle = origin + pose.ankle_center()
            for part in named_foot_bones():  # pragma: no branch
                var bone = FootBoneField(foot.foot, part)
                self._place(
                    bone_part_label(part) + suffix,
                    _side_region(RIGHT_FOOT_REGION.value, s),
                    ankle,
                    bone.low,
                    bone.high,
                )
                self.feet.append(bone)
        self.skull = self.find("skull")
        self._index()

    def _sweep(
        mut self,
        var field: SweepField,
        shell: Float32,
        name: String,
        region: BodyRegion,
    ):
        """Add one swept bone, already in the pelvis frame."""
        self._place(name, region, Vector3(0, 0, 0), field.low, field.high)
        self.shells.append(shell)
        self.sweeps.append(field^)

    def _place(
        mut self,
        name: String,
        region: BodyRegion,
        offset: Vector3,
        low: Vector3,
        high: Vector3,
    ):
        """Record one bone's name, region, offset and pelvis-frame box."""
        self.names.append(name)
        self.regions.append(region)
        self.offsets.append(offset)
        self.lows.append(low + offset)
        self.highs.append(high + offset)

    def count(self) -> Int:
        """Return how many bones the skeleton holds.

        Returns:
            The number of named bone fields.
        """
        return len(self.names)

    def probe(
        self, index: Int, point: Vector3
    ) raises -> Tuple[Float32, BoneOccupancy]:
        """Return one bone's signed distance and fill at a point.

        Args:
            index: A bone in the global order.
            point: A point in the pelvis frame, in meters.

        Returns:
            The signed distance in meters, negative inside, and the fill
            under the bone family's own tissue rule.

        Raises:
            Error: If the index names no bone.
        """
        if index < 0 or index >= self.count():
            raise Error("A canonical bone index must name a bone")
        var local = point - self.offsets[index]
        if index < len(self.sweeps):
            var d = self.sweeps[index].distance(local)
            if index == self.skull:
                d = _carve(d, local, self.eyes, self.orbit)
            return (d, fill_at(d, self.shells[index]))
        var at = index - len(self.sweeps)
        if at < len(self.pelvis):
            return (
                self.pelvis[at].distance(local),
                pelvis_bone_field_occupancy(self.pelvis[at], local),
            )
        at -= len(self.pelvis)
        var side = at // _LEG_BONES
        var k = at % _LEG_BONES
        if k == 0:
            return (
                self.femurs[side].distance(local),
                femur_field_occupancy(self.femurs[side], local),
            )
        if k == 1:
            return (
                self.patellas[side].distance(local),
                patella_field_occupancy(self.patellas[side], local),
            )
        if k == 2:
            return (
                self.tibias[side].distance(local),
                tibia_field_occupancy(self.tibias[side], local),
            )
        if k == 3:
            return (
                self.fibulas[side].distance(local),
                fibula_field_occupancy(self.fibulas[side], local),
            )
        var foot = side * (_LEG_BONES - 4) + k - 4
        return (
            self.feet[foot].distance(local),
            foot_bone_field_occupancy(self.feet[foot], local),
        )

    def mesh(self, index: Int) raises -> BufferGeometry:
        """Mesh one bone on its own grid, in the pelvis frame.

        Args:
            index: A bone in the global order.

        Returns:
            The bone's surface, without display widening.

        Raises:
            Error: If the index names no bone, or the field has no surface.
        """
        if index < 0 or index >= self.count():
            raise Error("A canonical bone index must name a bone")
        var name = self.names[index]
        var geometry: BufferGeometry
        if index == self.skull:
            ref bone = self.sweeps[index]
            var carved = OrbitedSkull(bone.copy(), self.eyes.copy(), self.orbit)
            geometry = mesh_field(
                carved, bone.low, bone.high, BONE_DETAIL, name
            )
            return geometry^
        if index < len(self.sweeps):
            ref bone = self.sweeps[index]
            geometry = mesh_field(bone, bone.low, bone.high, BONE_DETAIL, name)
            return geometry^
        var at = index - len(self.sweeps)
        if at < len(self.pelvis):
            ref bone = self.pelvis[at]
            geometry = mesh_field(bone, bone.low, bone.high, BONE_DETAIL, name)
            return _placed(geometry^, self.offsets[index])
        at -= len(self.pelvis)
        var side = at // _LEG_BONES
        var k = at % _LEG_BONES
        if k == 0:
            ref bone = self.femurs[side]
            geometry = mesh_field(bone, bone.low, bone.high, BONE_DETAIL, name)
        elif k == 1:
            ref bone = self.patellas[side]
            geometry = mesh_field(bone, bone.low, bone.high, BONE_DETAIL, name)
        elif k == 2:
            ref bone = self.tibias[side]
            geometry = mesh_field(bone, bone.low, bone.high, BONE_DETAIL, name)
        elif k == 3:
            ref bone = self.fibulas[side]
            geometry = mesh_field(bone, bone.low, bone.high, BONE_DETAIL, name)
        else:
            ref bone = self.feet[side * (_LEG_BONES - 4) + k - 4]
            geometry = mesh_field(bone, bone.low, bone.high, BONE_DETAIL, name)
        return _placed(geometry^, self.offsets[index])

    def find(self, name: String) raises -> Int:
        """Return the global index of a named bone.

        Args:
            name: A bone name, for example `skull` or `femur right`.

        Returns:
            The bone's index.

        Raises:
            Error: If no bone has that name.
        """
        for index in range(self.count()):  # pragma: no branch
            if self.names[index] == name:
                return index
        raise Error("No canonical bone is named " + name)

    def nearest(self, point: Vector3) raises -> Int:
        """Return the bone whose surface lies nearest a point.

        Only bones whose boxes hold the point are measured.

        Args:
            point: A point in the pelvis frame, in meters.

        Returns:
            The bone's index.

        Raises:
            Error: If no bone box holds the point.
        """
        var best = -1
        var least = Float32(1e30)
        for index in range(self.count()):  # pragma: no branch
            if _in_box(self.lows[index], self.highs[index], point):
                var d, _ = self.probe(index, point)
                if abs(d) < least:
                    least = abs(d)
                    best = index
        if best < 0:
            raise Error("No canonical bone box holds the point")
        return best

    def _bucket(self, point: Vector3) -> Int:
        """Return the candidate list of a point, or -1 off every slab."""
        var slab = Int((point.y - self.slab_low) / self.slab)
        if point.y < self.slab_low or slab >= self.slabs:
            return -1
        if point.x < 0:
            return 2 * slab + 1
        return 2 * slab

    def _index(mut self):
        """Sort each bone into the slab and side lists its box reaches."""
        var low = Float32(1e30)
        var high = Float32(-1e30)
        for index in range(self.count()):  # pragma: no branch
            low = min(low, self.lows[index].y)
            high = max(high, self.highs[index].y)
        self.slab_low = low
        self.slabs = Int((high - low) / self.slab) + 1
        self.buckets = List[List[Int]](length=2 * self.slabs, fill=List[Int]())
        for index in range(self.count()):  # pragma: no branch
            var first = Int((self.lows[index].y - low) / self.slab)
            var last = Int((self.highs[index].y - low) / self.slab)
            for slab in range(first, last + 1):  # pragma: no branch
                if self.highs[index].x >= 0:
                    self.buckets[2 * slab].append(index)
                if self.lows[index].x < 0:
                    self.buckets[2 * slab + 1].append(index)

    def locate(self, point: Vector3) raises -> BoneHit:
        """Return the first bone that holds a point and the nearest surface.

        Args:
            point: A point in the pelvis frame, in meters.

        Returns:
            The bone index, its fill, and the least distance to a bone
            whose box holds the point. A point in no box is `_FAR` away.

        Raises:
            Error: If a bone index is out of range.
        """
        var hit = BoneHit(-1, EMPTY, _FAR)
        var bucket = self._bucket(point)
        if bucket < 0:
            return hit
        for index in self.buckets[bucket]:  # pragma: no branch
            if _in_box(self.lows[index], self.highs[index], point):
                var d, fill = self.probe(index, point)
                hit.nearest = min(hit.nearest, d)
                # The first bone that holds the point owns it.
                if fill != EMPTY:
                    hit.index = index
                    hit.fill = fill
                    return hit
        return hit


def _carve(
    d: Float32, point: Vector3, eyes: List[Vector3], radius: Float32
) -> Float32:
    """Remove a ball of `radius` round each eye from a bone distance."""
    var carved = d
    for index in range(len(eyes)):  # pragma: no branch
        carved = max(carved, radius - (point - eyes[index]).length())
    return carved


struct OrbitedSkull(Copyable, DistanceField, Movable):
    """The skull field with each eyeball and its clearance carved out.

    The library skull keeps shallow orbits, so an eyeball reaches into
    its face block. The canonical skull follows the eyes instead: the
    eye genes and the face-shape eye shifts move the carved orbit with
    the eye.
    """

    var skull: SweepField
    var eyes: List[Vector3]
    var radius: Float32

    def __init__(
        out self,
        var skull: SweepField,
        var eyes: List[Vector3],
        radius: Float32,
    ):
        """Carve a skull.

        Args:
            skull: The library skull field.
            eyes: The eyeball centers, in meters.
            radius: The eyeball radius plus the clearance, in meters.
        """
        self.skull = skull^
        self.eyes = eyes^
        self.radius = radius

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the carved skull.

        Args:
            point: A point in the pelvis frame, in meters.

        Returns:
            The signed distance in meters, negative inside.
        """
        return _carve(self.skull.distance(point), point, self.eyes, self.radius)


def _side_suffix(side: BodySide) -> String:
    """Return the name suffix of a side."""
    if side == LEFT:
        return " left"
    return " right"


def _placed(
    var geometry: BufferGeometry, offset: Vector3
) raises -> BufferGeometry:
    """Return a mesh moved from its local frame by `offset`."""
    geometry.translate(
        Length(offset.x, METER),
        Length(offset.y, METER),
        Length(offset.z, METER),
    )
    return geometry^


struct CanonicalPart(Movable):
    """One canonical part: its region, its tissue, its mesh and properties."""

    var region: BodyRegion
    var tissue: CanonicalTissue
    var geometry: BufferGeometry
    """A closed surface in the pelvis frame, in meters."""
    var volume: Volume
    """The sampled volume of the part."""
    var inertia: SegmentInertia
    """Mass, center and full tensor about the center; length is zero."""

    def __init__(
        out self,
        region: BodyRegion,
        tissue: CanonicalTissue,
        var geometry: BufferGeometry,
        volume: Volume,
        inertia: SegmentInertia,
    ):
        """Hold one part.

        Args:
            region: Its named region.
            tissue: Its named tissue label.
            geometry: Its mesh.
            volume: Its sampled volume.
            inertia: Its sampled mass properties.
        """
        self.region = region
        self.tissue = tissue
        self.geometry = geometry^
        self.volume = volume
        self.inertia = inertia


struct CanonicalBody(Movable):
    """The 28 canonical parts of one template and their whole-body sum."""

    var spec: HumanoidSpec
    var step: Length
    var parts: List[CanonicalPart]
    var whole: SegmentInertia
    """Mass properties of the union of every part."""
    var envelope: CanonicalEnvelope
    """The skin fields and the region rule the parts came from."""
    var skeleton: CanonicalSkeleton
    """Every bone field the parts came from."""

    def __init__(
        out self,
        spec: HumanoidSpec,
        step: Length,
        var parts: List[CanonicalPart],
        whole: SegmentInertia,
        var envelope: CanonicalEnvelope,
        var skeleton: CanonicalSkeleton,
    ):
        """Hold a generated body.

        Args:
            spec: The canonical input recipe.
            step: The property grid step.
            parts: The 28 parts, in `part_index` order.
            whole: The whole-body mass properties.
            envelope: The skin fields and the region rule.
            skeleton: The bone fields.
        """
        self.spec = spec
        self.step = step
        self.parts = parts^
        self.whole = whole
        self.envelope = envelope^
        self.skeleton = skeleton^


def check_canonical_step(step: Length) raises:
    """Refuse a grid step outside the bounded canonical range.

    Args:
        step: The property grid step.

    Raises:
        Error: If the step is not finite or lies outside 5 mm to 10 mm.
    """
    if not isfinite(step.value):
        raise Error("A canonical grid step must be finite")
    if step.value < MIN_CANONICAL_STEP.value:
        raise Error("A canonical grid step must be at least 5 mm")
    if step.value > MAX_CANONICAL_STEP.value:
        raise Error("A canonical grid step must be at most 10 mm")


def canonical_body(
    spec: HumanoidSpec, step: Length = CANONICAL_STEP
) raises -> CanonicalBody:
    """Generate the canonical parts of a template from its fields.

    The grid is symmetric about the midsagittal plane, and no vertex lies
    on it. Each vertex stands for one cubic cell of `step` width.

    Args:
        spec: The canonical input recipe.
        step: The property grid step, 5 mm through 10 mm.

    Returns:
        The 28 parts in `part_index` order and the whole-body properties.

    Raises:
        Error: If the spec or the step is refused, or a mesh or a tensor
            cannot be formed.
    """
    _ = spec_fingerprint(spec)
    check_canonical_step(step)
    var h = Float32(step.value)
    var envelope = CanonicalEnvelope(spec)
    var skeleton = CanonicalSkeleton(spec)
    var low = envelope.low
    var high = envelope.high
    for index in range(skeleton.count()):  # pragma: no branch
        low = Vector3(
            min(low.x, skeleton.lows[index].x),
            min(low.y, skeleton.lows[index].y),
            min(low.z, skeleton.lows[index].z),
        )
        high = Vector3(
            max(high.x, skeleton.highs[index].x),
            max(high.y, skeleton.highs[index].y),
            max(high.z, skeleton.highs[index].z),
        )
    var half = Int(ceil(max(-low.x, high.x) / h)) + 1
    var nx = 2 * half
    var ny = Int(ceil((high.y - low.y) / h)) + 3
    var nz = Int(ceil((high.z - low.z) / h)) + 3
    var origin = Vector3(
        (Float32(0.5) - Float32(half)) * h, low.y - h, low.z - h
    )
    var count = nx * ny * nz
    var skin = List[Float32](length=count, fill=_FAR)
    var bones = List[Float32](length=count, fill=_FAR)
    var labels = List[Int](length=count, fill=-1)
    var tallies = List[InertiaTally]()
    var volumes = List[Float64](length=PART_COUNT, fill=0)
    for _ in range(PART_COUNT):  # pragma: no branch
        tallies.append(InertiaTally())
    var boxes = List[Int](length=REGION_COUNT * 6, fill=-1)
    var cell = Float64(h) * Float64(h) * Float64(h)
    var widths = Vector3(h, h, h)
    var soft = Float64(muscle_tissue().wet_density.value)
    var marrow = Float64(adipose_tissue().wet_density.value)
    var cortical = cortical_tissue()
    var trabecular = trabecular_tissue()
    var margin = _MARGIN_STEPS * h
    # A coarse pass skips each block whose corners all lie far outside
    # the skin, with room for a field that is not an exact distance.
    var reach = _REACH * Float32(_BLOCK) * h
    var cx = (nx - 1) // _BLOCK + 1
    var cy = (ny - 1) // _BLOCK + 1
    var cz = (nz - 1) // _BLOCK + 1
    var coarse = List[Float32](capacity=(cx + 1) * (cy + 1) * (cz + 1))
    for kz in range(cz + 1):  # pragma: no branch
        for ky in range(cy + 1):  # pragma: no branch
            for kx in range(cx + 1):  # pragma: no branch
                coarse.append(
                    envelope.distance(
                        origin
                        + Vector3(
                            Float32(min(kx * _BLOCK, nx - 1)) * h,
                            Float32(min(ky * _BLOCK, ny - 1)) * h,
                            Float32(min(kz * _BLOCK, nz - 1)) * h,
                        )
                    )
                )
    for bz in range(cz):  # pragma: no branch
        for by in range(cy):  # pragma: no branch
            for bx in range(cx):  # pragma: no branch
                var least = Float32(_FAR)
                for corner in range(8):  # pragma: no branch
                    var kx = bx + (corner & 1)
                    var ky = by + ((corner >> 1) & 1)
                    var kz = bz + ((corner >> 2) & 1)
                    least = min(
                        least, coarse[(kz * (cy + 1) + ky) * (cx + 1) + kx]
                    )
                if least > reach:
                    continue
                for iz in range(
                    bz * _BLOCK, min((bz + 1) * _BLOCK, nz)
                ):  # pragma: no branch
                    for iy in range(
                        by * _BLOCK, min((by + 1) * _BLOCK, ny)
                    ):  # pragma: no branch
                        for ix in range(
                            bx * _BLOCK, min((bx + 1) * _BLOCK, nx)
                        ):  # pragma: no branch
                            var v = (iz * ny + iy) * nx + ix
                            var p = origin + Vector3(
                                Float32(ix) * h,
                                Float32(iy) * h,
                                Float32(iz) * h,
                            )
                            var e = envelope.distance(p)
                            var hit = skeleton.locate(p)
                            skin[v] = e
                            bones[v] = hit.nearest
                            if e < margin:
                                labels[v] = envelope.region(p).value
                            if hit.index >= 0:
                                var at = part_index(
                                    skeleton.regions[hit.index], BONE_TISSUE
                                )
                                var rho = Float64(
                                    apparent_density_of(
                                        hit.fill, cortical, trabecular
                                    ).value
                                )
                                if hit.fill == MARROW:
                                    rho = marrow
                                tallies[at].add_cell(rho * cell, p, widths)
                                volumes[at] += cell
                                continue
                            if e < 0:
                                var at = part_index(
                                    BodyRegion(labels[v]), SOFT_TISSUE
                                )
                                tallies[at].add_cell(soft * cell, p, widths)
                                volumes[at] += cell
                                _grow(boxes, labels[v], ix, iy, iz)
    var parts = List[CanonicalPart]()
    var whole = InertiaTally()
    for region in named_body_regions():  # pragma: no branch
        for tissue in [SOFT_TISSUE, BONE_TISSUE]:  # pragma: no branch
            var at = part_index(region, tissue)
            var geometry: BufferGeometry
            if tissue == BONE_TISSUE:
                var own = List[BufferGeometry]()
                for index in range(skeleton.count()):  # pragma: no branch
                    if skeleton.regions[index] == region:
                        own.append(skeleton.mesh(index))
                geometry = merge_geometries(own)
            else:
                geometry = _soft_mesh(
                    skin, bones, labels, boxes, region, origin, h, nx, ny
                )
            whole.add(tallies[at])
            parts.append(
                CanonicalPart(
                    region,
                    tissue,
                    geometry^,
                    Volume(Float32(volumes[at]), CUBIC_METER),
                    tallies[at].result(0),
                )
            )
    return CanonicalBody(
        spec,
        step,
        parts^,
        whole.result(0),
        envelope^,
        skeleton^,
    )


def _grow(mut boxes: List[Int], region: Int, ix: Int, iy: Int, iz: Int):
    """Grow a region's index box to hold one vertex."""
    var at = region * 6
    if boxes[at] < 0:
        boxes[at] = ix
        boxes[at + 1] = iy
        boxes[at + 2] = iz
        boxes[at + 3] = ix
        boxes[at + 4] = iy
        boxes[at + 5] = iz
        return
    boxes[at] = min(boxes[at], ix)
    boxes[at + 1] = min(boxes[at + 1], iy)
    boxes[at + 2] = min(boxes[at + 2], iz)
    boxes[at + 3] = max(boxes[at + 3], ix)
    boxes[at + 4] = max(boxes[at + 4], iy)
    boxes[at + 5] = max(boxes[at + 5], iz)


def _soft_mesh(
    skin: List[Float32],
    bones: List[Float32],
    labels: List[Int],
    boxes: List[Int],
    region: BodyRegion,
    origin: Vector3,
    h: Float32,
    nx: Int,
    ny: Int,
) raises -> BufferGeometry:
    """Mesh one region's soft part from the shared grid samples.

    The part is the skin, cut to the region and with every bone removed:
    the larger of the skin distance, a region clip and the negated bone
    distance. The clip is half a step inside or outside, so a cut face
    lies midway between grid vertices of two regions.
    """
    var at = region.value * 6
    # Every region holds soft vertices, and the grid keeps a ring of
    # outside vertices, so the box grows by one vertex on each side.
    var x0 = boxes[at] - 1
    var y0 = boxes[at + 1] - 1
    var z0 = boxes[at + 2] - 1
    var sx = boxes[at + 3] - x0 + 2
    var sy = boxes[at + 4] - y0 + 2
    var sz = boxes[at + 5] - z0 + 2
    var samples = List[Float32](capacity=sx * sy * sz)
    for iz in range(z0, z0 + sz):  # pragma: no branch
        for iy in range(y0, y0 + sy):  # pragma: no branch
            for ix in range(x0, x0 + sx):  # pragma: no branch
                var v = (iz * ny + iy) * nx + ix
                var clip = Float32(0.5) * h
                if labels[v] == region.value:
                    clip = -clip
                samples.append(max(skin[v], max(clip, -bones[v])))
    var low = origin + Vector3(
        Float32(x0) * h, Float32(y0) * h, Float32(z0) * h
    )
    var grid = SampleGrid(
        sx - 1,
        sy - 1,
        sz - 1,
        h,
        h,
        h,
        sx,
        sy,
        sz,
        Float32(sy - 1) * h,
    )
    return mesh_samples(samples, low, grid, part_label(region, SOFT_TISSUE))


def geometry_digest(geometry: BufferGeometry) raises -> String:
    """Return the FNV-1a digest of a mesh's positions and index.

    Each count and index is eight little-endian bytes. Each coordinate is
    the four little-endian bytes of its float32 bit pattern.

    Args:
        geometry: A mesh with a `position` attribute.

    Returns:
        Sixteen lowercase hexadecimal digits. Not a cryptographic hash.

    Raises:
        Error: If the mesh has no positions.
    """
    ref positions = geometry.attribute_view(String(POSITION))
    var hash = _fnv_int(FNV1A_OFFSET, positions.count())
    for v in range(positions.count()):  # pragma: no branch
        for c in range(3):  # pragma: no branch
            hash = _fnv_bits(
                hash, bitcast[DType.uint32](positions.component(v, c))
            )
    hash = _fnv_int(hash, len(geometry.index))
    for entry in geometry.index:  # pragma: no branch
        hash = _fnv_int(hash, entry)
    return fingerprint_hex(hash)


def _fnv_int(hash: UInt64, value: Int) -> UInt64:
    """Fold eight little-endian bytes of `value` into a digest."""
    var state = hash
    var bits = UInt64(value)
    for at in range(8):  # pragma: no branch
        state = fnv1a_step(state, UInt8((bits >> UInt64(8 * at)) & 0xFF))
    return state


def _fnv_bits(hash: UInt64, bits: UInt32) -> UInt64:
    """Fold four little-endian bytes of a float32 bit pattern."""
    var state = hash
    for at in range(4):  # pragma: no branch
        state = fnv1a_step(state, UInt8((bits >> UInt32(8 * at)) & 0xFF))
    return state


def _tensor(inertia: SegmentInertia) -> String:
    """Return the six tensor entries as a JSON array."""
    return (
        "["
        + String(inertia.xx.value)
        + ","
        + String(inertia.yy.value)
        + ","
        + String(inertia.zz.value)
        + ","
        + String(inertia.xy.value)
        + ","
        + String(inertia.xz.value)
        + ","
        + String(inertia.yz.value)
        + "]"
    )


def _point(p: Vector3) -> String:
    """Return a point as a JSON array."""
    return "[" + String(p.x) + "," + String(p.y) + "," + String(p.z) + "]"


def _properties(
    mut data: UserData, inertia: SegmentInertia, volume: Volume
) raises:
    """Write one set of SI mass properties."""
    data.set_number("volume_m3", Float64(volume.value))
    data.set_number("mass_kg", Float64(inertia.mass.value))
    data.set_json("center_m", _point(inertia.center))
    data.set_json("inertia_kg_m2", _tensor(inertia))


def canonical_record(body: CanonicalBody) raises -> UserData:
    """Return a versioned record of every canonical part.

    The record holds the complete canonical inputs, the frame, the units,
    the grid step, each part's tissue rule, mesh digest and properties,
    and the whole-body properties. It holds no visual setting, so a
    visual, decimated or baked derivative cannot change it.

    Args:
        body: A body from `canonical_body`.

    Returns:
        The record, with a fingerprint of its parts.

    Raises:
        Error: If the spec or a part mesh is invalid.
    """
    var parts = UserData()
    var volume = Float64(0)
    for index in range(len(body.parts)):  # pragma: no branch
        var part = UserData()
        part.set_string("region", region_label(body.parts[index].region))
        part.set_string("tissue", tissue_label(body.parts[index].tissue))
        if body.parts[index].tissue == BONE_TISSUE:
            part.set_string("density_rule", String(BONE_DENSITY_RULE))
        else:
            part.set_string("density_rule", String(SOFT_DENSITY_RULE))
        part.set_number(
            "vertices", Float64(body.parts[index].geometry.vertex_count())
        )
        part.set_number(
            "triangles", Float64(body.parts[index].geometry.triangle_count())
        )
        part.set_string(
            "geometry_digest", geometry_digest(body.parts[index].geometry)
        )
        _properties(part, body.parts[index].inertia, body.parts[index].volume)
        volume += Float64(body.parts[index].volume.value)
        parts.set_json(
            part_label(body.parts[index].region, body.parts[index].tissue),
            part.to_json(),
        )
    var whole = UserData()
    _properties(whole, body.whole, Volume(Float32(volume), CUBIC_METER))
    var record = UserData()
    record.set_number("schema_version", CANONICAL_PARTS_SCHEMA)
    record.set_string("revision", String(CANONICAL_PARTS_REVISION))
    record.set_json("canonical_inputs", canonical_inputs(body.spec).to_json())
    record.set_string("spec_fingerprint", spec_fingerprint(body.spec))
    record.set_number("step_m", Float64(body.step.value))
    record.set_number("bone_detail", BONE_DETAIL)
    record.set_number("bones", Float64(body.skeleton.count()))
    record.set_string("length_unit", "meter")
    record.set_string("mass_unit", "kilogram")
    record.set_string("handedness", "right")
    record.set_string("up_axis", "+y")
    record.set_string("right_axis", "+x")
    record.set_string("anterior_axis", "+z")
    record.set_string("origin", "pelvis-frame-origin")
    record.set_string(
        "tensor_convention",
        (
            "xx,yy,zz,xy,xz,yz about each center; off-diagonals are minus the"
            " products of inertia"
        ),
    )
    record.set_string(
        "independent_of",
        "visual widening, leg parting, decimation, skin weights and bakes",
    )
    record.set_json("parts", parts.to_json())
    record.set_json("whole_body", whole.to_json())
    record.set_string("parts_digest", json_fingerprint(record.json("parts")))
    return record^


def require_canonical_record(stored: UserData, expected: UserData) raises:
    """Refuse a stored canonical record that does not match a fresh one.

    Args:
        stored: Data that holds a record under `CANONICAL_PARTS_KEY`.
        expected: `canonical_record` of a body generated now for the
            expected spec and step.

    Raises:
        Error: If the record is absent, of another schema or revision,
            for another spec or step, or changed in any field.
    """
    if not stored.has(String(CANONICAL_PARTS_KEY)):
        raise Error("No canonical parts record; regenerate it")
    var document = parse_json(stored.json(String(CANONICAL_PARTS_KEY)))
    var record = user_data_of(document, document.root())
    for key in [  # pragma: no branch
        "schema_version",
        "revision",
        "spec_fingerprint",
        "step_m",
        "parts_digest",
    ]:
        if not record.has(key):
            raise Error("The canonical parts record is incomplete")
    if record.json("schema_version") != expected.json("schema_version"):
        raise Error("The canonical parts schema is unsupported; regenerate it")
    if record.string("revision") != expected.string("revision"):
        raise Error("The canonical parts revision changed; regenerate it")
    if record.string("spec_fingerprint") != expected.string("spec_fingerprint"):
        raise Error("The canonical parts represent another spec")
    if record.json("step_m") != expected.json("step_m"):
        raise Error("The canonical parts use another grid step")
    if record.to_json() != expected.to_json():
        raise Error("The canonical parts record is stale or changed")


def require_part_geometry(
    body: CanonicalBody,
    region: BodyRegion,
    tissue: CanonicalTissue,
    geometry: BufferGeometry,
) raises:
    """Refuse a mesh that would stand in for a canonical part.

    A visual, widened, decimated or baked mesh has another digest. It can
    never become a part's mass or contact geometry.

    Args:
        body: A canonical body.
        region: The part's named region.
        tissue: The part's named tissue label.
        geometry: The mesh offered as the part's geometry.

    Raises:
        Error: If the region or tissue is not named, or the mesh differs
            from the part's own geometry.
    """
    var at = part_index(region, tissue)
    if geometry_digest(geometry) != geometry_digest(body.parts[at].geometry):
        raise Error(
            "Only the canonical "
            + part_label(region, tissue)
            + " mesh is its mass and contact geometry"
        )
