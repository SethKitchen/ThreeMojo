# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Synthetic contracts and a real bundled-asset humanoid GLB round trip."""

from core.assets import Assets
from core.object3d import NO_PARENT, Object3D
from core.buffer_geometry import POSITION
from core.scene import Scene
from core.user_data import UserData
from exporters.gltf import (
    GLB,
    GLTF_EMBEDDED,
    GltfExportOptions,
    export_gltf,
    write_gltf,
)
from extensions.humanoid.athleticism import Athleticism
from extensions.humanoid.fidelity import (
    CANONICAL_RECIPE,
    CANONICAL_TO_LOCAL_REST,
    ENGINEERING_USE,
    FIDELITY_KEY,
    FIDELITY_SCHEMA,
    FINGERPRINT_ALGORITHM,
    GAME_RECIPE,
    VISUAL_USE,
    HumanoidUse,
    canonical_inputs,
    humanoid_provenance,
    json_fingerprint,
    require_bake_provenance,
    require_current_spec,
    require_humanoid_use,
    settings_fingerprint,
    spec_fingerprint,
    stored_provenance,
)
from extensions.humanoid.genome import (
    FACE_SHAPE_1,
    GENE_COUNT,
    Expression,
    Gene,
    Genome,
)
from extensions.humanoid.rig.game import add_game_humanoid, game_build_settings
from extensions.humanoid.skeleton.head.hair.styles import HairStyle
from extensions.humanoid.sex import MALE, Sex
from extensions.humanoid.spec import HumanoidSpec
from core.user_data import user_data_of
from loaders.gltf import load_gltf, read_gltf
from loaders.json import parse_json
from tests.test_scratch import TestScratch, temporary_path
from std.memory import bitcast
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


def _provenance(spec: HumanoidSpec, budget: Int = 10000) raises -> UserData:
    return humanoid_provenance(
        spec,
        game_build_settings(budget),
        String(CANONICAL_RECIPE),
        String(GAME_RECIPE),
        "synthetic-no-source-assets",
    )


def test_capabilities_are_independent_and_fail_closed() raises:
    assert_true(VISUAL_USE.is_valid())
    assert_true(ENGINEERING_USE.is_valid())
    assert_false(HumanoidUse(-1).is_valid())
    assert_false(HumanoidUse(2).is_valid())
    require_humanoid_use(VISUAL_USE)
    with assert_raises(contains="named capability"):
        require_humanoid_use(HumanoidUse(3))
    with assert_raises(contains="Engineering use is unsupported"):
        require_humanoid_use(ENGINEERING_USE)
    var record = _provenance(_spec())
    assert_true(record.boolean("visual_use"))
    assert_false(record.boolean("engineering_use"))
    assert_false(record.boolean("canonical_geometry_embedded"))
    assert_false(record.boolean("physical_properties_embedded"))
    assert_false(record.boolean("source_manifest_verified"))


def test_inputs_retain_si_and_extreme_identity_values() raises:
    var spec = _spec()
    var original = canonical_inputs(spec).to_json()
    for at in range(GENE_COUNT):
        for weight in [Float32(-1), Float32(1)]:
            spec.genome = Genome().with_gene(Gene(at), Expression(weight))
            var record = _provenance(spec)
            assert_false(record.boolean("engineering_use"))
            assert_true(canonical_inputs(spec).to_json() != original)
    spec = _spec()
    spec.stature = Length(1.2, METER)
    _ = canonical_inputs(spec)
    spec.stature = Length(2.5, METER)
    _ = canonical_inputs(spec)
    spec = _spec()
    var copy = canonical_inputs(spec)
    spec.genome = spec.genome.with_gene(FACE_SHAPE_1, Expression(1))
    assert_equal(copy.to_json(), original)
    assert_true(copy.to_json() != canonical_inputs(spec).to_json())
    # Adjacent Float32 inputs must not alias through decimal formatting.
    spec = _spec()
    spec.stature = Length(
        bitcast[DType.float32](bitcast[DType.uint32](spec.stature.value) + 1),
        METER,
    )
    assert_true(canonical_inputs(spec).to_json() != original)


