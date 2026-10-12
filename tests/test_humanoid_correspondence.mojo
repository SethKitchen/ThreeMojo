# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Canonical-to-visual maps: exact controls, extreme identities, refusals."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from core.user_data import UserData, user_data_of
from extensions.humanoid.canonical import (
    HEAD_NECK_REGION,
    LEFT_FOOT_REGION,
    LEFT_HAND_REGION,
    LEFT_SHANK_REGION,
    LEFT_THIGH_REGION,
    REGION_COUNT,
    RIGHT_FOOT_REGION,
    RIGHT_FOREARM_REGION,
    RIGHT_HAND_REGION,
    RIGHT_SHANK_REGION,
    RIGHT_THIGH_REGION,
    RIGHT_UPPER_ARM_REGION,
    TRUNK_REGION,
    BodyRegion,
    CanonicalEnvelope,
    canonical_body,
    geometry_digest,
    named_body_regions,
)
from extensions.humanoid.correspondence import (
    BONES_DENTITION,
    CLEARANCE_TOLERANCE,
    DENTAL_MAP,
    EXPRESSION_JAW_MAP,
    IDENTITY_MAP,
    LOD_MAP,
    MAPPING_KEY,
    MOUTH_DENTITION,
    SKIN_WEIGHT_MAP,
    Dentition,
    FitReport,
    JawCoupling,
    JawFit,
    MappingKind,
    dental_payload,
    dentition_label,
    dentition_mesh,
    fit_hinge,
    head_dentitions,
    identity_fit,
    identity_payload,
    jaw_coupling,
    jaw_fit,
    jaw_payload,
    joint_region,
    lod_map,
    lod_payload,
    lod_shift,
    mapping_label,
    mapping_record,
    region_map,
    require_coupled_shape,
    require_dental_correspondence,
    require_dental_fit,
    require_eye_fit,
    require_identity_fit,
    require_jaw_fit,
    require_mapping,
    require_tissue_clearance,
    skin_weight_agreement,
    skin_weight_payload,
    topology_digest,
)
from extensions.humanoid.fidelity import MAPPING_REVISION
from extensions.humanoid.genome import (
    FACE_SHAPE_1,
    FACE_SHAPES,
    GENE_COUNT,
    Genome,
)
from extensions.humanoid.rig.game import add_game_humanoid
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    HIPS,
    LEFT_FOOT,
    LEFT_HAND,
    LEFT_SHIN,
    LEFT_THIGH,
    LEFT_TOES,
    NECK,
    RIGHT_FOREARM,
    RIGHT_TOES,
    RIGHT_UPPER_ARM,
    SPINE,
    Joint,
    named_joints,
)
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.skeleton.head.contents import (
    ALL,
    BONES,
    MOUTH,
    SKIN,
    HeadContents,
)
from extensions.humanoid.skeleton.simplify import simplify
from extensions.humanoid.skeleton.torso.body import body_skin_mesh
from extensions.humanoid.spec import HumanoidSpec
from loaders.json import parse_json
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from std.math import cos, nan, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import RADIAN, Angle, Length, METER


def _spec() -> HumanoidSpec:
    return HumanoidSpec(Length(1.8288, METER), MALE)


def _genome(value: Float32, face_only: Bool) -> Genome:
    var genome = Genome()
    for index in range(GENE_COUNT):
        var face = index >= FACE_SHAPE_1.value and index < (
            FACE_SHAPE_1.value + FACE_SHAPES
        )
        if face or not face_only:
            genome.expressions[index] = value
    return genome


def _geometry(points: List[Float32], index: List[Int]) raises -> BufferGeometry:
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(points.copy(), 3))
    geometry.set_index(index.copy())
    return geometry^


def _canonical() -> UserData:
    """A canonical record with the three fields a map binds."""
    var record = UserData()
    record.set_string("revision", "threemojo-canonical-parts-v1")
    record.set_string("parts_digest", "0123456789abcdef")
    record.set_string("spec_fingerprint", "fedcba9876543210")
    return record^


