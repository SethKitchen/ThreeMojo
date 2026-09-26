# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.lwo` and `loaders.lwo_iff`.

`assets/lwo/lwo.json` holds what three.js 0.180's `LWOLoader.parse` makes
of each file beside it, written by `three_lwo.mjs`: the materials, and
each mesh with its geometry. `make_lwo.py` wrote the files: an LWO2 scene
of three layers and three surfaces, and LWO3 standard, Phong and physical
surfaces of node attributes, image nodes and image maps.
"""

from core.assets import Assets
from core.scene import Scene
from loaders.json import BOOLEAN, JsonDocument, NULL, NUMBER, STRING, parse_json
from loaders.lwo import (
    LwoMap,
    LwoMaterial,
    LwoMesh,
    LwoModel,
    load_lwo,
    lwo_model_name,
    read_lwo,
    lwo_resource_path,
    parse_lwo,
)
from materials.material import ADD_OPERATION
from render.texture import CLAMP, MIRROR, REPEAT, Wrap
from std.math import isnan
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime FILES: List[String] = [
    "scene",
    "standard",
    "phong",
    "physical",
    "kitchen",
    "kitchen3",
]


def _reference() raises -> JsonDocument:
    return parse_json(Path("assets/lwo/lwo.json").read_text())


def _near(got: Float64, doc: JsonDocument, node: Int, what: String) raises:
    """Check a number, or NaN written as a string."""
    if doc.kind(node) == STRING:
        assert_equal(doc.string(node), "NaN", what)
        assert_true(isnan(got), what)
        return
    assert_almost_equal(got, doc.number(node), atol=1e-7, msg=what)


def _floats(
    got: List[Float32], doc: JsonDocument, node: Int, what: String
) raises:
    var array = doc.get(node, "array")
    assert_equal(len(got), doc.length(array), what)
    for k in range(len(got)):
        _near(Float64(got[k]), doc, doc.at(array, k), what + " " + String(k))


def _wrap(wrap: Wrap) -> Int:
    """three.js's wrapping constant."""
    if wrap == REPEAT:
        return 1000
    if wrap == MIRROR:
        return 1002
    return 1001


def _map(
    got: Optional[LwoMap], doc: JsonDocument, want: Int, key: String, env: Bool
) raises:
    if not doc.has(want, key):
        assert_false(Bool(got), key)
        return
    assert_true(Bool(got), key)
    ref map = got.value()
    var m = doc.get(want, key)
    assert_equal(map.file, doc.string(doc.get(m, "name")), key)
    assert_equal(_wrap(map.wrap_s), doc.integer(doc.get(m, "wrapS")), key)
    assert_equal(_wrap(map.wrap_t), doc.integer(doc.get(m, "wrapT")), key)
    var space = "srgb" if map.srgb else ""
    assert_equal(space, doc.string(doc.get(m, "colorSpace")), key)
    _ = env


def _color(
    got: SIMD[DType.float64, 4], doc: JsonDocument, want: Int, key: String
) raises:
    if not doc.has(want, key):
        return
    var c = doc.get(want, key)
    for k in range(3):
        assert_almost_equal(
            got[k], doc.number(doc.at(c, k)), atol=1e-12, msg=key
        )


def _number(got: Float64, doc: JsonDocument, want: Int, key: String) raises:
    if doc.has(want, key):
        assert_almost_equal(
            got, doc.number(doc.get(want, key)), atol=1e-12, msg=key
        )


