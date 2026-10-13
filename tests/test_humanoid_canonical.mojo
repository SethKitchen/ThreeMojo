# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Canonical parts: complete coverage, tissue labels, records and bakes."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from core.user_data import UserData, user_data_of
from extensions.anatomy.soft_tissue import muscle_tissue
from extensions.humanoid.bake import require_sealed_bake, write_sealed_bake
from extensions.humanoid.canonical import (
    BONE_TISSUE,
    CANONICAL_PARTS_KEY,
    CANONICAL_STEP,
    HEAD_NECK_REGION,
    LEFT_FOOT_REGION,
    LEFT_FOREARM_REGION,
    LEFT_HAND_REGION,
    LEFT_SHANK_REGION,
    LEFT_THIGH_REGION,
    LEFT_UPPER_ARM_REGION,
    MAX_CANONICAL_STEP,
    MIN_CANONICAL_STEP,
    ORBIT_CLEARANCE,
    PART_COUNT,
    REGION_COUNT,
    RIGHT_FOOT_REGION,
    RIGHT_FOREARM_REGION,
    RIGHT_HAND_REGION,
    RIGHT_SHANK_REGION,
    RIGHT_THIGH_REGION,
    RIGHT_UPPER_ARM_REGION,
    SOFT_TISSUE,
    TRUNK_REGION,
    BodyRegion,
    CanonicalEnvelope,
    CanonicalSkeleton,
    CanonicalTissue,
    OrbitedSkull,
    canonical_body,
    canonical_record,
    check_canonical_step,
    geometry_digest,
    named_body_regions,
    part_index,
    part_label,
    region_label,
    require_canonical_record,
    require_part_geometry,
    tissue_label,
)
from extensions.humanoid.fidelity import (
    CANONICAL_PARTS_REVISION,
    CANONICAL_RECIPE,
    FIDELITY_KEY,
    GAME_RECIPE,
    canonical_inputs,
    humanoid_provenance,
    spec_fingerprint,
    stored_spec,
)
from extensions.humanoid.genome import (
    EYE_DEPTH,
    EYE_SIZE,
    EYE_SPACING,
    Expression,
    Genome,
)
from extensions.humanoid.rig.game import add_game_humanoid, game_build_settings
from extensions.humanoid.sex import MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.skeleton.torso.body import BodySkinField
from extensions.humanoid.spec import HumanoidSpec
from loaders.gltf import read_gltf
from loaders.json import parse_json
from materials.material import BASIC, Material
from render.framebuffer import Color
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_scratch import TestScratch, temporary_path
from units.si import Length, METER, MILLIMETER


def _spec() -> HumanoidSpec:
    return HumanoidSpec(Length(1.8288, METER), MALE)


def _volume(geometry: BufferGeometry) raises -> Float64:
    """Return the signed volume a closed triangle mesh encloses."""
    ref p = geometry.attribute_view(String(POSITION))
    var sum = Float64(0)
    for t in range(0, len(geometry.index), 3):
        var a = p.vector3(geometry.index[t])
        var b = p.vector3(geometry.index[t + 1])
        var c = p.vector3(geometry.index[t + 2])
        sum += Float64(
            a.x * (b.y * c.z - b.z * c.y)
            - a.y * (b.x * c.z - b.z * c.x)
            + a.z * (b.x * c.y - b.y * c.x)
        )
    return sum / 6


def _stored(record: UserData) raises -> UserData:
    var stored = UserData()
    stored.set_json(String(CANONICAL_PARTS_KEY), record.to_json())
    return stored^


def _edited(record: UserData, key: String, json: String) raises -> UserData:
    var copy = record.copy()
    copy.set_json(key, json)
    return _stored(copy)


def test_regions_and_tissues_are_named_types() raises:
    var regions = named_body_regions()
    assert_equal(len(regions), REGION_COUNT)
    assert_equal(PART_COUNT, 28)
    assert_true(BodyRegion(0).is_valid())
    assert_false(BodyRegion(-1).is_valid())
    assert_false(BodyRegion(REGION_COUNT).is_valid())
    assert_equal(region_label(HEAD_NECK_REGION), "head-neck")
    assert_equal(region_label(LEFT_FOOT_REGION), "left-foot")
    assert_true(SOFT_TISSUE.is_valid())
    assert_true(BONE_TISSUE.is_valid())
    assert_false(CanonicalTissue(2).is_valid())
    assert_equal(tissue_label(SOFT_TISSUE), "soft")
    assert_equal(tissue_label(BONE_TISSUE), "bone")
    assert_equal(
        part_label(RIGHT_THIGH_REGION, BONE_TISSUE), "right-thigh.bone"
    )
    assert_equal(part_index(TRUNK_REGION, SOFT_TISSUE), 2)
    assert_equal(part_index(LEFT_FOOT_REGION, BONE_TISSUE), 27)
    with assert_raises(contains="body region must be named"):
        _ = region_label(BodyRegion(14))
    with assert_raises(contains="tissue must be named"):
        _ = tissue_label(CanonicalTissue(-1))
    with assert_raises(contains="body region must be named"):
        _ = part_index(BodyRegion(-1), SOFT_TISSUE)
    with assert_raises(contains="tissue must be named"):
        _ = part_index(TRUNK_REGION, CanonicalTissue(3))