def test_invalid_specs_and_missing_revisions_are_refused() raises:
    var spec = _spec()
    spec.stature = Length(bitcast[DType.float32](UInt32(0x7F800000)), METER)
    with assert_raises(contains="finite stature"):
        _ = canonical_inputs(spec)
    spec.stature = Length(1.19, METER)
    with assert_raises(contains="software range"):
        _ = canonical_inputs(spec)
    spec.stature = Length(2.51, METER)
    with assert_raises(contains="software range"):
        _ = canonical_inputs(spec)
    spec = _spec()
    spec.sex = Sex(8)
    with assert_raises(contains="named sex"):
        _ = canonical_inputs(spec)
    spec = _spec()
    spec.athleticism = Athleticism(8)
    with assert_raises(contains="named athleticism"):
        _ = canonical_inputs(spec)
    spec = _spec()
    spec.genome.expressions[0] = 2
    with assert_raises(contains="valid genome"):
        _ = canonical_inputs(spec)
    with assert_raises(contains="named hair style"):
        _ = game_build_settings(hair_style=HairStyle(-1))
    var settings = UserData()
    with assert_raises(contains="canonical revision"):
        _ = humanoid_provenance(_spec(), settings, "", "visual", "asset")
    with assert_raises(contains="visual revision"):
        _ = humanoid_provenance(_spec(), settings, "canonical", "", "asset")
    with assert_raises(contains="asset revision"):
        _ = humanoid_provenance(_spec(), settings, "canonical", "visual", "")


def test_stale_inputs_options_and_capability_edits_are_refused() raises:
    var stored = UserData()
    var expected = _provenance(_spec())
    with assert_raises(contains="no fidelity provenance"):
        require_bake_provenance(stored, expected)
    stored.set_json(String(FIDELITY_KEY), expected.to_json())
    require_bake_provenance(stored, expected)
    with assert_raises(contains="visual settings are stale"):
        require_bake_provenance(stored, _provenance(_spec(), 500))
    var spec = _spec()
    spec.genome = spec.genome.with_gene(FACE_SHAPE_1, Expression(1))
    with assert_raises(contains="spec fingerprint is stale"):
        require_bake_provenance(stored, _provenance(spec))
    var changed = _provenance(_spec())
    changed.set_boolean("engineering_use", True)
    stored.set_json(String(FIDELITY_KEY), changed.to_json())
    with assert_raises(contains="stale or changed"):
        require_bake_provenance(stored, expected)
    stored.set_json(String(FIDELITY_KEY), expected.to_json())
    for revisions in ["canonical", "visual", "asset"]:
        var next = humanoid_provenance(
            _spec(), game_build_settings(10000), revisions, revisions, revisions
        )
        with assert_raises(contains="stale or changed"):
            require_bake_provenance(stored, next)


def _parsed(text: String) raises -> UserData:
    var document = parse_json(text)
    return user_data_of(document, document.root())


def _stored(record: UserData) raises -> UserData:
    var stored = UserData()
    stored.set_json(String(FIDELITY_KEY), record.to_json())
    return stored^


def test_fingerprints_are_fnv1a_of_normalized_json() raises:
    # Published FNV-1a 64 test vectors.
    assert_equal(json_fingerprint(""), "cbf29ce484222325")
    assert_equal(json_fingerprint("a"), "af63dc4c8601ec8c")
    assert_equal(json_fingerprint("foobar"), "85944171f73967e8")
    var settings = game_build_settings(10000)
    var record = _provenance(_spec())
    assert_equal(record.number("schema_version"), Float64(FIDELITY_SCHEMA))
    assert_equal(
        record.string("fingerprint_algorithm"), String(FINGERPRINT_ALGORITHM)
    )
    assert_equal(record.string("spec_fingerprint"), spec_fingerprint(_spec()))
    assert_equal(
        record.string("visual_settings_fingerprint"),
        settings_fingerprint(settings),
    )
    assert_equal(
        record.string("recipe_digest"), json_fingerprint(record.json("recipe"))
    )
    var recipe = _parsed(record.json("recipe"))
    assert_equal(
        recipe.json("canonical_to_local_rest"), CANONICAL_TO_LOCAL_REST
    )
    assert_equal(recipe.string("length_unit"), "meter")
    assert_equal(recipe.string("handedness"), "right")
    assert_equal(recipe.string("up_axis"), "+y")
    assert_equal(recipe.string("origin"), "pelvis-frame-origin")
    assert_equal(recipe.string("canonical_revision"), CANONICAL_RECIPE)
    assert_equal(recipe.string("visual_revision"), GAME_RECIPE)
    assert_equal(recipe.string("asset_revision"), "synthetic-no-source-assets")
    # Each spec input and each quality option changes its own fingerprint.
    var next = _spec()
    next.genome = next.genome.with_gene(FACE_SHAPE_1, Expression(1))
    assert_true(spec_fingerprint(next) != spec_fingerprint(_spec()))
    next = _spec()
    next.stature = Length(1.8287999, METER)
    assert_true(spec_fingerprint(next) != spec_fingerprint(_spec()))
    assert_true(
        settings_fingerprint(game_build_settings(10000, 12))
        != settings_fingerprint(settings)
    )
    assert_equal(stored_provenance(_stored(record)).to_json(), record.to_json())