def _material(m: LwoMaterial, doc: JsonDocument, want: Int) raises:
    var name = m.name
    assert_equal(m.type, doc.string(doc.get(want, "type")), name)
    assert_equal(m.name, doc.string(doc.get(want, "name")), name)
    assert_equal(m.side.value, doc.integer(doc.get(want, "side")), name)
    assert_equal(
        m.flat_shading, doc.boolean(doc.get(want, "flatShading")), name
    )
    assert_equal(m.transparent, doc.boolean(doc.get(want, "transparent")), name)
    _number(m.opacity, doc, want, "opacity")
    _number(m.emissive_intensity, doc, want, "emissiveIntensity")
    _number(m.shininess, doc, want, "shininess")
    _number(m.reflectivity, doc, want, "reflectivity")
    _number(m.refraction_ratio, doc, want, "refractionRatio")
    _number(m.roughness, doc, want, "roughness")
    _number(m.metalness, doc, want, "metalness")
    _number(m.clearcoat, doc, want, "clearcoat")
    _number(m.clearcoat_roughness, doc, want, "clearcoatRoughness")
    _number(m.bump_scale, doc, want, "bumpScale")
    _number(m.size, doc, want, "size")
    if doc.has(want, "combine"):
        assert_equal(m.combine.value, doc.integer(doc.get(want, "combine")))
    _color(m.color, doc, want, "color")
    _color(m.emissive, doc, want, "emissive")
    _color(m.specular, doc, want, "specular")
    if doc.has(want, "normalScale"):
        var s = doc.get(want, "normalScale")
        assert_almost_equal(
            Float64(m.normal_scale.x), doc.number(doc.at(s, 0)), atol=1e-7
        )
        assert_almost_equal(
            Float64(m.normal_scale.y), doc.number(doc.at(s, 1)), atol=1e-7
        )
    _map(m.map, doc, want, "map", False)
    _map(m.ao_map, doc, want, "aoMap", False)
    _map(m.roughness_map, doc, want, "roughnessMap", False)
    _map(m.specular_map, doc, want, "specularMap", False)
    _map(m.emissive_map, doc, want, "emissiveMap", False)
    _map(m.metalness_map, doc, want, "metalnessMap", False)
    _map(m.alpha_map, doc, want, "alphaMap", False)
    _map(m.normal_map, doc, want, "normalMap", False)
    _map(m.bump_map, doc, want, "bumpMap", False)
    _map(m.env_map, doc, want, "envMap", True)
    if doc.has(want, "envMap"):
        var mapping = doc.integer(doc.get(doc.get(want, "envMap"), "mapping"))
        assert_equal(
            304 if m.env_refraction else 303, mapping, "envMap mapping"
        )


def _mesh(model: LwoModel, index: Int, doc: JsonDocument, want: Int) raises:
    ref mesh = model.meshes[index]
    var name = mesh.name
    assert_equal(mesh.type, doc.string(doc.get(want, "type")), name)
    assert_equal(mesh.name, doc.string(doc.get(want, "name")), name)
    var position = doc.get(want, "position")
    var pivot = doc.get(want, "pivot")
    for k in range(3):
        assert_almost_equal(
            mesh.position[k],
            doc.number(doc.at(position, k)),
            atol=1e-7,
            msg=name,
        )
        assert_almost_equal(
            mesh.pivot[k], doc.number(doc.at(pivot, k)), atol=1e-7, msg=name
        )
    # The materials, by name and class.
    var material = doc.get(want, "material")
    if mesh.single:
        ref m = model.materials[mesh.materials[0]]
        assert_equal(m.name + "|" + m.type, doc.string(material), name)
    else:
        assert_equal(len(mesh.materials), doc.length(material), name)
        for k in range(len(mesh.materials)):
            var entry = doc.at(material, k)
            if mesh.materials[k] < 0:
                assert_true(doc.kind(entry) == NULL, name)
            else:
                ref m = model.materials[mesh.materials[k]]
                assert_equal(m.name + "|" + m.type, doc.string(entry), name)
    _floats(
        mesh.positions,
        doc,
        doc.get(want, "position_attribute"),
        name + " position",
    )
    _floats(mesh.normals, doc, doc.get(want, "normal"), name + " normal")
    _floats(mesh.uvs, doc, doc.get(want, "uv"), name + " uv")
    var index_node = doc.get(want, "index")
    assert_equal(len(mesh.index), doc.length(index_node), name)
    for k in range(len(mesh.index)):
        assert_equal(mesh.index[k], doc.integer(doc.at(index_node, k)), name)
    var groups = doc.get(want, "groups")
    assert_equal(len(mesh.groups), doc.length(groups), name)
    for k in range(len(mesh.groups)):
        var g = doc.at(groups, k)
        assert_equal(mesh.groups[k].start, doc.integer(doc.at(g, 0)), name)
        assert_equal(mesh.groups[k].count, doc.integer(doc.at(g, 1)), name)
        assert_equal(
            mesh.groups[k].material_index, doc.integer(doc.at(g, 2)), name
        )
    var morphs = doc.get(want, "morphs")
    assert_equal(len(mesh.morphs), doc.length(morphs), name)
    for k in range(len(mesh.morphs)):
        var m = doc.at(morphs, k)
        assert_equal(mesh.morph_names[k], doc.string(doc.get(m, "name")), name)
        _floats(mesh.morphs[k], doc, m, name + " morph")
    var names = doc.get(want, "matNames")
    assert_equal(len(mesh.material_names), doc.length(names), name)
    for k in range(len(mesh.material_names)):
        assert_equal(mesh.material_names[k], doc.string(doc.at(names, k)), name)
    # The children, in the order of the layers.
    var children = doc.get(want, "children")
    var found = 0
    for k in range(len(model.meshes)):
        if model.meshes[k].parent == index:
            _mesh(model, k, doc, doc.at(children, found))
            found += 1
    assert_equal(found, doc.length(children), name)