def test_step_and_spec_are_refused_before_generation() raises:
    check_canonical_step(CANONICAL_STEP)
    check_canonical_step(MIN_CANONICAL_STEP)
    check_canonical_step(MAX_CANONICAL_STEP)
    with assert_raises(contains="must be finite"):
        check_canonical_step(Length(nan[DType.float32](), METER))
    with assert_raises(contains="at least 5 mm"):
        check_canonical_step(Length(4.9, MILLIMETER))
    with assert_raises(contains="at most 10 mm"):
        check_canonical_step(Length(10.1, MILLIMETER))
    with assert_raises(contains="named sex"):
        _ = canonical_body(HumanoidSpec(Length(1.8288, METER), Sex(7)))
    with assert_raises(contains="at least 5 mm"):
        _ = canonical_body(_spec(), Length(1.0, MILLIMETER))


def test_skeleton_holds_every_named_bone_family() raises:
    var skeleton = CanonicalSkeleton(_spec())
    assert_equal(skeleton.count(), 181)
    var skull = skeleton.find("skull")
    with assert_raises(contains="No canonical bone is named"):
        _ = skeleton.find("wishbone")
    with assert_raises(contains="must name a bone"):
        _ = skeleton.probe(-1, Vector3(0, 0, 0))
    with assert_raises(contains="must name a bone"):
        _ = skeleton.probe(skeleton.count(), Vector3(0, 0, 0))
    with assert_raises(contains="must name a bone"):
        _ = skeleton.mesh(-1)
    with assert_raises(contains="must name a bone"):
        _ = skeleton.mesh(skeleton.count())
    # One bone of each family holds its own mesh centroid region, and the
    # region of each named bone is anatomical, not geometric.
    var names: List[String] = [
        "teeth",
        "rib 3 left",
        "humerus right",
        "radius left",
        "lunate right",
        "sacrum",
        "femur right",
        "patella left",
        "tibia right",
        "fibula left",
        "talus right",
        "calcaneus left",
    ]
    var regions: List[BodyRegion] = [
        HEAD_NECK_REGION,
        TRUNK_REGION,
        RIGHT_UPPER_ARM_REGION,
        LEFT_FOREARM_REGION,
        RIGHT_HAND_REGION,
        TRUNK_REGION,
        RIGHT_THIGH_REGION,
        LEFT_THIGH_REGION,
        RIGHT_SHANK_REGION,
        LEFT_SHANK_REGION,
        RIGHT_FOOT_REGION,
        LEFT_FOOT_REGION,
    ]
    for at in range(len(names)):
        var index = skeleton.find(names[at])
        assert_true(skeleton.regions[index] == regions[at])
        var mesh = skeleton.mesh(index)
        ref p = mesh.attribute_view(String(POSITION))
        var surface = p.vector3(0)
        var d, _ = skeleton.probe(index, surface)
        # A marching vertex lies on the surface to within a cell.
        assert_true(abs(d) < 0.005)
        var near, _ = skeleton.probe(skeleton.nearest(surface), surface)
        assert_true(abs(near) <= abs(d))
    # A point above every bone, or below, has no candidates.
    var above = skeleton.locate(Vector3(0, 5, 0))
    assert_equal(above.index, -1)
    assert_equal(above.nearest, 1.0e3)
    assert_equal(skeleton.locate(Vector3(0, -5, 0)).index, -1)
    with assert_raises(contains="No canonical bone box"):
        _ = skeleton.nearest(Vector3(0, 5, 0))
    # The skull is carved round each eye with the orbit clearance.
    var eye = skeleton.eyes[0]
    var d, _ = skeleton.probe(skull, eye)
    assert_true(d > 0)
    var r = skeleton.orbit - Float32(ORBIT_CLEARANCE.value)
    var back = eye - Vector3(0, 0, r)
    var carved, _ = skeleton.probe(skull, back)
    assert_true(carved >= Float32(ORBIT_CLEARANCE.value) - 1e-5)
    # The library skull still holds the back of the eye: its orbit is
    # shallow. The canonical skull does not.
    assert_true(skeleton.sweeps[skull].distance(back) < 0)
    var orbited = OrbitedSkull(
        skeleton.sweeps[skull].copy(), skeleton.eyes.copy(), skeleton.orbit
    )
    assert_equal(orbited.distance(back), carved)


