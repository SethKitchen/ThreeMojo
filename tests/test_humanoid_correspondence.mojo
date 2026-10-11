# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Canonical records, mappings, bake content, sources and fit checks."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from core.user_data import UserData, user_data_of
from exporters.gltf import GLB, GltfExportOptions, write_gltf
from extensions.humanoid.bake import (
    CONTENT_KEY,
    CONTENT_SCHEMA,
    bake_content,
    mesh_inventory,
    require_bake_content,
)
from extensions.humanoid.canonical import (
    AUTHORED_TEETH_PART,
    CANONICAL_KEY,
    CANONICAL_RECORD_REVISION,
    LEFT_EYE_PART,
    LEFT_FOOT_PART,
    MANDIBLE_PART,
    RIGHT_EYE_PART,
    RIGHT_THIGH_PART,
    SKULL_PART,
    CanonicalPart,
    canonical_part_label,
    canonical_part_record,
    canonical_record,
    canonical_record_digest,
    named_canonical_parts,
    require_canonical_record,
)
from extensions.humanoid.fidelity import (
    CANONICAL_RECIPE,
    FIDELITY_KEY,
    GAME_RECIPE,
    geometry_fingerprint,
    humanoid_provenance,
    topology_fingerprint,
)
from extensions.humanoid.fit import (
    dental_fit,
    eye_bone_fit,
    require_clearance,
    require_containment,
    skin_bone_fit,
)
from extensions.humanoid.genome import (
    FACE_SHAPE_1,
    FACE_SHAPE_8,
    GENE_COUNT,
    Expression,
    Gene,
    Genome,
)
from extensions.humanoid.mapping import (
    DENTAL_MAP,
    EXPRESSION_JAW_MAP,
    EYE_MAP,
    IDENTITY_MAP,
    LOD_MAP,
    SKIN_WEIGHT_MAP,
    MappingKind,
    mapping_label,
    mapping_record,
    named_mappings,
    require_mapping,
    require_physical_mapping,
)
from extensions.humanoid.rig.game import (
    add_game_humanoid,
    exact_skin_weights,
    game_build_settings,
)
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.skeleton.head.bones.dimensions import (
    MANDIBLE,
    SKULL,
)
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.head.hair.styles import (
    GROWN,
    LAYERED,
    HairStyle,
)
from extensions.humanoid.sources import (
    CONVERTED_MANIFEST,
    FACE_ASSET,
    converted_sources,
    file_sha256,
    game_source_paths,
    sha256_hex,
)
from extensions.humanoid.spec import HumanoidSpec
from loaders.gltf import read_gltf
from loaders.json import parse_json
from extensions.humanoid.assets import humanoid_asset_path
from objects.skinned_mesh import (
    SKIN_INDEX,
    SKIN_WEIGHT,
    normalized_skin_weights,
)
from tests.test_scratch import TestScratch, temporary_path
from std.os import getenv, makedirs, setenv
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def _spec() -> HumanoidSpec:
    return HumanoidSpec(Length(1.8288, METER), MALE)


def _every_gene(value: Float32) raises -> Genome:
    var genome = Genome()
    for at in range(GENE_COUNT):
        genome = genome.with_gene(Gene(at), Expression(value))
    return genome^


def _face_genes(value: Float32) raises -> Genome:
    var genome = Genome()
    for at in range(FACE_SHAPE_1.value, FACE_SHAPE_8.value + 1):
        genome = genome.with_gene(Gene(at), Expression(value))
    return genome^


def _parsed(text: String) raises -> UserData:
    var document = parse_json(text)
    return user_data_of(document, document.root())


def _bytes(text: String) -> List[UInt8]:
    return List[UInt8](text.as_bytes())


def _expected(budget: Int, sources: UserData) raises -> UserData:
    return humanoid_provenance(
        _spec(),
        game_build_settings(budget, 12, 8, 8),
        String(CANONICAL_RECIPE),
        String(GAME_RECIPE),
        String(CONVERTED_MANIFEST),
        sources,
    )


