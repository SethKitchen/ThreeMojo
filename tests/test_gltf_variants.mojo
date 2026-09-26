# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `KHR_materials_variants` in `loaders.gltf`.

`assets/gltf_variants/variants.gltf` has four variants, two of them named
alike, and three meshes: two primitives that the variants map, one with
vertex colors, points that they map, and a mesh they do not map.
`variants.json` has what three.js 0.180's `GLTFLoader` draws each object
with, for each variant, with the `KHR_materials_variants` plugin of
takahirox/three-gltf-extensions registered. `three_variants.mjs` wrote
both.
"""

from core.assets import Assets
from core.scene import Scene
from loaders.gltf import (
    GLTF_INSTANCED_MESH,
    GLTF_LINE,
    GLTF_MESH,
    GLTF_POINTS,
    GLTF_SKINNED_MESH,
    GltfModel,
    GltfObjectKind,
    GltfVariantObject,
    is_supported_extension,
    load_gltf,
    select_variant,
)
from loaders.json import JsonDocument, parse_json
from math.matrix4 import Matrix4
from materials.material import BASIC, STANDARD, MaterialId
from objects.instanced_mesh import InstancedMesh
from objects.line import Line
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import SkinnedMesh
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

comptime HEX = "0123456789abcdef"


def _hex(value: UInt8) -> String:
    var v = Int(value)
    return String(HEX[byte = v >> 4 : (v >> 4) + 1]) + String(
        HEX[byte = v & 15 : (v & 15) + 1]
    )


def _file() raises -> String:
    return Path("assets/gltf_variants/variants.gltf").read_text()


def _load(
    text: String, mut scene: Scene, mut assets: Assets
) raises -> GltfModel:
    return load_gltf(text, List[UInt8](), "", scene, assets)


def _check(
    scene: Scene, assets: Assets, doc: JsonDocument, looks: Int, what: String
) raises:
    """Check the four drawn objects against three.js's, in its traversal
    order: two meshes, the points, and the last mesh."""
    var drawn: List[MaterialId] = [
        scene.meshes[0].material,
        scene.meshes[1].material,
        scene.points[0].material,
        scene.meshes[2].material,
    ]
    assert_equal(doc.length(looks), 4, what)
    for slot in range(4):
        var want = doc.at(looks, slot)
        var material = assets.materials.get(drawn[slot])
        var kind = doc.string(doc.get(want, "material"))
        if kind == "PointsMaterial":
            assert_true(material.kind == BASIC, what)
        else:
            assert_equal(kind, "MeshStandardMaterial", what)
            assert_true(material.kind == STANDARD, what)
        var color = (
            _hex(material.color.r)
            + _hex(material.color.g)
            + _hex(material.color.b)
        )
        assert_equal(color, doc.string(doc.get(want, "color")), what)
        assert_equal(
            material.vertex_colors,
            doc.boolean(doc.get(want, "vertexColors")),
            what,
        )


def test_each_variant_draws_as_three_js_draws_it() raises:
    var doc = parse_json(Path("assets/gltf_variants/variants.json").read_text())
    var scene = Scene()
    var assets = Assets()
    var model = _load(_file(), scene, assets)
    var names = doc.get(doc.root(), "variants")
    assert_equal(len(model.variants), doc.length(names))
    for slot in range(len(model.variants)):
        assert_equal(model.variants[slot], doc.string(doc.at(names, slot)))
    # Three mapped objects; the last mesh has no mappings.
    assert_equal(len(model.variant_objects), 3)
    _check(scene, assets, doc, doc.get(doc.root(), "original"), "original")
    var selected = doc.get(doc.root(), "selected")
    for slot in range(doc.length(selected)):
        var name = doc.key(selected, slot)
        select_variant(model, scene, name)
        _check(scene, assets, doc, doc.get(selected, name), name)
    select_variant(model, scene)
    _check(scene, assets, doc, doc.get(doc.root(), "restored"), "restored")
    assert_true(is_supported_extension("KHR_materials_variants"))


def test_the_other_lists_take_a_variant_too() raises:
    # A line, a skinned mesh and an instanced mesh are drawn from the
    # same lists `select_variant` writes; here each is put in place by
    # hand, as the loader records them.
    var scene = Scene()
    var assets = Assets()
    var model = _load(_file(), scene, assets)
    var red = model.variant_objects[0].materials[0]
    var kept = scene.meshes[2].material
    model.variant_objects.append(
        GltfVariantObject(GLTF_MESH, 2, kept, [red, kept, kept, kept])
    )
    select_variant(model, scene, String("red"))
    assert_equal(scene.meshes[2].material.value, red.value)
    select_variant(model, scene, String("no such variant"))
    assert_equal(scene.meshes[2].material.value, kept.value)
    var geometry = scene.meshes[0].geometry
    var node = scene.meshes[0].node
    scene.add_line(Line(geometry, kept, node))
    scene.add_instanced_mesh(InstancedMesh(geometry, kept, node, 1))
    scene.add_skinned_mesh(
        SkinnedMesh(geometry, kept, node, Skeleton([Bone(node, Matrix4())]))
    )
    var kinds: List[GltfObjectKind] = [
        GLTF_LINE,
        GLTF_INSTANCED_MESH,
        GLTF_SKINNED_MESH,
    ]
    for kind in kinds:
        model.variant_objects.append(
            GltfVariantObject(kind, 0, kept, [red, kept, kept, kept])
        )
    select_variant(model, scene, String("red"))
    assert_equal(scene.lines[0].material.value, red.value)
    assert_equal(scene.instanced_meshes[0].material.value, red.value)
    assert_equal(scene.skinned_meshes[0].material.value, red.value)
    for kind in kinds:
        model.variant_objects.append(
            GltfVariantObject(kind, 5, kept, [red, kept, kept, kept])
        )
        with assert_raises(contains="no longer has an object"):
            select_variant(model, scene, String("red"))
        _ = model.variant_objects.pop()
    model.variant_objects.append(
        GltfVariantObject(GLTF_POINTS, 5, kept, [red, kept, kept, kept])
    )
    with assert_raises(contains="no longer has an object"):
        select_variant(model, scene, String("red"))
    _ = model.variant_objects.pop()
    model.variant_objects.append(
        GltfVariantObject(GLTF_MESH, -1, kept, [red, kept, kept, kept])
    )
    with assert_raises(contains="no longer has an object"):
        select_variant(model, scene)
    _ = model.variant_objects.pop()
    # A model with no variants changes nothing.
    select_variant(GltfModel(), scene, String("red"))
    model.variant_objects.append(
        GltfVariantObject(GltfObjectKind(9), 0, kept, [red, kept, kept, kept])
    )
    with assert_raises(contains="object kind that is not known"):
        select_variant(model, scene)


def test_a_malformed_variant_is_refused() raises:
    var original = _file()
    var cases: List[Tuple[String, String, String]] = [
        (
            '{"name":"blue"}',
            '{"label":"blue"}',
            "a material variant needs a name",
        ),
        ('"variants":[2]}]', '"variants":[7]}]', "variant that is not there"),
        ('"variants":[2]}]', '"variants":[-1]}]', "variant that is not there"),
        ('{"material":3,"variants":[2]}', '{"variants":[2]}', "is required"),
    ]
    for entry in cases:
        var text = original.replace(entry[0], entry[1])
        assert_true(text != original, entry[0])
        var scene = Scene()
        var assets = Assets()
        with assert_raises(contains=entry[2]):
            _ = _load(text, scene, assets)


def test_mappings_without_the_root_extension_are_ignored() raises:
    # The plugin reads no mapping when the root does not have the
    # extension, and a root without `variants` has none.
    var original = _file()
    var start = original.find(
        '"extensions":{"KHR_materials_variants":{"variants"'
    )
    var end = original.find("]}},", start)
    var text = String(original[byte=0:start]) + String(
        original[byte = end + 4 :]
    )
    var scene = Scene()
    var assets = Assets()
    var model = _load(text, scene, assets)
    assert_equal(len(model.variants), 0)
    assert_equal(len(model.variant_objects), 0)
    var bare = original.replace(
        '{"variants":[{"name":"red"},{"name":"red"},{"name":"blue"},{"name":"red.1"}]}',
        "{}",
    )
    assert_true(bare != original)
    with assert_raises(contains="variant that is not there"):
        _ = _load(bare, scene, assets)
    var empty = original.replace(
        '{"variants":[{"name":"red"},{"name":"red"},{"name":"blue"},{"name":"red.1"}]}',
        '{"variants":[]}',
    )
    with assert_raises(contains="variant that is not there"):
        _ = _load(empty, scene, assets)
    # A primitive with no mappings, and a mapping with no variants, change
    # nothing.
    var unmapped = original.replace(
        '"mappings":[{"material":3,"variants":[2]}]', '"mappings":[]'
    ).replace('{"material":2,"variants":[2]}', '{"material":2,"variants":[]}')
    assert_true(unmapped != original)
    var fresh = Scene()
    var mapped = _load(unmapped, fresh, assets)
    assert_equal(len(mapped.variant_objects), 3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