def test_envelope_rule_names_each_region_from_landmarks() raises:
    var envelope = CanonicalEnvelope(_spec())
    var skull_top = Vector3(0, envelope.neck_base + 0.15, 0)
    assert_true(envelope.region(skull_top) == HEAD_NECK_REGION)
    assert_true(envelope.region(Vector3(0, 0.25, 0)) == TRUNK_REGION)
    for side in range(2):
        var sign = Float32(1) - Float32(2 * side)
        var elbow = envelope.elbows[side]
        var wrist = envelope.wrists[side]
        var hand = (envelope.hands[side].low + envelope.hands[side].high) * 0.5
        var upper = elbow - envelope.upper_axes[side] * 0.08
        var fore = (elbow + wrist) * 0.5
        assert_true(
            envelope.region(upper)
            == BodyRegion(RIGHT_UPPER_ARM_REGION.value + 3 * side)
        )
        assert_true(
            envelope.region(fore)
            == BodyRegion(RIGHT_FOREARM_REGION.value + 3 * side)
        )
        assert_true(
            envelope.region(hand)
            == BodyRegion(RIGHT_HAND_REGION.value + 3 * side)
        )
        var x = sign * 0.09
        assert_true(
            envelope.region(Vector3(x, envelope.hip - 0.1, 0.0))
            == BodyRegion(RIGHT_THIGH_REGION.value + 3 * side)
        )
        assert_true(
            envelope.region(Vector3(x, envelope.knees[side] - 0.1, 0.0))
            == BodyRegion(RIGHT_SHANK_REGION.value + 3 * side)
        )
        assert_true(
            envelope.region(Vector3(x, envelope.malleoli[side] - 0.03, 0.05))
            == BodyRegion(RIGHT_FOOT_REGION.value + 3 * side)
        )
        # The whole eyeball is inside the canonical skin.
        var eye = envelope.eyes[side]
        var front = eye + Vector3(0, 0, envelope.eye_radius * 0.999)
        assert_true(envelope.distance(front) < 0)
    # The visual body has a crotch crease. The canonical skin does not:
    # a crease is a display seam, not a tissue boundary.
    var visual = BodySkinField(_spec())
    var seam = Vector3(0, visual.lower.crotch_top - 0.01, 0.0)
    assert_true(visual.distance(seam) > 0)
    assert_true(envelope.distance(seam) < 0)