def test_edited_or_foreign_records_are_refused() raises:
    var record = _provenance(_spec())
    var edited = record.copy()
    _ = edited.remove("schema_version")
    with assert_raises(contains="has no schema"):
        _ = stored_provenance(_stored(edited))
    edited = record.copy()
    edited.set_number("schema_version", 1)
    with assert_raises(contains="schema is unsupported"):
        _ = stored_provenance(_stored(edited))
    for key in [
        "recipe",
        "spec_fingerprint",
        "visual_settings_fingerprint",
        "recipe_digest",
    ]:
        edited = record.copy()
        _ = edited.remove(key)
        with assert_raises(contains="provenance is incomplete"):
            _ = stored_provenance(_stored(edited))
    for key in ["canonical_inputs", "visual_settings"]:
        var recipe = _parsed(record.json("recipe"))
        _ = recipe.remove(key)
        edited = record.copy()
        edited.set_json("recipe", recipe.to_json())
        with assert_raises(contains="recipe is incomplete"):
            _ = stored_provenance(_stored(edited))
    # A recipe edited without its fingerprints is refused.
    var recipe = _parsed(record.json("recipe"))
    var spec = _spec()
    spec.genome = spec.genome.with_gene(FACE_SHAPE_1, Expression(1))
    recipe.set_json("canonical_inputs", canonical_inputs(spec).to_json())
    edited = record.copy()
    edited.set_json("recipe", recipe.to_json())
    with assert_raises(contains="do not match its recipe"):
        _ = stored_provenance(_stored(edited))
    # Each fingerprint is checked, even when the digest is rewritten.
    edited.set_string("recipe_digest", json_fingerprint(edited.json("recipe")))
    with assert_raises(contains="do not match its recipe"):
        _ = stored_provenance(_stored(edited))
    recipe = _parsed(record.json("recipe"))
    recipe.set_json("visual_settings", game_build_settings(500).to_json())
    edited = record.copy()
    edited.set_json("recipe", recipe.to_json())
    edited.set_string("recipe_digest", json_fingerprint(edited.json("recipe")))
    with assert_raises(contains="do not match its recipe"):
        _ = stored_provenance(_stored(edited))
    var stored = UserData()
    stored.set_json(String(FIDELITY_KEY), "[1]")
    with assert_raises(contains="JSON object"):
        _ = stored_provenance(stored)
    with assert_raises(contains="no fidelity provenance"):
        require_current_spec(UserData(), _spec())


def test_a_stale_bake_does_not_represent_a_changed_spec() raises:
    var stored = _stored(_provenance(_spec()))
    require_current_spec(stored, _spec())
    # Visual settings and revisions do not change the represented spec.
    require_current_spec(_stored(_provenance(_spec(), 500)), _spec())
    var spec = _spec()
    spec.genome = spec.genome.with_gene(FACE_SHAPE_1, Expression(1))
    with assert_raises(contains="different spec"):
        require_current_spec(stored, spec)
    spec = _spec()
    spec.stature = Length(1.8287999, METER)
    with assert_raises(contains="different spec"):
        require_current_spec(stored, spec)
    spec = _spec()
    spec.athleticism = Athleticism(1)
    with assert_raises(contains="different spec"):
        require_current_spec(stored, spec)


def _rewritten_recipe(record: UserData, recipe: UserData) raises -> UserData:
    # Model an editor that updates all advertised hashes. Structural schema
    # checks must still reject missing fields and unsupported capabilities.
    var edited = record.copy()
    edited.set_json("recipe", recipe.to_json())
    edited.set_string("recipe_fingerprint", recipe.to_json())
    edited.set_string("recipe_digest", json_fingerprint(edited.json("recipe")))
    for pair in [
        ("canonical_inputs", "spec_fingerprint"),
        ("visual_settings", "visual_settings_fingerprint"),
    ]:
        if recipe.has(pair[0]):
            edited.set_string(pair[1], json_fingerprint(recipe.json(pair[0])))
    return edited^