def test_sha256_matches_fips_vectors_and_the_pinned_face() raises:
    assert_equal(
        sha256_hex(List[UInt8]()),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    )
    assert_equal(
        sha256_hex(_bytes("abc")),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    )
    assert_equal(
        sha256_hex(
            _bytes("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
        ),
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
    )
    # Padding fits in one block at 55 bytes, and needs two at 64 and 119.
    assert_equal(
        sha256_hex(_bytes(String("a") * 55)),
        "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
    )
    assert_equal(
        sha256_hex(_bytes(String("a") * 64)),
        "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
    )
    assert_equal(
        sha256_hex(_bytes(String("a") * 119)),
        "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb",
    )
    # The manifest pins this digest of the bundled face model (#303).
    assert_equal(
        file_sha256(humanoid_asset_path(String(FACE_ASSET))),
        "a1e9423fdbd88363e3ab9582e395720003d1459c8ed8ea5d55214b0148163271",
    )
    with assert_raises():
        _ = file_sha256(temporary_path("no such file"))


def test_converted_sources_bind_pinned_upstream_revisions() raises:
    var paths = game_source_paths(0, LAYERED)
    assert_equal(len(paths), 1)
    assert_equal(len(game_source_paths(4, GROWN)), 1)
    paths = game_source_paths(4, LAYERED)
    assert_equal(len(paths), 2)
    assert_equal(paths[1], "assets/hair/layered.bin")
    with assert_raises(contains="named hair style"):
        _ = game_source_paths(0, HairStyle(-1))
    var record = converted_sources(paths)
    assert_equal(record.string("manifest"), String(CONVERTED_MANIFEST))
    assert_equal(record.number("manifest_schema"), 2)
    var assets = _parsed(record.json("assets"))
    var face = _parsed(assets.json(String(FACE_ASSET)))
    assert_equal(
        face.string("sha256"),
        "a1e9423fdbd88363e3ab9582e395720003d1459c8ed8ea5d55214b0148163271",
    )
    assert_equal(face.string("source_id"), "ict")
    assert_equal(
        face.string("repository"), "https://github.com/USC-ICT/ICT-FaceKit"
    )
    assert_equal(
        face.string("revision"), "da5f95a607f5e6b37755b38d3385d7f2853732e5"
    )
    assert_equal(face.number("format_version"), 6)
    assert_equal(face.string("license"), "MIT")
    var hair = _parsed(assets.json("assets/hair/layered.bin"))
    assert_equal(hair.string("source_id"), "sintel")
    assert_equal(hair.string("license"), "CC-BY-3.0")
    with assert_raises(contains="at least one asset"):
        _ = converted_sources(List[String]())
    # A file the manifest hashes but does not pin as a production asset.
    with assert_raises(contains="not pinned by the manifest"):
        _ = converted_sources(["assets/converted-fixtures/face/still.obj"])
    with assert_raises(contains="manifest has no"):
        _ = converted_sources(["assets/face/other.bin"])


def test_changed_or_foreign_sources_are_refused() raises:
    var manifest = Path(
        humanoid_asset_path(String(CONVERTED_MANIFEST))
    ).read_bytes()
    var root = temporary_path("asset-root")
    makedirs(root + "/face", exist_ok=True)
    var saved = getenv("THREEMOJO_ASSET_ROOT", "")
    _ = setenv("THREEMOJO_ASSET_ROOT", root)
    Path(root + "/converted-asset-manifest.json").write_bytes(manifest)
    Path(root + "/face/ict_face.bin").write_text("an edited face model")
    with assert_raises(contains="does not match its pinned manifest"):
        _ = converted_sources([String(FACE_ASSET)])
    Path(root + "/converted-asset-manifest.json").write_text(
        '{"schema_version": 1}'
    )
    with assert_raises(contains="schema is unsupported"):
        _ = converted_sources([String(FACE_ASSET)])
    _ = setenv("THREEMOJO_ASSET_ROOT", saved)


def test_mapping_kinds_are_typed_and_named() raises:
    assert_equal(len(named_mappings()), 6)
    for kind in named_mappings():
        assert_true(kind.is_valid())
    assert_false(MappingKind(-1).is_valid())
    assert_false(MappingKind(6).is_valid())
    assert_equal(mapping_label(IDENTITY_MAP), "identity")
    assert_equal(mapping_label(EXPRESSION_JAW_MAP), "expression_jaw")
    assert_equal(mapping_label(EYE_MAP), "eyes")
    assert_equal(mapping_label(DENTAL_MAP), "dental")
    assert_equal(mapping_label(SKIN_WEIGHT_MAP), "skin_weights")
    assert_equal(mapping_label(LOD_MAP), "lod")
    assert_equal(mapping_label(MappingKind(9)), "mapping")
    with assert_raises(contains="named kind"):
        _ = mapping_record(MappingKind(9), "source", "topology")
    with assert_raises(contains="source and topology"):
        _ = mapping_record(IDENTITY_MAP, "", "topology")
    with assert_raises(contains="source and topology"):
        _ = mapping_record(IDENTITY_MAP, "source", "")
    for kind in named_mappings():
        var record = mapping_record(kind, "source", "topology")
        assert_true(record.boolean("visual_use"))
        assert_false(record.boolean("physical_correspondence"))
        assert_true(record.string("scope") != "")
        assert_equal(record.has("representations"), kind == DENTAL_MAP)
        # No mapping is a tested physical correspondence.
        with assert_raises(contains="correspondence is unsupported"):
            require_physical_mapping(kind)
    with assert_raises(contains="named kind"):
        require_physical_mapping(MappingKind(9))
    # Both dentitions stay named until a tested map exists.
    var dental = mapping_record(DENTAL_MAP, "source", "topology")
    assert_equal(
        dental.json("representations"),
        '["authored-bones-teeth-field","scanned-mouth-teeth"]',
    )


def test_changed_sources_and_topologies_invalidate_mappings() raises:
    var stored = mapping_record(SKIN_WEIGHT_MAP, "rig-a", "mesh-a")
    require_mapping(stored, SKIN_WEIGHT_MAP, "rig-a", "mesh-a")
    with assert_raises(contains="not the lod mapping"):
        require_mapping(stored, LOD_MAP, "rig-a", "mesh-a")
    var edited = stored.copy()
    _ = edited.remove("kind")
    with assert_raises(contains="not the skin_weights mapping"):
        require_mapping(edited, SKIN_WEIGHT_MAP, "rig-a", "mesh-a")
    with assert_raises(contains="source changed"):
        require_mapping(stored, SKIN_WEIGHT_MAP, "rig-b", "mesh-a")
    edited = stored.copy()
    _ = edited.remove("source_fingerprint")
    with assert_raises(contains="source changed"):
        require_mapping(edited, SKIN_WEIGHT_MAP, "rig-a", "mesh-a")
    with assert_raises(contains="topology changed"):
        require_mapping(stored, SKIN_WEIGHT_MAP, "rig-a", "mesh-b")
    edited = stored.copy()
    _ = edited.remove("topology_fingerprint")
    with assert_raises(contains="topology changed"):
        require_mapping(edited, SKIN_WEIGHT_MAP, "rig-a", "mesh-a")
    edited = stored.copy()
    edited.set_boolean("physical_correspondence", True)
    with assert_raises(contains="was edited"):
        require_mapping(edited, SKIN_WEIGHT_MAP, "rig-a", "mesh-a")
    with assert_raises(contains="named kind"):
        require_mapping(stored, MappingKind(9), "rig-a", "mesh-a")


def _triangle() raises -> BufferGeometry:
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        BufferAttribute([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0], 3),
    )
    return geometry^


