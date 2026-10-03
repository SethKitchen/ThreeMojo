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
    ENGINEERING_USE,
    FIDELITY_KEY,
    GAME_RECIPE,
    VISUAL_USE,
    HumanoidUse,
    canonical_inputs,
    humanoid_provenance,
    require_bake_provenance,
    require_humanoid_use,
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
from loaders.gltf import load_gltf, read_gltf
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
    with assert_raises(contains="stale or changed"):
        require_bake_provenance(stored, _provenance(_spec(), 500))
    var spec = _spec()
    spec.genome = spec.genome.with_gene(FACE_SHAPE_1, Expression(1))
    with assert_raises(contains="stale or changed"):
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