def test_stored_provenance_requires_every_record_field() raises:
    var record = _provenance(_spec())
    for at in range(record.count()):
        var key = record.key(at)
        var edited = record.copy()
        _ = edited.remove(key)
        with assert_raises():
            _ = stored_provenance(_stored(edited))
        edited = record.copy()
        edited.set_null(key)
        with assert_raises():
            _ = stored_provenance(_stored(edited))
    for key in [
        "engineering_use",
        "canonical_geometry_embedded",
        "physical_properties_embedded",
        "source_manifest_verified",
    ]:
        var edited = record.copy()
        edited.set_boolean(key, True)
        with assert_raises(contains="stale or changed"):
            _ = stored_provenance(_stored(edited))
        with assert_raises(contains="stale or changed"):
            require_current_spec(_stored(edited), _spec())
    var edited = record.copy()
    edited.set_boolean("visual_use", False)
    with assert_raises(contains="stale or changed"):
        _ = stored_provenance(_stored(edited))
    for key in [
        "fingerprint_algorithm",
        "recipe_fingerprint",
        "identity_mapping",
        "expression_jaw_mapping",
        "dental_mapping",
        "skin_weight_mapping",
        "lod_mapping",
        "invalidation",
    ]:
        edited = record.copy()
        edited.set_string(key, "foreign claim")
        with assert_raises(contains="stale or changed"):
            _ = stored_provenance(_stored(edited))
    edited = record.copy()
    edited.set_boolean("unknown_capability", True)
    with assert_raises(contains="stale or changed"):
        _ = stored_provenance(_stored(edited))


def test_stored_provenance_requires_the_complete_recipe_schema() raises:
    var record = _provenance(_spec())
    var recipe = _parsed(record.json("recipe"))
    for at in range(recipe.count()):
        var key = recipe.key(at)
        var changed = recipe.copy()
        _ = changed.remove(key)
        with assert_raises(contains="recipe is incomplete"):
            _ = stored_provenance(_stored(_rewritten_recipe(record, changed)))
        changed = recipe.copy()
        changed.set_null(key)
        with assert_raises():
            _ = stored_provenance(_stored(_rewritten_recipe(record, changed)))
    var changed = recipe.copy()
    changed.set_number("schema_version", 1)
    with assert_raises(contains="stale or changed"):
        _ = stored_provenance(_stored(_rewritten_recipe(record, changed)))
    changed = recipe.copy()
    changed.set_json(
        "canonical_to_local_rest", "[2,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]"
    )
    with assert_raises(contains="stale or changed"):
        _ = stored_provenance(_stored(_rewritten_recipe(record, changed)))
    changed = recipe.copy()
    changed.set_string("length_unit", "centimeter")
    with assert_raises(contains="stale or changed"):
        _ = stored_provenance(_stored(_rewritten_recipe(record, changed)))
    # Valid producer revisions remain caller assertions. No authentication
    # claim is made when an editor rewrites a valid recipe and its hashes.
    var foreign = humanoid_provenance(
        _spec(), UserData(), "custom canonical", "custom visual", "unknown"
    )
    assert_equal(
        stored_provenance(_stored(foreign)).to_json(), foreign.to_json()
    )


def test_stored_provenance_checks_every_canonical_input() raises:
    var record = _provenance(_spec())
    var recipe = _parsed(record.json("recipe"))
    var inputs = _parsed(recipe.json("canonical_inputs"))
    for at in range(inputs.count()):
        var changed = inputs.copy()
        _ = changed.remove(inputs.key(at))
        var changed_recipe = recipe.copy()
        changed_recipe.set_json("canonical_inputs", changed.to_json())
        with assert_raises():
            _ = stored_provenance(
                _stored(_rewritten_recipe(record, changed_recipe))
            )
    for key in ["genes", "gene_float32_bits"]:
        var genes = _parsed(inputs.json(key))
        _ = genes.remove("42")
        var changed = inputs.copy()
        changed.set_json(key, genes.to_json())
        var changed_recipe = recipe.copy()
        changed_recipe.set_json("canonical_inputs", changed.to_json())
        with assert_raises():
            _ = stored_provenance(
                _stored(_rewritten_recipe(record, changed_recipe))
            )
    for key in ["stature_m", "sex", "athleticism", "schema_version"]:
        var changed = inputs.copy()
        changed.set_number(key, changed.number(key) + 0.5)
        var changed_recipe = recipe.copy()
        changed_recipe.set_json("canonical_inputs", changed.to_json())
        with assert_raises(contains="canonical inputs are stale or changed"):
            _ = stored_provenance(
                _stored(_rewritten_recipe(record, changed_recipe))
            )
    var next = _spec()
    next.sex = Sex(1)
    next.athleticism = Athleticism(1)
    next.stature = Length(1.8287999, METER)
    next.genome = next.genome.with_gene(FACE_SHAPE_1, Expression(-0.5))
    next.genome.expressions[0] = bitcast[DType.float32](UInt32(0x80000000))
    var valid = _provenance(next)
    assert_equal(stored_provenance(_stored(valid)).to_json(), valid.to_json())
    require_current_spec(_stored(valid), next)
    for text in ["-1", "4294967296", "00", "18446744073709551616", ""]:
        var bits = _parsed(inputs.json("gene_float32_bits"))
        bits.set_string("0", text)
        var changed = inputs.copy()
        changed.set_json("gene_float32_bits", bits.to_json())
        var changed_recipe = recipe.copy()
        changed_recipe.set_json("canonical_inputs", changed.to_json())
        with assert_raises():
            _ = stored_provenance(
                _stored(_rewritten_recipe(record, changed_recipe))
            )