def test_geometry_fingerprints_cover_exact_bytes() raises:
    var plain = _triangle()
    var record = geometry_fingerprint(plain)
    assert_equal(record.number("vertices"), 3)
    assert_equal(record.number("triangles"), 1)
    assert_equal(record.string("skin"), "none")
    assert_equal(record.string("morphs"), "none")
    assert_equal(record.string("topology"), topology_fingerprint(plain))
    var indexed = _triangle()
    indexed.index = [0, 2, 1]
    assert_true(topology_fingerprint(indexed) != topology_fingerprint(plain))
    var moved = _triangle()
    moved.set_attribute(
        String(POSITION),
        BufferAttribute([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0e-7], 3),
    )
    var changed = geometry_fingerprint(moved)
    assert_equal(changed.string("topology"), record.string("topology"))
    assert_true(changed.string("positions") != record.string("positions"))
    var half = _triangle()
    half.set_attribute(
        String(SKIN_INDEX), BufferAttribute(List[Float32](length=12, fill=0), 4)
    )
    with assert_raises(contains="both skin indices and weights"):
        _ = geometry_fingerprint(half)
    var other = _triangle()
    other.set_attribute(
        String(SKIN_WEIGHT),
        BufferAttribute(List[Float32](length=12, fill=0), 4),
    )
    with assert_raises(contains="both skin indices and weights"):
        _ = geometry_fingerprint(other)
    half.set_attribute(
        String(SKIN_WEIGHT),
        BufferAttribute(List[Float32](length=12, fill=0), 4),
    )
    assert_true(geometry_fingerprint(half).string("skin") != "none")
    var morphing = _triangle()
    morphing.morph_positions.append(
        BufferAttribute(List[Float32](length=9, fill=0.5), 3)
    )
    var morphed = geometry_fingerprint(morphing)
    assert_equal(morphed.number("morph_targets"), 1)
    assert_true(morphed.string("morphs") != "none")