def _stored(record: UserData) raises -> UserData:
    var stored = UserData()
    stored.set_json(String(MAPPING_KEY), record.to_json())
    return stored^


def _report() -> FitReport:
    """A report that passes every check with room to spare."""
    var report = FitReport()
    for region in named_body_regions():
        report.cover.append(0.002)
        report.worst.append("bone " + String(region.value))
    report.eye_gap = 0.001
    report.library_eye_gap = -0.006
    report.eye_depth = -0.0001
    report.upper_contact = -0.01
    report.lower_contact = -0.006
    report.mouth_outside = 0.0
    report.mouth_offset = Vector3(0, 0.005, 0.02)
    return report^


def _require_refused(report: FitReport, contains: String) raises:
    with assert_raises(contains=contains):
        require_identity_fit(report)


def test_kinds_and_dentitions_are_named_types() raises:
    assert_true(IDENTITY_MAP.is_valid())
    assert_true(DENTAL_MAP.is_valid())
    assert_false(MappingKind(-1).is_valid())
    assert_false(MappingKind(5).is_valid())
    assert_equal(mapping_label(EXPRESSION_JAW_MAP), "expression-jaw")
    assert_equal(mapping_label(LOD_MAP), "lod")
    with assert_raises(contains="map kind must be named"):
        _ = mapping_label(MappingKind(9))
    assert_true(BONES_DENTITION.is_valid())
    assert_true(MOUTH_DENTITION.is_valid())
    assert_false(Dentition(2).is_valid())
    assert_equal(dentition_label(BONES_DENTITION), "bones")
    assert_equal(dentition_label(MOUTH_DENTITION), "mouth")
    with assert_raises(contains="BONES or MOUTH"):
        _ = dentition_label(Dentition(-1))
    # ALL draws two separate dentitions: an overlay, not a third one.
    var both = head_dentitions(ALL)
    assert_equal(len(both), 2)
    assert_true(both[0] == BONES_DENTITION)
    assert_true(both[1] == MOUTH_DENTITION)
    assert_equal(len(head_dentitions(BONES)), 1)
    assert_true(head_dentitions(MOUTH)[0] == MOUTH_DENTITION)
    assert_equal(len(head_dentitions(SKIN)), 0)
    with assert_raises(contains="layer"):
        _ = head_dentitions(HeadContents(0))
    require_dental_correspondence(BONES_DENTITION, BONES_DENTITION)
    require_dental_correspondence(MOUTH_DENTITION, MOUTH_DENTITION)
    with assert_raises(contains="No tested correspondence"):
        require_dental_correspondence(BONES_DENTITION, MOUTH_DENTITION)
    with assert_raises(contains="No tested correspondence"):
        require_dental_correspondence(MOUTH_DENTITION, BONES_DENTITION)
    with assert_raises(contains="BONES or MOUTH"):
        require_dental_correspondence(Dentition(5), BONES_DENTITION)