def test_each_file_is_read_as_three_js_reads_it() raises:
    var doc = _reference()
    for file in materialize[FILES]():
        var bytes = Path("assets/lwo/" + file + ".lwo").read_bytes()
        var model = parse_lwo(bytes, file, "models/")
        var want = doc.get(doc.root(), file)
        var materials = doc.get(want, "materials")
        assert_equal(model.surfaces, doc.length(materials), file)
        for k in range(model.surfaces):
            _material(model.materials[k], doc, doc.at(materials, k))
        var meshes = doc.get(want, "meshes")
        assert_equal(len(model.roots), doc.length(meshes), file)
        for k in range(len(model.roots)):
            _mesh(model, model.roots[k], doc, doc.at(meshes, k))


def test_a_file_three_js_cannot_read_is_refused() raises:
    # Every file in `broken/`: three.js throws on most, and reads the rest
    # in a way the port does not follow; see the module docstrings.
    var doc = _reference()
    var root = doc.root()
    var count = 0
    for k in range(doc.length(root)):
        var name = doc.key(root, k)
        if not name.startswith("broken/"):
            continue
        count += 1
        var bytes = Path("assets/lwo/" + name + ".lwo").read_bytes()
        with assert_raises():
            _ = parse_lwo(bytes, "broken")
    assert_equal(count, 32)


def test_each_kind_goes_into_a_scene_with_its_maps() raises:
    var scene = Scene()
    var assets = Assets()
    for file in materialize[FILES]():
        var bytes = Path("assets/lwo/" + file + ".lwo").read_bytes()
        _ = load_lwo(bytes, scene, assets, file, "assets/lwo/")
    # `images/color.png` is there, and decoded; the other maps' files are
    # not.
    assert_equal(len(assets.textures.textures), 1)
    var read = read_lwo("assets/lwo/scene.lwo", scene, assets)
    assert_equal(len(read.nodes), 3)


def test_a_file_goes_into_a_scene() raises:
    var scene = Scene()
    var assets = Assets()
    var bytes = Path("assets/lwo/scene.lwo").read_bytes()
    var model = load_lwo(bytes, scene, assets, "scene")
    assert_equal(len(model.nodes), 3)
    assert_equal(len(scene.meshes), 1)
    assert_equal(len(scene.lines), 1)
    assert_equal(len(scene.points), 1)
    assert_equal(scene.get(model.nodes[1]).parent, model.nodes[0])
    assert_equal(scene.get(model.nodes[0]).name, "Base")
    # Lines and points are drawn from positions in order: read through
    # their index, with no index left.
    ref lines = assets.geometries.get(scene.lines[0].geometry)
    assert_false(lines.is_indexed())
    assert_equal(lines.attribute_view("position").count(), 4)


def test_a_path_names_the_model_as_three_js_does() raises:
    assert_equal(
        lwo_resource_path("models/lwo/Objects/Demo.lwo"), "models/lwo/"
    )
    assert_equal(lwo_model_name("models/lwo/Objects/Demo.lwo"), "Objects/Demo")
    assert_equal(lwo_resource_path("box.lwo"), "./")
    assert_equal(lwo_model_name("box.lwo"), "box")
    # three.js splits a path that starts with `Objects` into characters.
    assert_equal(lwo_resource_path("Objects/a.lwo"), "")
    assert_equal(lwo_model_name("Objects/a.lwo"), "o")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