def test_exact_skin_weights_survive_loader_normalization() raises:
    var part = _triangle()
    part.set_attribute(
        String(SKIN_WEIGHT),
        BufferAttribute(
            [
                Float32(0.3),
                0.3,
                0.3,
                0.1,
                0.0,
                0.0,
                0.0,
                0.0,
                0.2,
                0.7,
                0.05,
                0.05,
            ],
            4,
        ),
    )
    exact_skin_weights(part)
    ref weights = part.attribute_view(String(SKIN_WEIGHT))
    for vertex in range(3):
        var four = SIMD[DType.float32, 4](
            weights.component(vertex, 0),
            weights.component(vertex, 1),
            weights.component(vertex, 2),
            weights.component(vertex, 3),
        )
        assert_equal(four.cast[DType.float64]().reduce_add(), 1.0)
        # The loader's normalization keeps every bit.
        assert_equal(normalized_skin_weights(four), four)
    # A vertex without weight goes to its first bone, as three.js does.
    assert_equal(weights.component(1, 0), 1.0)
    assert_true(abs(weights.component(2, 1) - 0.7) < 1.0e-6)
    with assert_raises():
        var bare = _triangle()
        exact_skin_weights(bare)


def test_canonical_parts_are_typed_and_carry_si_properties() raises:
    assert_equal(len(named_canonical_parts()), 11)
    assert_false(CanonicalPart(-1).is_valid())
    assert_false(CanonicalPart(11).is_valid())
    assert_equal(canonical_part_label(CanonicalPart(11)), "canonical part")
    assert_equal(canonical_part_label(SKULL_PART), "head/skull")
    assert_equal(canonical_part_label(LEFT_FOOT_PART), "leg-left/foot")
    with assert_raises(contains="must be named"):
        _ = canonical_part_record(_spec(), CanonicalPart(11))
    var thigh = canonical_part_record(_spec(), RIGHT_THIGH_PART)
    assert_equal(thigh.string("part_id"), "leg-right/thigh")
    assert_equal(thigh.string("origin_label"), "tibiofemoral-joint-line")
    var labels = parse_json(thigh.json("tissue_labels"))
    assert_equal(labels.length(labels.root()), 7)
    var physical = _parsed(thigh.json("physical_properties"))
    assert_true(physical.number("mass_kg") > 1)
    assert_equal(physical.string("tensor_reference"), "center-of-mass")
    var tensor = parse_json(physical.json("inertia_kg_m2"))
    assert_equal(tensor.length(tensor.root()), 6)
    var foot = canonical_part_record(_spec(), LEFT_FOOT_PART)
    assert_equal(foot.string("part_id"), "leg-left/foot")
    var eye = canonical_part_record(_spec(), LEFT_EYE_PART)
    assert_equal(eye.json("physical_properties"), "null")
    assert_true(_parsed(eye.json("geometry")).number("radius_m") > 0.01)
    var right = canonical_part_record(_spec(), RIGHT_EYE_PART)
    assert_true(right.json("geometry") != eye.json("geometry"))
    var mandible = canonical_part_record(_spec(), MANDIBLE_PART)
    var bone = _parsed(mandible.json("physical_properties"))
    assert_true(bone.number("mass_kg") > 0)
    assert_equal(bone.json("inertia_kg_m2"), "null")
    var geometry = _parsed(mandible.json("geometry"))
    assert_true(geometry.number("triangles") > 0)
    assert_equal(geometry.string("kind"), "isosurface-mesh")