def test_fit_requirements_follow_exact_thresholds() raises:
    var tolerance = Float32(CLEARANCE_TOLERANCE.value)
    require_identity_fit(_report())
    # A bone exactly at the tolerance passes; just past it is refused.
    var edge = _report()
    edge.cover[TRUNK_REGION.value] = -tolerance
    require_identity_fit(edge)
    var crossed = _report()
    crossed.cover[TRUNK_REGION.value] = -tolerance * 1.01
    _require_refused(crossed, "In trunk, the bone 1 bone lies")
    with assert_raises(contains="body region must be named"):
        require_tissue_clearance(_report(), BodyRegion(-2))
    var eye = _report()
    eye.eye_gap = -tolerance * 1.01
    _require_refused(eye, "eyeball enters the canonical skull")
    eye = _report()
    eye.eye_depth = tolerance * 1.01
    _require_refused(eye, "eyeball leaves the canonical skin")
    eye.eye_depth = tolerance
    require_eye_fit(eye)
    var teeth = _report()
    teeth.upper_contact = tolerance * 1.01
    _require_refused(teeth, "upper BONES teeth stand off the skull")
    teeth = _report()
    teeth.lower_contact = tolerance * 1.01
    _require_refused(teeth, "lower BONES teeth stand off the mandible")
    # The scanned teeth have no tested fit to the canonical jaws.
    var mouth = _report()
    with assert_raises(contains="no tested fit"):
        require_dental_fit(mouth, MOUTH_DENTITION)
    mouth.mouth_outside = tolerance * 1.01
    with assert_raises(contains="MOUTH teeth leave the canonical skin"):
        require_dental_fit(mouth, MOUTH_DENTITION)
    with assert_raises(contains="BONES or MOUTH"):
        require_dental_fit(mouth, Dentition(3))
    # The payload holds every region and refuses a partial report.
    var data = identity_payload(_report())
    var regions_document = parse_json(data.json("regions"))
    var regions = user_data_of(regions_document, regions_document.root())
    var trunk_document = parse_json(regions.json("trunk"))
    var trunk = user_data_of(trunk_document, trunk_document.root())
    assert_true(trunk.boolean("supported"))
    var outside = identity_payload(crossed)
    var outside_document = parse_json(outside.json("regions"))
    var outside_regions = user_data_of(
        outside_document, outside_document.root()
    )
    var outside_trunk_document = parse_json(outside_regions.json("trunk"))
    assert_false(
        user_data_of(
            outside_trunk_document, outside_trunk_document.root()
        ).boolean("supported")
    )
    with assert_raises(contains="every canonical region"):
        _ = identity_payload(FitReport())
    var half = _report()
    half.worst = List[String]()
    with assert_raises(contains="every canonical region"):
        _ = identity_payload(half)


def test_hinge_fit_recovers_an_exact_rotation() raises:
    var pivot = Vector3(0.01, 0.68, 0.008)
    var angle = Float32(0.4)
    var coupling = JawCoupling(pivot, Angle(angle, RADIAN), Length(0, METER), 0)
    var rest = List[Vector3]()
    var moved = List[Vector3]()
    for k in range(12):
        var p = Vector3(
            0.02 * Float32(k % 3) - 0.02,
            0.64 + 0.003 * Float32(k),
            0.05 + 0.004 * Float32(k % 5),
        )
        rest.append(p)
        moved.append(coupling.canonical_point(p, 1))
    var fit = fit_hinge(rest, moved)
    assert_almost_equal(fit.angle.value, angle, atol=1e-5)
    assert_almost_equal(fit.pivot.y, pivot.y, atol=1e-5)
    assert_almost_equal(fit.pivot.z, pivot.z, atol=1e-5)
    assert_true(fit.residual.value < 1e-5)
    assert_equal(fit.moving, 12)
    # Round trips, and zero weight is the identity.
    for p in rest:
        var there = fit.canonical_point(p, 0.37)
        var back = fit.rest_point(there, 0.37)
        assert_true((back - p).length() < 1e-6)
        var still = fit.canonical_point(p, 0)
        assert_equal(still.x, p.x)
        assert_equal(still.y, p.y)
        assert_equal(still.z, p.z)
    with assert_raises(contains="one moved point per rest point"):
        _ = fit_hinge(rest, List[Vector3]())
    with assert_raises(contains="needs moved points"):
        _ = fit_hinge(List[Vector3](), List[Vector3]())
    var slid = List[Vector3]()
    for p in rest:
        slid.append(p + Vector3(0, -0.01, 0.002))
    with assert_raises(contains="not a translation"):
        _ = fit_hinge(rest, slid)


def test_the_scanned_jaw_opens_about_a_rigid_hinge() raises:
    var jaw = jaw_coupling(_spec())
    # The scan's lower teeth turn rigidly to within a fraction of a
    # millimeter, about an axis below and in front of the ear.
    assert_true(jaw.residual.value < 0.0005)
    assert_true(jaw.moving > 1000)
    assert_true(jaw.angle.value > 0.3)
    assert_true(jaw.angle.value < 0.6)
    var data = jaw_payload(jaw)
    assert_equal(data.string("coupled_shape"), "jawOpen")
    assert_equal(data.string("other_shapes"), "visual-only")
    require_coupled_shape("jawOpen")
    with assert_raises(contains="is visual-only"):
        require_coupled_shape("mouthSmile_L")