def test_gltf_retains_node_and_scene_contracts() raises:
    var assets = Assets()
    var scene = Scene()
    var record = _provenance(_spec())
    var root = Object3D()
    root.user_data.set_json(String(FIDELITY_KEY), record.to_json())
    _ = scene.add(root^)
    var options = GltfExportOptions()
    options.scene_user_data.set_json(String(FIDELITY_KEY), record.to_json())
    var files = export_gltf(scene, assets, GLTF_EMBEDDED, options=options^)
    var loaded_scene = Scene()
    var loaded_assets = Assets()
    var model = load_gltf(
        String(unsafe_from_utf8=files.document),
        List[UInt8](),
        "",
        loaded_scene,
        loaded_assets,
    )
    require_bake_provenance(model.scene_extras, record)
    require_bake_provenance(loaded_scene.get(model.nodes[0]).user_data, record)
    require_current_spec(model.scene_extras, _spec())
    var spec = _spec()
    spec.genome = spec.genome.with_gene(FACE_SHAPE_1, Expression(-1))
    with assert_raises(contains="different spec"):
        require_current_spec(model.scene_extras, spec)
    with assert_raises(contains="spec fingerprint is stale"):
        require_bake_provenance(model.scene_extras, _provenance(spec))


def test_real_game_humanoid_glb_retains_recipe_and_visual_positions() raises:
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    var person = add_game_humanoid(
        scene, assets, parent, _spec(), 3000, 12, 8, 8, workers=1
    )
    var expected = humanoid_provenance(
        _spec(),
        game_build_settings(3000, 12, 8, 8),
        String(CANONICAL_RECIPE),
        String(GAME_RECIPE),
        "unverified-converted-ICTF-THRS",
    )
    require_bake_provenance(scene.get(person.root).user_data, expected)
    var options = GltfExportOptions()
    options.scene_user_data.set_json(String(FIDELITY_KEY), expected.to_json())
    var path = temporary_path("real-humanoid.glb")
    write_gltf(path, scene, assets, GLB, options=options^)
    var loaded_scene = Scene()
    var loaded_assets = Assets()
    var model = read_gltf(path, loaded_scene, loaded_assets)
    require_bake_provenance(model.scene_extras, expected)
    var contracts = 0
    for node in model.nodes:
        if node != NO_PARENT:
            var data = loaded_scene.get(node).user_data.copy()
            if data.has(String(FIDELITY_KEY)):
                require_bake_provenance(data, expected)
                contracts += 1
    assert_equal(contracts, 1)
    assert_equal(len(loaded_scene.skinned_meshes), len(person.skins))
    for index in range(len(person.skins)):
        ref before = assets.geometries.get(
            scene.skinned_meshes[person.skins[index]].geometry
        )
        ref after = loaded_assets.geometries.get(
            loaded_scene.skinned_meshes[index].geometry
        )
        assert_equal(before.triangle_count(), after.triangle_count())
        ref original = before.attribute_view(String(POSITION))
        ref restored = after.attribute_view(String(POSITION))
        assert_equal(original.count(), restored.count())
        for vertex in range(original.count()):
            for component in range(3):
                assert_equal(
                    original.component(vertex, component),
                    restored.component(vertex, component),
                )
    # A real bake remains visual-only after its successful byte round trip.
    assert_false(expected.boolean("engineering_use"))


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