def test_canonical_record_survives_decimation_and_a_bake() raises:
    var record = canonical_record(_spec())
    assert_equal(record.string("revision"), String(CANONICAL_RECORD_REVISION))
    assert_false(record.boolean("engineering_validated"))
    assert_equal(_parsed(record.json("parts")).count(), 11)
    # A decimated game build and its bake do not touch the record.
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    var person = add_game_humanoid(
        scene, assets, parent, _spec(), 3000, 12, 8, 8
    )
    var options = GltfExportOptions()
    options.scene_user_data.set_json(String(CANONICAL_KEY), record.to_json())
    var path = temporary_path("canonical.glb")
    write_gltf(path, scene, assets, GLB, options=options^)
    var loaded = Scene()
    var loaded_assets = Assets()
    var model = read_gltf(path, loaded, loaded_assets)
    var stored = _parsed(model.scene_extras.json(String(CANONICAL_KEY)))
    require_canonical_record(stored, _spec())
    assert_equal(
        canonical_record_digest(stored), canonical_record_digest(record)
    )
    var content = _parsed(
        scene.get(person.root).user_data.json(String(CONTENT_KEY))
    )
    # The visual derivative's digests are not the canonical record's.
    assert_true(
        content.string("content_digest") != canonical_record_digest(record)
    )
    var edited = stored.copy()
    edited.set_number("schema_version", 2)
    with assert_raises(contains="schema is unsupported"):
        require_canonical_record(edited, _spec())
    _ = edited.remove("schema_version")
    with assert_raises(contains="schema is unsupported"):
        require_canonical_record(edited, _spec())
    edited = stored.copy()
    edited.set_string("revision", "older")
    with assert_raises(contains="revision is stale"):
        require_canonical_record(edited, _spec())
    _ = edited.remove("revision")
    with assert_raises(contains="revision is stale"):
        require_canonical_record(edited, _spec())
    edited = stored.copy()
    _ = edited.remove("spec_fingerprint")
    with assert_raises(contains="different spec"):
        require_canonical_record(edited, _spec())
    var other = _spec()
    other.genome = other.genome.with_gene(FACE_SHAPE_1, Expression(1))
    with assert_raises(contains="different spec"):
        require_canonical_record(stored, other)
    edited = stored.copy()
    edited.set_boolean("engineering_validated", True)
    with assert_raises(contains="stale or changed"):
        require_canonical_record(edited, _spec())