def test_the_coupled_jaw_is_refused_past_its_supported_opening() raises:
    var body = canonical_body(_spec())
    var jaw = jaw_coupling(_spec())
    var rest = jaw_fit(body, jaw, 0)
    require_jaw_fit(rest, rest)
    # The lower teeth leave the upper jaw as the mouth opens.
    var half = jaw_fit(body, jaw, 0.5)
    require_jaw_fit(rest, half)
    assert_true(half.teeth > rest.teeth)
    # The hinge has no joint translation: at full opening the condyle
    # region reaches deeper into the skull than at rest.
    var full = jaw_fit(body, jaw, 1)
    with assert_raises(contains="mandible enters the skull"):
        require_jaw_fit(rest, full)
    var teeth = JawFit(1, rest.mandible, rest.teeth - 0.001)
    with assert_raises(contains="lower teeth enter the skull"):
        require_jaw_fit(rest, teeth)
    with assert_raises(contains="must lie in 0 to 1"):
        _ = jaw_fit(body, jaw, 1.5)
    with assert_raises(contains="must lie in 0 to 1"):
        _ = jaw_fit(body, jaw, -0.5)
    with assert_raises(contains="must lie in 0 to 1"):
        _ = jaw_fit(body, jaw, nan[DType.float32]())


def test_template_identity_fits_and_keeps_both_dentitions() raises:
    var body = canonical_body(_spec())
    var fit = identity_fit(body)
    require_identity_fit(fit)
    # The carved orbit keeps the clearance; the library skull does not.
    assert_almost_equal(fit.eye_gap, 0.001, atol=1e-5)
    assert_true(fit.library_eye_gap < -0.004)
    assert_true(fit.eye_depth <= 1e-5)
    assert_true(fit.upper_contact < 0)
    assert_true(fit.lower_contact < 0)
    # The scanned teeth stand about 22 mm in front of the authored teeth.
    assert_true(fit.mouth_offset.z > 0.015)
    with assert_raises(contains="MOUTH teeth leave the canonical skin"):
        require_dental_fit(fit, MOUTH_DENTITION)
    var bones = dentition_mesh(body, BONES_DENTITION)
    var mouth = dentition_mesh(body, MOUTH_DENTITION)
    var dental = dental_payload(body)
    assert_equal(dental.string("bones_digest"), geometry_digest(bones))
    assert_equal(dental.string("mouth_digest"), geometry_digest(mouth))
    assert_true(dental.string("bones_digest") != dental.string("mouth_digest"))
    assert_equal(dental.string("correspondence"), "none; ALL is an overlay")
    with assert_raises(contains="BONES or MOUTH"):
        _ = dentition_mesh(body, Dentition(7))


def test_face_shape_extremes_set_the_supported_identity_domain() raises:
    # Each face-shape mode at -1 keeps the skull inside the scanned skin.
    var body = canonical_body(
        HumanoidSpec(Length(1.8288, METER), MALE, genome=_genome(-1, True))
    )
    var fit = identity_fit(body)
    require_identity_fit(fit)
    require_eye_fit(fit)


def test_face_shapes_at_plus_one_are_refused() raises:
    # At +1 the scanned face recedes behind the authored teeth: the face
    # modes do not move the skull, so the identity map fails closed.
    var body = canonical_body(
        HumanoidSpec(Length(1.8288, METER), MALE, genome=_genome(1, True))
    )
    var fit = identity_fit(body)
    require_eye_fit(fit)
    _require_refused(fit, "In head-neck, the teeth bone lies")
    require_tissue_clearance(fit, TRUNK_REGION)
    require_tissue_clearance(fit, RIGHT_FOOT_REGION)