def test_generated_parts_cover_the_whole_body() raises:
    var body = canonical_body(_spec())
    assert_equal(len(body.parts), PART_COUNT)
    var mass = Float64(0)
    var first = Vector3(0, 0, 0)
    var soft = muscle_tissue().wet_density.value
    for index in range(PART_COUNT):
        ref part = body.parts[index]
        assert_equal(part_index(part.region, part.tissue), index)
        var m = Float64(part.inertia.mass.value)
        assert_true(m > 0)
        assert_true(part.geometry.triangle_count() > 0)
        mass += m
        first = first + part.inertia.center * Float32(m)
        var v = Float64(part.volume.value)
        if part.tissue == SOFT_TISSUE:
            # One declared density for every non-bone cell.
            assert_almost_equal(m / v, Float64(soft), rtol=1e-5)
        else:
            # Bone apparent density lies between trabecular and cortical.
            assert_true(m / v > 400)
            assert_true(m / v <= 1800.001)
        # The closed part mesh agrees with the sampled volume.
        assert_almost_equal(_volume(part.geometry), v, rtol=0.2)
    # The whole body is the sum of the exclusive parts.
    assert_almost_equal(Float64(body.whole.mass.value), mass, rtol=1e-6)
    var center = first * Float32(1 / mass)
    assert_almost_equal(body.whole.center.y, center.y, atol=1e-5)
    assert_almost_equal(body.whole.center.z, center.z, atol=1e-5)
    # Parallel-axis sum of every part's tensor about the body's center.
    var xx = Float64(0)
    var yz = Float64(0)
    for index in range(PART_COUNT):
        ref part = body.parts[index]
        var m = Float64(part.inertia.mass.value)
        var d = part.inertia.center - body.whole.center
        xx += Float64(part.inertia.xx.value) + m * Float64(
            d.y * d.y + d.z * d.z
        )
        yz += Float64(part.inertia.yz.value) - m * Float64(d.y * d.z)
    assert_almost_equal(Float64(body.whole.xx.value), xx, rtol=1e-4)
    assert_almost_equal(Float64(body.whole.yz.value), yz, atol=1e-3)
    # The grid is symmetric, so mirrored limb parts match.
    for region in [
        RIGHT_UPPER_ARM_REGION,
        RIGHT_FOREARM_REGION,
        RIGHT_HAND_REGION,
        RIGHT_THIGH_REGION,
        RIGHT_SHANK_REGION,
        RIGHT_FOOT_REGION,
    ]:
        for tissue in [SOFT_TISSUE, BONE_TISSUE]:
            ref right = body.parts[part_index(region, tissue)]
            ref left = body.parts[
                part_index(BodyRegion(region.value + 3), tissue)
            ]
            assert_almost_equal(
                right.inertia.mass.value, left.inertia.mass.value, rtol=1e-5
            )
            assert_almost_equal(
                right.inertia.center.x, -left.inertia.center.x, atol=1e-5
            )
    # Every bone region holds the named bones of that region alone.
    assert_true(
        body.parts[part_index(LEFT_HAND_REGION, BONE_TISSUE)].inertia.center.x
        < 0
    )
    assert_true(
        body.parts[part_index(HEAD_NECK_REGION, BONE_TISSUE)].inertia.center.y
        > body.envelope.neck_base
    )


def test_record_is_versioned_and_refuses_each_change() raises:
    var body = canonical_body(_spec())
    var record = canonical_record(body)
    assert_equal(record.string("revision"), CANONICAL_PARTS_REVISION)
    assert_equal(record.string("spec_fingerprint"), spec_fingerprint(_spec()))
    assert_equal(
        record.json("canonical_inputs"), canonical_inputs(_spec()).to_json()
    )
    assert_equal(record.string("length_unit"), "meter")
    var parts_document = parse_json(record.json("parts"))
    var parts = user_data_of(parts_document, parts_document.root())
    var thigh_document = parse_json(parts.json("right-thigh.bone"))
    var thigh = user_data_of(thigh_document, thigh_document.root())
    assert_equal(
        thigh.string("geometry_digest"),
        geometry_digest(
            body.parts[part_index(RIGHT_THIGH_REGION, BONE_TISSUE)].geometry
        ),
    )
    assert_true(thigh.string("density_rule").startswith("bone-family"))
    var soft_document = parse_json(parts.json("trunk.soft"))
    var soft = user_data_of(soft_document, soft_document.root())
    assert_true(soft.string("density_rule").startswith("muscle_tissue"))
    require_canonical_record(_stored(record), record)
    with assert_raises(contains="No canonical parts record"):
        require_canonical_record(UserData(), record)
    var partial = record.copy()
    _ = partial.remove("parts_digest")
    with assert_raises(contains="record is incomplete"):
        require_canonical_record(_stored(partial), record)
    with assert_raises(contains="schema is unsupported"):
        require_canonical_record(_edited(record, "schema_version", "2"), record)
    with assert_raises(contains="revision changed"):
        require_canonical_record(
            _edited(record, "revision", '"threemojo-canonical-parts-v0"'),
            record,
        )
    with assert_raises(contains="another spec"):
        require_canonical_record(
            _edited(record, "spec_fingerprint", '"0000000000000000"'), record
        )
    with assert_raises(contains="another grid step"):
        require_canonical_record(_edited(record, "step_m", "0.005"), record)
    with assert_raises(contains="stale or changed"):
        require_canonical_record(_edited(record, "bones", "180"), record)