def test_identity_moves_the_scan_but_not_canonical_bones() raises:
    # Face-shape genes reshape scanned skin and teeth. The canonical skull,
    # mandible and authored teeth stay as the template made them.
    var shaped = _spec()
    shaped.genome = _face_genes(1)
    for part in [SKULL_PART, MANDIBLE_PART, AUTHORED_TEETH_PART]:
        var before = _parsed(
            canonical_part_record(_spec(), part).json("geometry")
        )
        var after = _parsed(
            canonical_part_record(shaped, part).json("geometry")
        )
        assert_equal(before.string("positions"), after.string("positions"))
    # The eyes follow the identity's mean shift.
    assert_true(
        canonical_part_record(_spec(), RIGHT_EYE_PART).json("geometry")
        != canonical_part_record(shaped, RIGHT_EYE_PART).json("geometry")
    )
    var template = dental_fit(head_muscle_dimensions(_spec()))
    var moved = dental_fit(head_muscle_dimensions(shaped))
    assert_true(template.maximum.value != moved.maximum.value)


def test_extreme_identities_keep_finite_canonical_records() raises:
    var short = HumanoidSpec(Length(1.2, METER), FEMALE, genome=_every_gene(1))
    var tall = HumanoidSpec(Length(2.5, METER), MALE, genome=_every_gene(-1))
    var low = canonical_record(short)
    var high = canonical_record(tall)
    require_canonical_record(low, short)
    assert_true(low.string("parts_digest") != high.string("parts_digest"))
    var thigh = _parsed(
        _parsed(_parsed(high.json("parts")).json("leg-right/thigh")).json(
            "physical_properties"
        )
    )
    assert_true(thigh.number("mass_kg") > 1)


def test_eye_dental_and_tissue_fit_are_measured_and_refused() raises:
    var template = head_muscle_dimensions(_spec())
    # The fitted skin clears the authored skull on the template.
    var skin = skin_bone_fit(template, SKULL)
    assert_true(skin.samples > 1000)
    assert_equal(skin.inside, 0)
    require_clearance(skin, Length(0, METER), "skin-skull")
    # Even the template's skin lies just inside the authored mandible.
    assert_true(skin_bone_fit(template, MANDIBLE).minimum.value < 0)
    # An extreme identity pushes the scan inside the skull and mandible.
    var shaped = _spec()
    shaped.genome = _face_genes(1)
    var dims = head_muscle_dimensions(shaped)
    with assert_raises(contains="skin-skull clearance fails"):
        require_clearance(
            skin_bone_fit(dims, SKULL), Length(0, METER), "skin-skull"
        )
    with assert_raises(contains="skin-mandible clearance fails"):
        require_clearance(
            skin_bone_fit(dims, MANDIBLE), Length(0, METER), "skin-mandible"
        )
    var tall = HumanoidSpec(Length(2.5, METER), MALE, genome=_every_gene(-1))
    with assert_raises(contains="clearance fails"):
        require_clearance(
            skin_bone_fit(head_muscle_dimensions(tall), SKULL),
            Length(0, METER),
            "skin-skull",
        )
    # The identity-placed eyeballs enter the authored skull field.
    for side in [RIGHT, LEFT]:
        var eye = eye_bone_fit(template, side, SKULL)
        assert_true(eye.minimum.value < 0)
        with assert_raises(contains="eye-skull clearance fails"):
            require_clearance(eye, Length(0, METER), "eye-skull")
    # The scanned teeth lie far outside the authored teeth.
    var teeth = dental_fit(template)
    assert_true(teeth.inside < teeth.samples)
    assert_true(teeth.maximum.value > 0.01)
    with assert_raises(contains="dental correspondence fails"):
        require_containment(teeth, Length(0.001, METER), "dental")
    require_containment(teeth, Length(1, METER), "dental")