def test_every_gene_at_plus_one_is_refused() raises:
    var body = canonical_body(
        HumanoidSpec(Length(1.8288, METER), MALE, genome=_genome(1, False))
    )
    var fit = identity_fit(body)
    require_eye_fit(fit)
    _require_refused(fit, "In head-neck, the teeth bone lies")
    for region in named_body_regions():
        if region != HEAD_NECK_REGION:
            require_tissue_clearance(fit, region)


def test_every_gene_at_minus_one_is_refused() raises:
    var body = canonical_body(
        HumanoidSpec(Length(1.8288, METER), MALE, genome=_genome(-1, False))
    )
    var fit = identity_fit(body)
    require_eye_fit(fit)
    require_dental_fit(fit, BONES_DENTITION)
    _require_refused(fit, "In head-neck, the skull bone lies")


def test_stature_and_sex_extremes() raises:
    # The shortest female template keeps every fit.
    var short = identity_fit(
        canonical_body(HumanoidSpec(Length(1.2, METER), FEMALE))
    )
    require_identity_fit(short)


def test_the_tallest_template_is_refused() raises:
    var fit = identity_fit(
        canonical_body(HumanoidSpec(Length(2.5, METER), MALE))
    )
    require_eye_fit(fit)
    require_dental_fit(fit, BONES_DENTITION)
    _require_refused(fit, "In head-neck, the skull bone lies")


def test_map_records_bind_kind_revisions_spec_and_topology() raises:
    var canonical = _canonical()
    var mesh = _geometry(
        [0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0], [0, 1, 2, 2, 1, 3]
    )
    var payload = skin_weight_payload(3, 4)
    var record = mapping_record(
        SKIN_WEIGHT_MAP, canonical, "visual-v1", mesh, payload
    )
    assert_equal(record.string("mapping_revision"), MAPPING_REVISION)
    assert_equal(record.string("kind"), "skin-weight")
    assert_equal(record.string("topology_digest"), topology_digest(mesh))
    require_mapping(
        _stored(record), SKIN_WEIGHT_MAP, canonical, "visual-v1", mesh
    )
    with assert_raises(contains="needs a visual revision"):
        _ = mapping_record(LOD_MAP, canonical, "", mesh, payload)
    with assert_raises(contains="map kind must be named"):
        _ = mapping_record(MappingKind(8), canonical, "v", mesh, payload)
    with assert_raises(contains="No canonical-to-visual map record"):
        require_mapping(
            UserData(), SKIN_WEIGHT_MAP, canonical, "visual-v1", mesh
        )
    var partial = record.copy()
    _ = partial.remove("payload_digest")
    with assert_raises(contains="record is incomplete"):
        require_mapping(
            _stored(partial), SKIN_WEIGHT_MAP, canonical, "visual-v1", mesh
        )
    with assert_raises(contains="another kind of map"):
        require_mapping(_stored(record), LOD_MAP, canonical, "visual-v1", mesh)
    var old = record.copy()
    old.set_string("mapping_revision", "threemojo-canonical-visual-maps-v0")
    with assert_raises(contains="map revision changed"):
        require_mapping(
            _stored(old), SKIN_WEIGHT_MAP, canonical, "visual-v1", mesh
        )
    var other = canonical.copy()
    other.set_string("revision", "threemojo-canonical-parts-v2")
    with assert_raises(contains="canonical parts revision changed"):
        require_mapping(
            _stored(record), SKIN_WEIGHT_MAP, other, "visual-v1", mesh
        )
    other = canonical.copy()
    other.set_string("spec_fingerprint", "0000000000000000")
    with assert_raises(contains="another spec"):
        require_mapping(
            _stored(record), SKIN_WEIGHT_MAP, other, "visual-v1", mesh
        )
    other = canonical.copy()
    other.set_string("parts_digest", "ffffffffffffffff")
    with assert_raises(contains="canonical parts changed"):
        require_mapping(
            _stored(record), SKIN_WEIGHT_MAP, other, "visual-v1", mesh
        )
    with assert_raises(contains="visual revision changed"):
        require_mapping(
            _stored(record), SKIN_WEIGHT_MAP, canonical, "visual-v2", mesh
        )
    # A pose does not change topology; a new triangle order does.
    var posed = _geometry(
        [0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1], [0, 1, 2, 2, 1, 3]
    )
    require_mapping(
        _stored(record), SKIN_WEIGHT_MAP, canonical, "visual-v1", posed
    )
    var reordered = _geometry(
        [0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0], [1, 3, 2, 0, 1, 2]
    )
    with assert_raises(contains="visual topology changed"):
        require_mapping(
            _stored(record), SKIN_WEIGHT_MAP, canonical, "visual-v1", reordered
        )
    var edited = record.copy()
    edited.set_json("payload", skin_weight_payload(4, 4).to_json())
    with assert_raises(contains="payload was edited"):
        require_mapping(
            _stored(edited), SKIN_WEIGHT_MAP, canonical, "visual-v1", mesh
        )
    with assert_raises(contains="at most every vertex"):
        _ = skin_weight_payload(5, 4)
    with assert_raises(contains="at most every vertex"):
        _ = skin_weight_payload(-1, 4)


