# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Versioned maps between canonical parts and visual meshes, with fit checks.

Each map names its kind, its own revision, the canonical record it reads
and the visual topology it was built for. `require_mapping` refuses a map
when any of them changes. A map never writes into the canonical record.

| Map | Supported | Refused |
|---|---|---|
| Identity | Shared spec; eyes, carved orbits and skin follow the eye genes; per-region tissue clearance | A region whose bones cross the skin; a whole body while any region fails |
| Expression and jaw | `jawOpen` as a fitted rigid hinge of the canonical mandible and lower teeth | Every other expression shape |
| Skin weights | A fixed joint-to-region table and its measured agreement | Weights as a tissue or mass map |
| LOD | Nearest full-mesh vertex of each reduced vertex | A reduced mesh as a mass or contact geometry |
| Dental | Each dentition with itself | `BONES` to `MOUTH`: no tested correspondence |

    var body = canonical_body(person)
    var fit = identity_fit(body)
    require_tissue_clearance(fit, HEAD_NECK_REGION)
    var jaw = jaw_coupling(person)
    var open = jaw.canonical_point(incisor, 0.5)

These are template checks. They are not anatomical, biomechanical or
clinical validation.
"""

from core.buffer_geometry import POSITION, BufferGeometry
from core.user_data import UserData, user_data_of
from extensions.humanoid.canonical import (
    BONE_TISSUE,
    HEAD_NECK_REGION,
    LEFT_FOOT_REGION,
    LEFT_FOREARM_REGION,
    LEFT_HAND_REGION,
    LEFT_SHANK_REGION,
    LEFT_THIGH_REGION,
    LEFT_UPPER_ARM_REGION,
    REGION_COUNT,
    RIGHT_FOOT_REGION,
    RIGHT_FOREARM_REGION,
    RIGHT_HAND_REGION,
    RIGHT_SHANK_REGION,
    RIGHT_THIGH_REGION,
    RIGHT_UPPER_ARM_REGION,
    TRUNK_REGION,
    BodyRegion,
    CanonicalBody,
    CanonicalEnvelope,
    geometry_digest,
    named_body_regions,
    part_index,
    region_label,
)
from extensions.humanoid.fidelity import (
    MAPPING_REVISION,
    FNV1A_OFFSET,
    fingerprint_hex,
    fnv1a_step,
    json_fingerprint,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    HIPS,
    LEFT_FOOT,
    LEFT_FOREARM,
    LEFT_HAND,
    LEFT_SHIN,
    LEFT_THIGH,
    LEFT_TOES,
    LEFT_UPPER_ARM,
    NECK,
    RIGHT_FOOT,
    RIGHT_FOREARM,
    RIGHT_HAND,
    RIGHT_SHIN,
    RIGHT_THIGH,
    RIGHT_TOES,
    RIGHT_UPPER_ARM,
    SPINE,
    Joint,
)
from extensions.humanoid.skeleton.head.contents import HeadContents
from extensions.humanoid.skeleton.head.face_model import TEETH
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.head.skin.mouth import mouth_mesh
from extensions.humanoid.spec import HumanoidSpec
from loaders.json import parse_json
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from std.math import atan2, cos, max, min, pi, round, sin, sqrt
from units.si import RADIAN, Angle, Length, METER, MILLIMETER

comptime MAPPING_KEY = "threemojo_canonical_visual_map"
comptime MAPPING_SCHEMA = 1
# A bone mesh vertex lies on a marching grid of at least 24 cells along
# the bone, so it may stand this far off the true surface.
comptime CLEARANCE_TOLERANCE = Length(0.5, MILLIMETER)
# The one expression shape with a canonical coupling.
comptime JAW_SHAPE = "jawOpen"
# Points sampled on each eyeball.
comptime EYE_SAMPLES = 128
# A vertex the jaw shape moves by more than this share of the largest
# move belongs to the lower dentition.
comptime _MOVING_SHARE = Float32(0.5)
# The least rotation a hinge fit accepts, in radians.
comptime _LEAST_TURN = Float32(1.0e-4)
# Weld cells per meter for the clearance pass: 10 micrometers each.
comptime _WELD = Float32(1.0e5)
# The cell of the nearest-vertex search, in meters.
comptime _CELL = Float32(0.01)
comptime _MAP_LABELS: List[String] = [
    "identity",
    "expression-jaw",
    "skin-weight",
    "lod",
    "dental",
]


@fieldwise_init
struct MappingKind(Equatable, ImplicitlyCopyable, Writable):
    """Which canonical-to-visual map a record holds.

    The type stops a bare integer at compile time. A value that is not a
    named kind is still constructible, and each boundary refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is a named map kind.

        Returns:
            True for the five named kinds.
        """
        return self.value >= 0 and self.value <= DENTAL_MAP.value


comptime IDENTITY_MAP = MappingKind(0)
comptime EXPRESSION_JAW_MAP = MappingKind(1)
comptime SKIN_WEIGHT_MAP = MappingKind(2)
comptime LOD_MAP = MappingKind(3)
comptime DENTAL_MAP = MappingKind(4)


@fieldwise_init
struct Dentition(Equatable, ImplicitlyCopyable, Writable):
    """One of the two separate tooth representations.

    `BONES_DENTITION` is the authored anatomical teeth field. The
    `MOUTH_DENTITION` is the scanned expression teeth. `ALL` draws both,
    as an overlay: it is not a third dentition.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is a named dentition.

        Returns:
            True for `BONES_DENTITION` and `MOUTH_DENTITION`.
        """
        return self == BONES_DENTITION or self == MOUTH_DENTITION


comptime BONES_DENTITION = Dentition(0)
comptime MOUTH_DENTITION = Dentition(1)


def mapping_label(kind: MappingKind) raises -> String:
    """Return the stable label of a map kind.

    Args:
        kind: A named map kind.

    Returns:
        A lowercase label, for example `expression-jaw`.

    Raises:
        Error: If the kind is not named.
    """
    if not kind.is_valid():
        raise Error("A canonical-to-visual map kind must be named")
    return materialize[_MAP_LABELS]()[kind.value]


def dentition_label(dentition: Dentition) raises -> String:
    """Return the stable label of a dentition.

    Args:
        dentition: A named dentition.

    Returns:
        `bones` or `mouth`.

    Raises:
        Error: If the dentition is not named.
    """
    if not dentition.is_valid():
        raise Error("A dentition must be BONES or MOUTH")
    if dentition == MOUTH_DENTITION:
        return "mouth"
    return "bones"


def head_dentitions(contents: HeadContents) raises -> List[Dentition]:
    """Return the separate dentitions a head layer set draws.

    Args:
        contents: A named head layer set.

    Returns:
        `BONES_DENTITION` when the bones are drawn, then
        `MOUTH_DENTITION` when the mouth is drawn. `ALL` returns both:
        an overlay of two representations, not one coupled dentition.

    Raises:
        Error: If the layer set is not named.
    """
    var dentitions = List[Dentition]()
    if contents.includes_bones():
        dentitions.append(BONES_DENTITION)
    if contents.includes_mouth():
        dentitions.append(MOUTH_DENTITION)
    return dentitions^


def require_dental_correspondence(source: Dentition, target: Dentition) raises:
    """Refuse a correspondence between the two separate dentitions.

    Each dentition maps to itself. No tested map joins them, so a caller
    cannot transfer a tooth, a contact or a load from one to the other.

    Args:
        source: The dentition a value comes from.
        target: The dentition it would go to.

    Raises:
        Error: If either is not named, or they differ.
    """
    var a = dentition_label(source)
    var b = dentition_label(target)
    if source != target:
        raise Error(
            "No tested correspondence joins the "
            + a
            + " and "
            + b
            + " dentitions; keep them separate"
        )


def dentition_mesh(
    body: CanonicalBody, dentition: Dentition
) raises -> BufferGeometry:
    """Return one dentition's mesh, in the pelvis frame.

    Args:
        body: A canonical body.
        dentition: A named dentition.

    Returns:
        The authored teeth field's mesh, or the scanned teeth.

    Raises:
        Error: If the dentition is not named, or a mesh cannot be formed.
    """
    _ = dentition_label(dentition)
    if dentition == MOUTH_DENTITION:
        return mouth_mesh(head_muscle_dimensions(body.spec), TEETH)
    return body.skeleton.mesh(body.skeleton.find("teeth"))


def topology_digest(geometry: BufferGeometry) raises -> String:
    """Return the FNV-1a digest of a mesh's topology.

    The digest covers the vertex count and every index entry, as eight
    little-endian bytes each. A pose, a morph or a skin weight does not
    change it. A decimation, a reorder or a new vertex does.

    Args:
        geometry: A mesh with a `position` attribute.

    Returns:
        Sixteen lowercase hexadecimal digits. Not a cryptographic hash.

    Raises:
        Error: If the mesh has no positions.
    """
    var hash = _fnv_int(FNV1A_OFFSET, geometry.vertex_count())
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


struct RegionMap(Movable):
    """The canonical region and skin clearance of each visual vertex."""

    var regions: List[BodyRegion]
    """The region of each vertex under the canonical rule."""
    var clearance: List[Float32]
    """The canonical skin distance of each vertex, in meters."""

    def __init__(
        out self, var regions: List[BodyRegion], var clearance: List[Float32]
    ):
        """Hold a region map.

        Args:
            regions: One region per vertex.
            clearance: One signed distance per vertex, in meters.
        """
        self.regions = regions^
        self.clearance = clearance^

    def count(self, region: BodyRegion) raises -> Int:
        """Return how many vertices a region holds.

        Args:
            region: A named region.

        Returns:
            The number of vertices mapped to it.

        Raises:
            Error: If the region is not named.
        """
        _ = region_label(region)
        var total = 0
        for index in range(len(self.regions)):  # pragma: no branch
            if self.regions[index] == region:
                total += 1
        return total

    def gap(self) -> Length:
        """Return the largest distance of a vertex from the canonical skin.

        Returns:
            The largest absolute clearance.
        """
        var largest = Float32(0)
        for value in self.clearance:  # pragma: no branch
            largest = max(largest, abs(value))
        return Length(largest, METER)


def region_map(
    envelope: CanonicalEnvelope, geometry: BufferGeometry
) raises -> RegionMap:
    """Map each vertex of a visual mesh to a canonical region.

    The map reads the vertex positions in the pelvis frame. It does not
    move a canonical part or change a canonical property.

    Args:
        envelope: The canonical skin and region rule, as `CanonicalBody`
            holds it.
        geometry: A visual mesh in the pelvis frame.

    Returns:
        The region and the signed skin clearance of every vertex.

    Raises:
        Error: If the mesh has no positions.
    """
    ref positions = geometry.attribute_view(String(POSITION))
    var regions = List[BodyRegion](capacity=positions.count())
    var clearance = List[Float32](capacity=positions.count())
    for v in range(positions.count()):  # pragma: no branch
        var p = positions.vector3(v)
        regions.append(envelope.region(p))
        clearance.append(envelope.distance(p))
    return RegionMap(regions^, clearance^)


def _key(p: Vector3) -> Int:
    """Return the search cell of a point, as one integer."""
    var i = Int(p.x / _CELL + 4096)
    var j = Int(p.y / _CELL + 4096)
    var k = Int(p.z / _CELL + 4096)
    return (i * 8192 + j) * 8192 + k


def lod_map(full: BufferGeometry, reduced: BufferGeometry) raises -> List[Int]:
    """Map each vertex of a reduced mesh to the nearest full-mesh vertex.

    Ties keep the lowest full index. The map is a visual correspondence.
    It does not make a reduced mesh a mass or contact geometry.

    Args:
        full: The mesh before decimation.
        reduced: The mesh after decimation, in the same frame.

    Returns:
        One full-mesh index per reduced vertex.

    Raises:
        Error: If either mesh has no positions, or the full mesh has no
            vertices while the reduced one has some.
    """
    ref source = full.attribute_view(String(POSITION))
    ref target = reduced.attribute_view(String(POSITION))
    if source.count() == 0 and target.count() > 0:
        raise Error("A LOD map needs full-mesh vertices")
    var cells = Dict[Int, List[Int]]()
    for v in range(source.count()):  # pragma: no branch
        var key = _key(source.vector3(v))
        if key not in cells:
            cells[key] = List[Int]()
        cells[key].append(v)
    var nearest = List[Int](capacity=target.count())
    for v in range(target.count()):  # pragma: no branch
        var p = target.vector3(v)
        var best = 0
        var closest = Float32(1e30)
        var ring = 0
        while True:
            for dx in range(-ring, ring + 1):  # pragma: no branch
                for dy in range(-ring, ring + 1):  # pragma: no branch
                    for dz in range(-ring, ring + 1):  # pragma: no branch
                        # Only the shell of this ring is new.
                        if max(abs(dx), max(abs(dy), abs(dz))) < ring:
                            continue
                        var key = _key(
                            p
                            + Vector3(
                                Float32(dx) * _CELL,
                                Float32(dy) * _CELL,
                                Float32(dz) * _CELL,
                            )
                        )
                        if key not in cells:
                            continue
                        for s in cells[key]:  # pragma: no branch
                            var d = (source.vector3(s) - p).length()
                            if d < closest:
                                closest = d
                                best = s
            # An unvisited cell is at least this far away. One extra cell
            # absorbs the rounding of the cell key.
            if closest <= Float32(ring - 1) * _CELL:
                break
            ring += 1
        nearest.append(best)
    return nearest^


def lod_shift(
    full: BufferGeometry, reduced: BufferGeometry, map: List[Int]
) raises -> Length:
    """Return the largest distance from a reduced vertex to its map target.

    Args:
        full: The mesh before decimation.
        reduced: The mesh after decimation.
        map: The result of `lod_map(full, reduced)`.

    Returns:
        The largest shift.

    Raises:
        Error: If the map does not hold one full index per reduced vertex.
    """
    ref source = full.attribute_view(String(POSITION))
    ref target = reduced.attribute_view(String(POSITION))
    if len(map) != target.count():
        raise Error("A LOD map needs one entry per reduced vertex")
    var largest = Float32(0)
    for v in range(len(map)):  # pragma: no branch
        if map[v] < 0 or map[v] >= source.count():
            raise Error("A LOD map entry must name a full-mesh vertex")
        largest = max(
            largest, (source.vector3(map[v]) - target.vector3(v)).length()
        )
    return Length(largest, METER)


def joint_region(joint: Joint) raises -> BodyRegion:
    """Return the canonical region an animation joint corresponds to.

    Args:
        joint: A named joint.

    Returns:
        The trunk for the hips, spine and chest; the head and neck for
        the neck and head; and the matching limb region otherwise.

    Raises:
        Error: If the joint is not named.
    """
    if not joint.is_valid():
        raise Error("A joint must be a named joint")
    if joint == NECK or joint == HEAD:
        return HEAD_NECK_REGION
    if joint.value <= CHEST.value:
        return TRUNK_REGION
    var table: List[BodyRegion] = [
        RIGHT_UPPER_ARM_REGION,
        RIGHT_FOREARM_REGION,
        RIGHT_HAND_REGION,
        LEFT_UPPER_ARM_REGION,
        LEFT_FOREARM_REGION,
        LEFT_HAND_REGION,
        RIGHT_THIGH_REGION,
        RIGHT_SHANK_REGION,
        RIGHT_FOOT_REGION,
        RIGHT_FOOT_REGION,
        LEFT_THIGH_REGION,
        LEFT_SHANK_REGION,
        LEFT_FOOT_REGION,
        LEFT_FOOT_REGION,
    ]
    return table[joint.value - RIGHT_UPPER_ARM.value]


def skin_weight_agreement(
    envelope: CanonicalEnvelope, geometry: BufferGeometry
) raises -> Tuple[Int, Int]:
    """Count the vertices whose strongest joint names their region.

    Skin weights are animation weights. This count measures how far they
    agree with the canonical regions. It does not turn them into a tissue
    or mass map.

    Args:
        envelope: The canonical skin and region rule.
        geometry: A skinned mesh at rest, in the pelvis frame.

    Returns:
        The agreeing vertex count and the vertex count.

    Raises:
        Error: If the mesh has no positions, skin indices or skin weights,
            or names an unknown joint.
    """
    ref positions = geometry.attribute_view(String(POSITION))
    ref joints = geometry.attribute_view(String(SKIN_INDEX))
    ref weights = geometry.attribute_view(String(SKIN_WEIGHT))
    var agree = 0
    for v in range(positions.count()):  # pragma: no branch
        var strongest = 0
        for c in range(1, weights.item_size):  # pragma: no branch
            if weights.component(v, c) > weights.component(v, strongest):
                strongest = c
        var joint = Joint(Int(joints.component(v, strongest)))
        if joint_region(joint) == envelope.region(positions.vector3(v)):
            agree += 1
    return (agree, positions.count())


struct JawCoupling(ImplicitlyCopyable):
    """A rigid hinge for the canonical mandible and lower teeth.

    The hinge is fitted to the scanned lower teeth under the `jawOpen`
    shape: a rotation about the body's x axis through `pivot`. A weight
    `w` turns the canonical jaw by `w` times `angle`.
    """

    var pivot: Vector3
    """A point on the hinge axis, in meters."""
    var angle: Angle
    """The rotation at a `jawOpen` weight of one. Positive opens."""
    var residual: Length
    """The root-mean-square misfit of the rigid hinge on the scan."""
    var moving: Int
    """How many scanned teeth vertices the fit used."""

    def __init__(
        out self, pivot: Vector3, angle: Angle, residual: Length, moving: Int
    ):
        """Hold a fitted hinge.

        Args:
            pivot: A point on the hinge axis, in meters.
            angle: The rotation at full weight.
            residual: The fit's root-mean-square misfit.
            moving: The vertex count of the fit.
        """
        self.pivot = pivot
        self.angle = angle
        self.residual = residual
        self.moving = moving

    def canonical_point(self, point: Vector3, weight: Float32) -> Vector3:
        """Move a canonical mandible point by a `jawOpen` weight.

        Args:
            point: A rest point of the mandible or the lower teeth.
            weight: The `jawOpen` weight.

        Returns:
            The moved point, in meters.
        """
        return _turn(point, self.pivot, Float32(self.angle.value) * weight)

    def rest_point(self, point: Vector3, weight: Float32) -> Vector3:
        """Undo `canonical_point` for the same weight.

        Args:
            point: A moved point.
            weight: The `jawOpen` weight that moved it.

        Returns:
            The rest point, in meters.
        """
        return _turn(point, self.pivot, -Float32(self.angle.value) * weight)


def _turn(point: Vector3, pivot: Vector3, angle: Float32) -> Vector3:
    """Rotate a point about the x axis through `pivot`.

    A positive angle turns plus z toward minus y, which lowers the chin.
    """
    var y = point.y - pivot.y
    var z = point.z - pivot.z
    var c = cos(angle)
    var s = sin(angle)
    # The move, not the turned point: a zero angle moves nothing exactly.
    return Vector3(
        point.x,
        point.y + ((c - 1) * y - s * z),
        point.z + (s * y + (c - 1) * z),
    )


def jaw_coupling(spec: HumanoidSpec) raises -> JawCoupling:
    """Fit the canonical jaw hinge to the scanned `jawOpen` shape.

    The fit takes the scanned teeth that the shape moves by more than half
    of its largest move: the lower dentition. See `fit_hinge`.

    Args:
        spec: The canonical input recipe.

    Returns:
        The fitted hinge and its residual.

    Raises:
        Error: If the spec or the face model is refused, or `fit_hinge`
            refuses the moved teeth.
    """
    var teeth = mouth_mesh(
        head_muscle_dimensions(spec), TEETH, [String(JAW_SHAPE)]
    )
    ref rest = teeth.attribute_view(String(POSITION))
    var largest = Float32(0)
    for v in range(rest.count()):  # pragma: no branch
        largest = max(largest, teeth.morph_position(0, v).length())
    var before = List[Vector3]()
    var after = List[Vector3]()
    for v in range(rest.count()):  # pragma: no branch
        var move = teeth.morph_position(0, v)
        if move.length() > _MOVING_SHARE * largest:
            before.append(rest.vector3(v))
            after.append(rest.vector3(v) + move)
    return fit_hinge(before, after)


def fit_hinge(rest: List[Vector3], moved: List[Vector3]) raises -> JawCoupling:
    """Fit a rigid rotation about the x axis to moved points.

    The rotation angle is the closed-form two-dimensional Procrustes
    solution in the y-z plane. The pivot then carries the rest centroid
    to the moved centroid. The residual includes any x motion.

    Args:
        rest: Points before the motion, in meters.
        moved: The same points after it.

    Returns:
        The hinge, its residual and the point count.

    Raises:
        Error: If the lists differ in length or are empty, or the motion
            has no rotation to fit.
    """
    if len(rest) != len(moved):
        raise Error("A hinge fit needs one moved point per rest point")
    if len(rest) == 0:
        raise Error("A hinge fit needs moved points")
    var a = _centroid(rest)
    var b = _centroid(moved)
    var cross = Float64(0)
    var dot = Float64(0)
    for index in range(len(rest)):  # pragma: no branch
        var p = rest[index] - a
        var q = moved[index] - b
        dot += Float64(p.y * q.y + p.z * q.z)
        cross += Float64(p.y * q.z - p.z * q.y)
    var angle = Float32(atan2(cross, dot))
    if abs(angle) < _LEAST_TURN:
        raise Error("A hinge fit needs a rotation, not a translation")
    # The pivot c solves b = c + R (a - c), so (I - R) c = b - R a.
    var c = cos(angle)
    var s = sin(angle)
    var ty = b.y - (c * a.y - s * a.z)
    var tz = b.z - (s * a.y + c * a.z)
    var det = (1 - c) * (1 - c) + s * s
    var pivot = Vector3(
        a.x, ((1 - c) * ty - s * tz) / det, ((1 - c) * tz + s * ty) / det
    )
    var sum = Float64(0)
    for index in range(len(rest)):  # pragma: no branch
        var turned = _turn(rest[index], pivot, angle)
        sum += Float64((turned - moved[index]).length_sq())
    var rms = Float32(sqrt(sum / Float64(len(rest))))
    return JawCoupling(
        pivot, Angle(angle, RADIAN), Length(rms, METER), len(rest)
    )


def require_coupled_shape(name: String) raises:
    """Refuse a canonical coupling for an uncoupled expression shape.

    Args:
        name: An expression shape name.

    Raises:
        Error: If the shape is not `jawOpen`. Other shapes move the
            visual face, teeth, gums and tongue only.
    """
    if name != String(JAW_SHAPE):
        raise Error(
            "Expression shape "
            + name
            + " is visual-only; only jawOpen moves the canonical jaw"
        )


@fieldwise_init
struct JawFit(ImplicitlyCopyable):
    """The skull clearance of the coupled canonical jaw at one weight."""

    var weight: Float32
    """The `jawOpen` weight."""
    var mandible: Float32
    """The least skull distance of a mandible vertex, in meters."""
    var teeth: Float32
    """The least skull distance of a lower `BONES` tooth vertex, in meters."""


def jaw_fit(
    body: CanonicalBody, coupling: JawCoupling, weight: Float32
) raises -> JawFit:
    """Measure the coupled mandible and lower teeth against the skull.

    Args:
        body: A canonical body.
        coupling: The fitted hinge.
        weight: A `jawOpen` weight, zero through one.

    Returns:
        The least skull distance of each moved part.

    Raises:
        Error: If the weight is not finite or lies outside zero to one.
    """
    if not (weight >= 0 and weight <= 1):
        raise Error("A jawOpen weight must lie in 0 to 1")
    ref skeleton = body.skeleton
    var skull = skeleton.find("skull")
    var teeth = skeleton.find("teeth")
    var mandible = skeleton.mesh(skeleton.find("mandible"))
    var lower = skeleton.mesh(teeth)
    ref arches = skeleton.sweeps[teeth]
    var fit = JawFit(weight, 1e30, 1e30)
    ref bone = mandible.attribute_view(String(POSITION))
    for v in range(bone.count()):  # pragma: no branch
        var d, _ = skeleton.probe(
            skull, coupling.canonical_point(bone.vector3(v), weight)
        )
        fit.mandible = min(fit.mandible, d)
    ref crowns = lower.attribute_view(String(POSITION))
    for v in range(crowns.count()):  # pragma: no branch
        var p = crowns.vector3(v)
        # The second sweep is the lower arch.
        if arches.sweeps[1].distance(p, arches.k) < arches.sweeps[0].distance(
            p, arches.k
        ):
            var d, _ = skeleton.probe(
                skull, coupling.canonical_point(p, weight)
            )
            fit.teeth = min(fit.teeth, d)
    return fit


def require_jaw_fit(rest: JawFit, moved: JawFit) raises:
    """Refuse a jaw weight that drives the jaw deeper into the skull.

    The hinge has no temporomandibular translation. At rest the authored
    condyle and lower teeth already overlap the skull; a moved jaw may not
    overlap it more deeply than that.

    Args:
        rest: `jaw_fit` at weight zero.
        moved: `jaw_fit` at the weight to check.

    Raises:
        Error: If the mandible or the lower teeth reach more than
            `CLEARANCE_TOLERANCE` deeper into the skull than at rest.
    """
    var tolerance = Float32(CLEARANCE_TOLERANCE.value)
    if moved.mandible < rest.mandible - tolerance:
        raise Error(
            "The coupled mandible enters the skull "
            + _mm(rest.mandible - moved.mandible)
            + " deeper than at rest"
        )
    if moved.teeth < rest.teeth - tolerance:
        raise Error(
            "The coupled lower teeth enter the skull "
            + _mm(rest.teeth - moved.teeth)
            + " deeper than at rest"
        )


def _centroid(points: List[Vector3]) -> Vector3:
    """Return the mean of a nonempty list of points."""
    var sum = Vector3(0, 0, 0)
    for p in points:  # pragma: no branch
        sum = sum + p
    return sum * (Float32(1) / Float32(len(points)))


struct FitReport(Copyable, Movable):
    """Measured fits of one canonical body, all in meters.

    A cover is the canonical skin depth of a bone mesh vertex. A negative
    cover means the bone crosses the skin.
    """

    var cover: List[Float32]
    """The least bone cover of each region."""
    var worst: List[String]
    """The bone with the least cover in each region."""
    var eye_gap: Float32
    """The least canonical skull distance of an eyeball sample."""
    var library_eye_gap: Float32
    """The same against the library skull, before its orbits are carved."""
    var eye_depth: Float32
    """The largest canonical skin distance of an eyeball sample."""
    var upper_contact: Float32
    """The least skull distance of the upper `BONES` teeth."""
    var lower_contact: Float32
    """The least mandible distance of the lower `BONES` teeth."""
    var mouth_outside: Float32
    """The largest canonical skin distance of a `MOUTH` tooth vertex."""
    var mouth_offset: Vector3
    """The `MOUTH` teeth centroid minus the `BONES` teeth centroid."""

    def __init__(out self):
        """Start an empty report."""
        self.cover = List[Float32]()
        self.worst = List[String]()
        self.eye_gap = 0
        self.library_eye_gap = 0
        self.eye_depth = 0
        self.upper_contact = 0
        self.lower_contact = 0
        self.mouth_outside = 0
        self.mouth_offset = Vector3(0, 0, 0)


def identity_fit(body: CanonicalBody) raises -> FitReport:
    """Measure tissue clearance, eye fit and dental fit of one body.

    Args:
        body: A canonical body for the identity to check.

    Returns:
        The measured fits.

    Raises:
        Error: If a mesh or a field cannot be evaluated.
    """
    var report = FitReport()
    ref skeleton = body.skeleton
    for region in named_body_regions():  # pragma: no branch
        ref geometry = body.parts[part_index(region, BONE_TISSUE)].geometry
        ref positions = geometry.attribute_view(String(POSITION))
        var least = Float32(1e30)
        var at = Vector3(0, 0, 0)
        # Each marching vertex repeats in about six triangles. Points that
        # share a 10 micrometer cell are measured once.
        var seen = Dict[Int, Bool]()
        for v in range(positions.count()):  # pragma: no branch
            var p = positions.vector3(v)
            var key = _weld_key(p)
            if key in seen:
                continue
            seen[key] = True
            var cover = -body.envelope.distance(p)
            if cover < least:
                least = cover
                at = p
        report.cover.append(least)
        report.worst.append(skeleton.names[skeleton.nearest(at)])
    var skull = skeleton.find("skull")
    var mandible = skeleton.find("mandible")
    report.eye_gap = 1e30
    report.library_eye_gap = 1e30
    report.eye_depth = -1e30
    for e in range(2):  # pragma: no branch
        for i in range(EYE_SAMPLES):  # pragma: no branch
            var p = (
                body.envelope.eyes[e] + _sphere(i) * body.envelope.eye_radius
            )
            var d, _ = skeleton.probe(skull, p)
            report.eye_gap = min(report.eye_gap, d)
            report.library_eye_gap = min(
                report.library_eye_gap, skeleton.sweeps[skull].distance(p)
            )
            report.eye_depth = max(report.eye_depth, body.envelope.distance(p))
    var teeth = skeleton.find("teeth")
    var bones = skeleton.mesh(teeth)
    ref placed = bones.attribute_view(String(POSITION))
    ref field = skeleton.sweeps[teeth]
    report.upper_contact = 1e30
    report.lower_contact = 1e30
    var sum = Vector3(0, 0, 0)
    for v in range(placed.count()):  # pragma: no branch
        var p = placed.vector3(v)
        sum = sum + p
        # The first sweep is the upper arch, the second the lower.
        if field.sweeps[0].distance(p, field.k) < field.sweeps[1].distance(
            p, field.k
        ):
            var d, _ = skeleton.probe(skull, p)
            report.upper_contact = min(report.upper_contact, d)
        else:
            var d, _ = skeleton.probe(mandible, p)
            report.lower_contact = min(report.lower_contact, d)
    var bones_center = sum * (Float32(1) / Float32(placed.count()))
    var mouth = dentition_mesh(body, MOUTH_DENTITION)
    ref scanned = mouth.attribute_view(String(POSITION))
    report.mouth_outside = -1e30
    sum = Vector3(0, 0, 0)
    for v in range(scanned.count()):  # pragma: no branch
        var p = scanned.vector3(v)
        sum = sum + p
        report.mouth_outside = max(
            report.mouth_outside, body.envelope.distance(p)
        )
    report.mouth_offset = (
        sum * (Float32(1) / Float32(scanned.count())) - bones_center
    )
    return report^


def _weld_key(p: Vector3) -> Int:
    """Return one integer for the 10 micrometer cell that holds a point.

    Each axis takes 21 bits, which spans 20 meters round the origin.
    """
    var i = Int(round(p.x * _WELD)) + (1 << 20)
    var j = Int(round(p.y * _WELD)) + (1 << 20)
    var k = Int(round(p.z * _WELD)) + (1 << 20)
    return (i << 42) | (j << 21) | k


def _sphere(index: Int) -> Vector3:
    """Return one of `EYE_SAMPLES` near-uniform unit directions."""
    var z = 1 - 2 * (Float32(index) + 0.5) / Float32(EYE_SAMPLES)
    var r = sqrt(1 - z * z)
    # The golden angle spreads the points round the axis.
    var a = Float32(index) * Float32(pi * (3 - sqrt(5.0)))
    return Vector3(r * cos(a), r * sin(a), z)


def _mm(value: Float32) -> String:
    """Return meters as text in millimeters."""
    return String(value * 1000) + " mm"


def require_tissue_clearance(report: FitReport, region: BodyRegion) raises:
    """Refuse a region whose bones cross the canonical skin.

    Args:
        report: Fits from `identity_fit`.
        region: A named region.

    Raises:
        Error: If the region is not named, or a bone vertex lies more than
            `CLEARANCE_TOLERANCE` outside the skin.
    """
    var label = region_label(region)
    if report.cover[region.value] < -Float32(CLEARANCE_TOLERANCE.value):
        raise Error(
            "In "
            + label
            + ", the "
            + report.worst[region.value]
            + " bone lies "
            + _mm(-report.cover[region.value])
            + " outside the canonical skin"
        )


def require_eye_fit(report: FitReport) raises:
    """Refuse an eyeball that meets the canonical skull or leaves the skin.

    Args:
        report: Fits from `identity_fit`.

    Raises:
        Error: If an eyeball sample lies inside the canonical skull, or
            outside the canonical skin, by more than the tolerance.
    """
    var tolerance = Float32(CLEARANCE_TOLERANCE.value)
    if report.eye_gap < -tolerance:
        raise Error(
            "An eyeball enters the canonical skull by " + _mm(-report.eye_gap)
        )
    if report.eye_depth > tolerance:
        raise Error(
            "An eyeball leaves the canonical skin by " + _mm(report.eye_depth)
        )


def require_dental_fit(report: FitReport, dentition: Dentition) raises:
    """Refuse a dentition that does not fit the canonical jaws and skin.

    Args:
        report: Fits from `identity_fit`.
        dentition: A named dentition.

    Raises:
        Error: If the `BONES` teeth do not touch their jaws, or if the
            `MOUTH` teeth leave the canonical skin. The `MOUTH` teeth have
            no tested fit to the canonical jaws at all.
    """
    var tolerance = Float32(CLEARANCE_TOLERANCE.value)
    _ = dentition_label(dentition)
    if dentition == MOUTH_DENTITION:
        if report.mouth_outside > tolerance:
            raise Error(
                "The MOUTH teeth leave the canonical skin by "
                + _mm(report.mouth_outside)
            )
        raise Error(
            "The MOUTH teeth have no tested fit to the canonical jaws; they"
            " lie "
            + _mm(report.mouth_offset.length())
            + " from the BONES teeth"
        )
    if report.upper_contact > tolerance:
        raise Error(
            "The upper BONES teeth stand off the skull by "
            + _mm(report.upper_contact)
        )
    if report.lower_contact > tolerance:
        raise Error(
            "The lower BONES teeth stand off the mandible by "
            + _mm(report.lower_contact)
        )


def require_identity_fit(report: FitReport) raises:
    """Refuse an identity map unless every canonical fit holds.

    Args:
        report: Fits from `identity_fit`.

    Raises:
        Error: Whatever `require_tissue_clearance` raises for any region,
            or `require_eye_fit` or `require_dental_fit` for the `BONES`
            teeth raises.
    """
    for region in named_body_regions():  # pragma: no branch
        require_tissue_clearance(report, region)
    require_eye_fit(report)
    require_dental_fit(report, BONES_DENTITION)


def _point(p: Vector3) -> String:
    """Return a point as a JSON array."""
    return "[" + String(p.x) + "," + String(p.y) + "," + String(p.z) + "]"


def identity_payload(report: FitReport) raises -> UserData:
    """Return the values of an identity map.

    Args:
        report: Fits from `identity_fit`.

    Returns:
        Each region's cover, worst bone and support, and the eye and
        dental fits, in meters.

    Raises:
        Error: If the report does not hold every region.
    """
    if len(report.cover) != REGION_COUNT or len(report.worst) != REGION_COUNT:
        raise Error("An identity fit needs every canonical region")
    var regions = UserData()
    for region in named_body_regions():  # pragma: no branch
        var entry = UserData()
        entry.set_number("cover_m", Float64(report.cover[region.value]))
        entry.set_string("worst_bone", report.worst[region.value])
        entry.set_boolean(
            "supported",
            report.cover[region.value] >= -Float32(CLEARANCE_TOLERANCE.value),
        )
        regions.set_json(region_label(region), entry.to_json())
    var data = UserData()
    data.set_json("regions", regions.to_json())
    data.set_number("eye_gap_m", Float64(report.eye_gap))
    data.set_number("library_eye_gap_m", Float64(report.library_eye_gap))
    data.set_number("eye_depth_m", Float64(report.eye_depth))
    data.set_number("upper_contact_m", Float64(report.upper_contact))
    data.set_number("lower_contact_m", Float64(report.lower_contact))
    data.set_number("mouth_outside_m", Float64(report.mouth_outside))
    data.set_json("mouth_offset_m", _point(report.mouth_offset))
    data.set_number("tolerance_m", Float64(CLEARANCE_TOLERANCE.value))
    return data^


def jaw_payload(coupling: JawCoupling) raises -> UserData:
    """Return the values of an expression-and-jaw map.

    Args:
        coupling: The fitted hinge.

    Returns:
        The coupled shape, the hinge and its residual, in SI units.

    Raises:
        Error: If a value cannot be written.
    """
    var data = UserData()
    data.set_string("coupled_shape", String(JAW_SHAPE))
    data.set_string("other_shapes", "visual-only")
    data.set_string("axis", "+x")
    data.set_json("pivot_m", _point(coupling.pivot))
    data.set_number("angle_rad", Float64(coupling.angle.value))
    data.set_number("residual_m", Float64(coupling.residual.value))
    data.set_number("fitted_vertices", Float64(coupling.moving))
    return data^


def skin_weight_payload(agree: Int, total: Int) raises -> UserData:
    """Return the values of a skin-weight map.

    Args:
        agree: Vertices whose strongest joint names their region.
        total: All vertices.

    Returns:
        The counts and the fixed table's use.

    Raises:
        Error: If the counts are negative or `agree` exceeds `total`.
    """
    if agree < 0 or agree > total:
        raise Error("Skin-weight agreement must count at most every vertex")
    var data = UserData()
    data.set_string("table", "fixed joint-to-region table")
    data.set_string("use", "animation-only; not a tissue or mass map")
    data.set_number("agreeing_vertices", Float64(agree))
    data.set_number("vertices", Float64(total))
    return data^


def lod_payload(map: List[Int], shift: Length) raises -> UserData:
    """Return the values of a LOD map.

    Args:
        map: The result of `lod_map`.
        shift: The result of `lod_shift`.

    Returns:
        The entry count, a digest of the entries and the largest shift.

    Raises:
        Error: If a value cannot be written.
    """
    var hash = _fnv_int(FNV1A_OFFSET, len(map))
    for entry in map:  # pragma: no branch
        hash = _fnv_int(hash, entry)
    var data = UserData()
    data.set_number("entries", Float64(len(map)))
    data.set_string("entries_digest", fingerprint_hex(hash))
    data.set_number("largest_shift_m", Float64(shift.value))
    data.set_string("use", "visual-only; not a mass or contact geometry")
    return data^


def dental_payload(body: CanonicalBody) raises -> UserData:
    """Return the values of the dental map: two separate dentitions.

    Args:
        body: A canonical body.

    Returns:
        The mesh digest of each dentition and no correspondence.

    Raises:
        Error: If a dentition mesh cannot be formed.
    """
    var data = UserData()
    data.set_string(
        "bones_digest", geometry_digest(dentition_mesh(body, BONES_DENTITION))
    )
    data.set_string(
        "mouth_digest", geometry_digest(dentition_mesh(body, MOUTH_DENTITION))
    )
    data.set_string("correspondence", "none; ALL is an overlay")
    return data^


def mapping_record(
    kind: MappingKind,
    canonical: UserData,
    visual_revision: String,
    geometry: BufferGeometry,
    payload: UserData,
) raises -> UserData:
    """Return a versioned map record bound to its inputs.

    Args:
        kind: A named map kind.
        canonical: A record from `canonical_record`.
        visual_revision: The visual producer's topology, rig and mapping
            revision.
        geometry: The visual mesh the map was built for.
        payload: The map's own values.

    Returns:
        The record, with the canonical revision and parts digest, the
        spec fingerprint, the visual topology digest and a payload digest.

    Raises:
        Error: If the kind is not named, the revision is empty, the
            canonical record is incomplete or the mesh has no positions.
    """
    var label = mapping_label(kind)
    if visual_revision == "":
        raise Error("A canonical-to-visual map needs a visual revision")
    var record = UserData()
    record.set_number("schema_version", MAPPING_SCHEMA)
    record.set_string("mapping_revision", String(MAPPING_REVISION))
    record.set_string("kind", label)
    record.set_string("canonical_revision", canonical.string("revision"))
    record.set_string(
        "canonical_parts_digest", canonical.string("parts_digest")
    )
    record.set_string("spec_fingerprint", canonical.string("spec_fingerprint"))
    record.set_string("visual_revision", visual_revision)
    record.set_number("vertices", Float64(geometry.vertex_count()))
    record.set_string("topology_digest", topology_digest(geometry))
    record.set_json("payload", payload.to_json())
    record.set_string("payload_digest", json_fingerprint(payload.to_json()))
    record.set_string(
        "invalidation",
        (
            "a new map, canonical or visual revision, spec, canonical part or"
            " topology refuses the map"
        ),
    )
    return record^


def require_mapping(
    stored: UserData,
    kind: MappingKind,
    canonical: UserData,
    visual_revision: String,
    geometry: BufferGeometry,
) raises:
    """Refuse a map whose kind or inputs changed since it was built.

    Args:
        stored: Data that holds a record under `MAPPING_KEY`.
        kind: The expected map kind.
        canonical: The current record from `canonical_record`.
        visual_revision: The current visual revision.
        geometry: The current visual mesh.

    Raises:
        Error: If the record is absent or incomplete, or its kind, map
            revision, canonical revision, canonical parts, spec, visual
            revision, topology or payload differs.
    """
    if not stored.has(String(MAPPING_KEY)):
        raise Error("No canonical-to-visual map record; rebuild it")
    var document = parse_json(stored.json(String(MAPPING_KEY)))
    var record = user_data_of(document, document.root())
    for key in [  # pragma: no branch
        "kind",
        "mapping_revision",
        "canonical_revision",
        "canonical_parts_digest",
        "spec_fingerprint",
        "visual_revision",
        "topology_digest",
        "payload",
        "payload_digest",
    ]:
        if not record.has(key):
            raise Error("The canonical-to-visual map record is incomplete")
    if record.string("kind") != mapping_label(kind):
        raise Error("The map record holds another kind of map")
    if record.string("mapping_revision") != String(MAPPING_REVISION):
        raise Error("The map revision changed; rebuild the map")
    if record.string("canonical_revision") != canonical.string("revision"):
        raise Error("The canonical parts revision changed; rebuild the map")
    if record.string("spec_fingerprint") != canonical.string(
        "spec_fingerprint"
    ):
        raise Error("The map was built for another spec; rebuild it")
    if record.string("canonical_parts_digest") != canonical.string(
        "parts_digest"
    ):
        raise Error("The canonical parts changed; rebuild the map")
    if record.string("visual_revision") != visual_revision:
        raise Error("The visual revision changed; rebuild the map")
    if record.string("topology_digest") != topology_digest(geometry):
        raise Error("The visual topology changed; rebuild the map")
    if record.string("payload_digest") != json_fingerprint(
        record.json("payload")
    ):
        raise Error("The map payload was edited; rebuild the map")