def _content_root(scene: Scene) raises -> NodeId:
    for node in scene.traverse():
        if node != NO_PARENT and scene.get(node).user_data.has(
            String(CONTENT_KEY)
        ):
            return node
    raise Error("no humanoid root")


def _rewrite(
    mut scene: Scene, root: NodeId, key: String, var content: UserData
) raises:
    var node = scene.get(root)
    node.user_data.set_json(key, content.to_json())
    scene.set(root, node^)


def test_an_empty_root_has_an_empty_inventory() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var inventory = mesh_inventory(scene, assets, root)
    assert_equal(inventory.json("skinned"), "[]")
    assert_equal(inventory.json("rigid"), "[]")


def test_bake_content_binds_meshes_and_mappings() raises:
    var sources = converted_sources(game_source_paths(0, GROWN))
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    var person = add_game_humanoid(
        scene, assets, parent, _spec(), 3000, 12, 8, 8
    )
    var expected = _expected(3000, sources)
    require_bake_content(scene, assets, person.root, expected)
    var content = _parsed(
        scene.get(person.root).user_data.json(String(CONTENT_KEY))
    )
    assert_equal(content.number("schema_version"), Float64(CONTENT_SCHEMA))
    var mappings = _parsed(content.json("mappings"))
    assert_equal(mappings.count(), 6)
    var identity = _parsed(mappings.json("identity"))
    assert_equal(
        identity.string("source_fingerprint"),
        "a1e9423fdbd88363e3ab9582e395720003d1459c8ed8ea5d55214b0148163271",
    )
    # A round trip through a GLB keeps every checked byte.
    var path = temporary_path("content.glb")
    write_gltf(path, scene, assets, GLB)
    var loaded = Scene()
    var loaded_assets = Assets()
    _ = read_gltf(path, loaded, loaded_assets)
    var root = _content_root(loaded)
    require_bake_content(loaded, loaded_assets, root, expected)
    # Another spec or other settings make the bake stale.
    with assert_raises(contains="visual settings are stale"):
        require_bake_content(
            loaded, loaded_assets, root, _expected(2000, sources)
        )
    # An edited vertex is a changed mesh.
    var geometry = loaded_assets.geometries.get(
        loaded.skinned_meshes[0].geometry
    ).clone()
    var positions = geometry.clone_attribute(String(POSITION))
    positions.data[0] += 0.001
    geometry.set_attribute(String(POSITION), positions^)
    var bent = loaded_assets.geometries.add(geometry^)
    var original = loaded.skinned_meshes[0].geometry
    loaded.skinned_meshes[0].geometry = bent
    with assert_raises(contains="mesh content changed"):
        require_bake_content(loaded, loaded_assets, root, expected)
    loaded.skinned_meshes[0].geometry = original
    require_bake_content(loaded, loaded_assets, root, expected)
    # Edited, missing or foreign content records are refused.
    var edited = content.copy()
    edited.set_number("schema_version", 2)
    _rewrite(loaded, root, String(CONTENT_KEY), edited^)
    with assert_raises(contains="content schema is unsupported"):
        require_bake_content(loaded, loaded_assets, root, expected)
    edited = content.copy()
    _ = edited.remove("schema_version")
    _rewrite(loaded, root, String(CONTENT_KEY), edited^)
    with assert_raises(contains="content schema is unsupported"):
        require_bake_content(loaded, loaded_assets, root, expected)
    edited = content.copy()
    edited.set_string("recipe_digest", "0000000000000000")
    _rewrite(loaded, root, String(CONTENT_KEY), edited^)
    with assert_raises(contains="belongs to another recipe"):
        require_bake_content(loaded, loaded_assets, root, expected)
    edited = content.copy()
    edited.set_string("content_digest", "0000000000000000")
    _rewrite(loaded, root, String(CONTENT_KEY), edited^)
    with assert_raises(contains="content record was edited"):
        require_bake_content(loaded, loaded_assets, root, expected)
    for kind in named_mappings():
        var label = mapping_label(kind)
        var changed = mappings.copy()
        _ = changed.remove(label)
        edited = content.copy()
        edited.set_json("mappings", changed.to_json())
        _rewrite(loaded, root, String(CONTENT_KEY), edited^)
        with assert_raises(contains="has no " + label + " mapping"):
            require_bake_content(loaded, loaded_assets, root, expected)
        var mapping = _parsed(mappings.json(label))
        mapping.set_string("topology_fingerprint", "foreign")
        changed = mappings.copy()
        changed.set_json(label, mapping.to_json())
        edited = content.copy()
        edited.set_json("mappings", changed.to_json())
        _rewrite(loaded, root, String(CONTENT_KEY), edited^)
        with assert_raises(contains=label + " mapping topology changed"):
            require_bake_content(loaded, loaded_assets, root, expected)
    var node = loaded.get(root)
    _ = node.user_data.remove(String(CONTENT_KEY))
    loaded.set(root, node^)
    with assert_raises(contains="no content record"):
        require_bake_content(loaded, loaded_assets, root, expected)