def test_lod_map_exact_controls() raises:
    var full = _geometry(
        [0, 0, 0, 0.1, 0, 0, 0, 0.1, 0, 0.1, 0.1, 0, 0.05, 0.05, 0.03],
        [0, 1, 2, 2, 1, 3, 0, 1, 4],
    )
    var same = lod_map(full, full)
    for index in range(len(same)):
        assert_equal(same[index], index)
    assert_equal(lod_shift(full, full, same).value, 0)
    # A reduced vertex maps to the nearest full vertex, the lowest on a tie.
    var reduced = _geometry(
        [0.002, 0.001, 0, 0.05, 0.05, 0.0, 0.3, 0.3, 0.3], [0, 1, 2]
    )
    var map = lod_map(full, reduced)
    assert_equal(map[0], 0)
    assert_equal(map[1], 4)
    assert_equal(map[2], 3)
    assert_almost_equal(
        lod_shift(full, reduced, map).value,
        (Vector3(0.3, 0.3, 0.3) - Vector3(0.1, 0.1, 0)).length(),
        atol=1e-6,
    )
    var tie = _geometry([0.05, 0, 0], [0, 0, 0])
    assert_equal(lod_map(full, tie)[0], 0)
    var empty = BufferGeometry()
    empty.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    assert_equal(len(lod_map(empty, empty)), 0)
    with assert_raises(contains="needs full-mesh vertices"):
        _ = lod_map(empty, reduced)
    with assert_raises(contains="one entry per reduced vertex"):
        _ = lod_shift(full, reduced, [0])
    with assert_raises(contains="must name a full-mesh vertex"):
        _ = lod_shift(full, reduced, [0, 1, 5])
    with assert_raises(contains="must name a full-mesh vertex"):
        _ = lod_shift(full, reduced, [0, -1, 2])
    var data = lod_payload(map, lod_shift(full, reduced, map))
    assert_equal(data.number("entries"), 3)
    assert_true(data.string("use").startswith("visual-only"))