def test_visual_meshes_cannot_redefine_canonical_parts() raises:
    var body = canonical_body(_spec())
    var before = canonical_record(body)
    # A decimated, skinned, parted visual build changes nothing canonical.
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    var person = add_game_humanoid(
        scene, assets, parent, _spec(), 3000, 12, 8, 8, workers=1
    )
    assert_equal(canonical_record(body).to_json(), before.to_json())
    ref visual = assets.geometries.get(
        scene.skinned_meshes[person.skins[0]].geometry
    )
    with assert_raises(contains="mass and contact geometry"):
        require_part_geometry(body, TRUNK_REGION, SOFT_TISSUE, visual)
    ref own = body.parts[part_index(TRUNK_REGION, SOFT_TISSUE)].geometry
    require_part_geometry(body, TRUNK_REGION, SOFT_TISSUE, own)
    # One moved vertex is another mesh.
    var moved = own.clone()
    var positions = moved.clone_attribute(String(POSITION))
    positions.set_component(0, 0, positions.component(0, 0) + 1e-3)
    moved.set_attribute(String(POSITION), positions^)
    with assert_raises(contains="mass and contact geometry"):
        require_part_geometry(body, TRUNK_REGION, SOFT_TISSUE, moved)
    with assert_raises(contains="body region must be named"):
        require_part_geometry(body, BodyRegion(99), SOFT_TISSUE, own)


def test_bake_round_trip_keeps_spec_and_canonical_record() raises:
    var body = canonical_body(_spec())
    var record = canonical_record(body)
    var settings = game_build_settings(3000, 12, 8, 8)
    var provenance = humanoid_provenance(
        _spec(),
        settings,
        String(CANONICAL_RECIPE),
        String(GAME_RECIPE),
        "unverified-converted-ICTF-THRS",
    )
    var scene = Scene()
    var assets = Assets()
    var root = Object3D()
    root.name = "canonical"
    root.user_data.set_json(String(CANONICAL_PARTS_KEY), record.to_json())
    var node = scene.add(root^)
    var shape = BufferGeometry()
    var corners: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    shape.set_attribute(String(POSITION), BufferAttribute(corners^, 3))
    shape.set_index([0, 1, 2])
    var geometry = assets.geometries.add(shape^)
    var paint = assets.materials.add(Material(Color(1, 1, 1), kind=BASIC))
    scene.add_mesh(Mesh(geometry, paint, node))
    var path = temporary_path("canonical.glb")
    write_sealed_bake(path, scene, assets, provenance)
    var loaded_scene = Scene()
    var loaded_assets = Assets()
    var model = read_gltf(path, loaded_scene, loaded_assets)
    require_sealed_bake(
        model.scene_extras, provenance, loaded_scene, loaded_assets
    )
    # The exact spec comes back, so the same parts can be regenerated.
    var spec = stored_spec(model.scene_extras)
    assert_equal(
        canonical_inputs(spec).to_json(), canonical_inputs(_spec()).to_json()
    )
    var extras = loaded_scene.get(model.nodes[0]).user_data.copy()
    require_canonical_record(extras, record)
    # Editing the baked visual geometry breaks the bake, not the record.
    var mesh = loaded_scene.meshes[0].geometry
    var edited = loaded_assets.geometries.get(mesh).clone()
    var positions = edited.clone_attribute(String(POSITION))
    positions.set_component(1, 0, 2)
    edited.set_attribute(String(POSITION), positions^)
    loaded_assets.geometries.replace(mesh, edited^)
    with assert_raises(contains="does not match its digest"):
        require_sealed_bake(
            model.scene_extras, provenance, loaded_scene, loaded_assets
        )
    require_canonical_record(extras, record)
    with assert_raises(contains="no fidelity provenance"):
        _ = stored_spec(UserData())


def test_eye_genes_move_the_carved_orbits() raises:
    var genome = Genome()
    genome = genome.with_gene(EYE_SIZE, Expression(1))
    genome = genome.with_gene(EYE_SPACING, Expression(-1))
    genome = genome.with_gene(EYE_DEPTH, Expression(1))
    var spec = HumanoidSpec(Length(1.8288, METER), MALE, genome=genome)
    var skeleton = CanonicalSkeleton(spec)
    var template = CanonicalSkeleton(_spec())
    var skull = skeleton.find("skull")
    for side in range(2):
        # The eye moved, and its orbit moved with it.
        assert_true((skeleton.eyes[side] - template.eyes[side]).length() > 1e-3)
        assert_true(skeleton.orbit > template.orbit)
        var directions: List[Vector3] = [
            Vector3(1, 0, 0),
            Vector3(-1, 0, 0),
            Vector3(0, 1, 0),
            Vector3(0, -1, 0),
            Vector3(0, 0, 1),
            Vector3(0, 0, -1),
        ]
        for direction in directions:
            var surface = skeleton.eyes[side] + direction * (
                skeleton.orbit - Float32(ORBIT_CLEARANCE.value)
            )
            var d, _ = skeleton.probe(skull, surface)
            assert_true(d >= Float32(ORBIT_CLEARANCE.value) - 1e-5)


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