def test_lod_and_source_changes_invalidate_mappings() raises:
    var sources = converted_sources(game_source_paths(0, GROWN))
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    var coarse = add_game_humanoid(
        scene, assets, parent, _spec(), 3000, 12, 8, 8
    )
    var fine = add_game_humanoid(scene, assets, parent, _spec(), 3000, 16, 8, 8)
    var first = _parsed(
        _parsed(
            scene.get(coarse.root).user_data.json(String(CONTENT_KEY))
        ).json("mappings")
    )
    var second = _parsed(
        _parsed(scene.get(fine.root).user_data.json(String(CONTENT_KEY))).json(
            "mappings"
        )
    )
    # Another full-resolution source invalidates the level of detail.
    var lod = _parsed(first.json("lod"))
    var rebuilt = _parsed(second.json("lod"))
    with assert_raises(contains="lod mapping source changed"):
        require_mapping(
            lod,
            LOD_MAP,
            rebuilt.string("source_fingerprint"),
            lod.string("topology_fingerprint"),
        )
    # Another face model source invalidates every face mapping.
    for kind in [IDENTITY_MAP, EXPRESSION_JAW_MAP, EYE_MAP, DENTAL_MAP]:
        var mapping = _parsed(first.json(mapping_label(kind)))
        with assert_raises(contains="source changed"):
            require_mapping(
                mapping,
                kind,
                String("0") * 64,
                mapping.string("topology_fingerprint"),
            )
    # A record without verified face sources names that limit.
    var unverified = humanoid_provenance(
        _spec(),
        game_build_settings(3000, 12, 8, 8),
        String(CANONICAL_RECIPE),
        String(GAME_RECIPE),
        "synthetic",
    )
    var content = bake_content(scene, assets, coarse.root, unverified, "lod")
    var identity = _parsed(_parsed(content.json("mappings")).json("identity"))
    assert_equal(identity.string("source_fingerprint"), "unverified-face-model")
    var hair_only = humanoid_provenance(
        _spec(),
        game_build_settings(3000, 12, 8, 8),
        String(CANONICAL_RECIPE),
        String(GAME_RECIPE),
        "hair only",
        converted_sources(["assets/hair/layered.bin"]),
    )
    content = bake_content(scene, assets, coarse.root, hair_only, "lod")
    identity = _parsed(_parsed(content.json("mappings")).json("identity"))
    assert_equal(identity.string("source_fingerprint"), "unverified-face-model")
    # Each build's inventory covers only its own meshes.
    assert_true(
        mesh_inventory(scene, assets, coarse.root).to_json()
        != mesh_inventory(scene, assets, fine.root).to_json()
    )
    _ = sources


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