def test_decimation_keeps_regions_and_a_bounded_map() raises:
    var envelope = CanonicalEnvelope(_spec())
    var full = body_skin_mesh(_spec(), 12)
    var reduced = simplify(full, full.triangle_count() // 4)
    var map = lod_map(full, reduced)
    # A decimated vertex stays within a few centimeters of the full mesh.
    assert_true(lod_shift(full, reduced, map).value < 0.05)
    var before = region_map(envelope, full)
    var after = region_map(envelope, reduced)
    var agree = 0
    for v in range(len(map)):
        if after.regions[v] == before.regions[map[v]]:
            agree += 1
    assert_true(Float32(agree) > 0.95 * Float32(len(map)))
    with assert_raises(contains="body region must be named"):
        _ = after.count(BodyRegion(-1))


def test_skin_weight_table_and_agreement() raises:
    assert_true(joint_region(HIPS) == TRUNK_REGION)
    assert_true(joint_region(SPINE) == TRUNK_REGION)
    assert_true(joint_region(CHEST) == TRUNK_REGION)
    assert_true(joint_region(NECK) == HEAD_NECK_REGION)
    assert_true(joint_region(HEAD) == HEAD_NECK_REGION)
    assert_true(joint_region(RIGHT_UPPER_ARM) == RIGHT_UPPER_ARM_REGION)
    assert_true(joint_region(RIGHT_FOREARM) == RIGHT_FOREARM_REGION)
    assert_true(joint_region(LEFT_HAND) == LEFT_HAND_REGION)
    assert_true(joint_region(LEFT_THIGH) == LEFT_THIGH_REGION)
    assert_true(joint_region(LEFT_SHIN) == LEFT_SHANK_REGION)
    assert_true(joint_region(LEFT_FOOT) == LEFT_FOOT_REGION)
    assert_true(joint_region(LEFT_TOES) == LEFT_FOOT_REGION)
    assert_true(joint_region(RIGHT_TOES) == RIGHT_FOOT_REGION)
    # Every region has at least one joint.
    var covered = List[Bool](length=REGION_COUNT, fill=False)
    for joint in named_joints():
        covered[joint_region(joint).value] = True
    for index in range(REGION_COUNT):
        assert_true(covered[index])
    with assert_raises(contains="named joint"):
        _ = joint_region(Joint(19))
    # Exact control: two vertices weighted to their own regions, one not.
    var envelope = CanonicalEnvelope(_spec())
    var top = Vector3(0, envelope.neck_base + 0.15, 0)
    var thigh = Vector3(0.09, envelope.hip - 0.1, 0)
    var mesh = _geometry(
        [top.x, top.y, top.z, thigh.x, thigh.y, thigh.z, 0, 0.25, 0],
        [0, 1, 2],
    )
    var joints: List[Float32] = [4, 0, 0, 0, 0, 11, 0, 0, 13, 0, 0, 0]
    var weights: List[Float32] = [1, 0, 0, 0, 0.2, 0.8, 0, 0, 0.6, 0.4, 0, 0]
    mesh.set_attribute(String(SKIN_INDEX), BufferAttribute(joints^, 4))
    mesh.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))
    var counts = skin_weight_agreement(envelope, mesh)
    assert_equal(counts[0], 2)
    assert_equal(counts[1], 3)
    var map = region_map(envelope, mesh)
    assert_true(map.regions[0] == HEAD_NECK_REGION)
    assert_true(map.regions[1] == RIGHT_THIGH_REGION)
    assert_true(map.regions[2] == TRUNK_REGION)
    assert_equal(map.count(TRUNK_REGION), 1)
    assert_true(map.gap().value > 0)


def test_game_humanoid_skin_weights_agree_with_regions() raises:
    var envelope = CanonicalEnvelope(_spec())
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    var person = add_game_humanoid(
        scene, assets, parent, _spec(), 3000, 12, 8, 8, workers=1
    )
    for index in range(len(person.skins)):
        ref skin = assets.geometries.get(
            scene.skinned_meshes[person.skins[index]].geometry
        )
        var counts = skin_weight_agreement(envelope, skin)
        assert_true(Float32(counts[0]) > 0.85 * Float32(counts[1]))
        var map = region_map(envelope, skin)
        var total = 0
        for region in named_body_regions():
            total += map.count(region)
        assert_equal(total, skin.vertex_count())
    ref body = assets.geometries.get(
        scene.skinned_meshes[person.skins[0]].geometry
    )
    var map = region_map(envelope, body)
    for region in named_body_regions():
        if region != RIGHT_HAND_REGION and region != LEFT_HAND_REGION:
            assert_true(map.count(region) > 0)
    ref hand = assets.geometries.get(
        scene.skinned_meshes[person.skins[1]].geometry
    )
    var hand_map = region_map(envelope, hand)
    assert_true(
        Float32(hand_map.count(RIGHT_HAND_REGION))
        > 0.75 * Float32(hand.vertex_count())
    )
    assert_true(hand_map.count(RIGHT_FOREARM_REGION) > 0)
    assert_equal(hand_map.count(LEFT_HAND_REGION), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
