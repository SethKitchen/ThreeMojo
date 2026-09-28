# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.usd`: the fixtures of `assets/usd/` read as three.js
r186's `USDLoader`, `USDAParser` and `USDCParser` read them, from
`assets/usd/three_usd.mjs`, and a scene written by `exporters.usdz` read
back."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, UV, UV1, BufferGeometry
from core.object3d import GROUP_TYPE, NO_PARENT, OBJECT3D_TYPE, Object3D
from core.scene import Scene
from exporters.usdz import export_usdz
from geometries.box import box
from loaders.json import (
    ARRAY,
    BOOLEAN,
    NULL,
    NUMBER,
    OBJECT,
    STRING,
    JsonDocument,
    parse_json,
)
from loaders.model_nodes import texture_from_file
from loaders.usd import (
    decode_text,
    lowercase_extension,
    parse_usd,
    parse_usda,
    read_usd,
    read_usdz,
    url_base,
)
from loaders.usd_composer import UsdModel, UsdTexture
from loaders.usd_specs import (
    USD_ARRAY,
    USD_BOOLEAN,
    USD_NULL,
    USD_NUMBER,
    USD_NUMBERS,
    USD_OBJECT,
    USD_SAMPLES,
    USD_STRING,
    USD_STRINGS,
    USD_UNDEFINED,
    UsdLayer,
)
from loaders.usda_parser import parse_usda_layer
from loaders.usdc_parser import parse_usdc
from loaders.zip import ZIP_STORED, ZipEntry, zip_archive
from materials.material import PHYSICAL, STANDARD, Material, MaterialId
from math.quaternion import Quaternion
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB, srgb_to_linear
from render.texture import CLAMP, COVERAGE, IGNORED, MIRROR, REPEAT, Wrap
from render.texture_store import NO_TEXTURE, TextureId
from std.math import isinf, isnan
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, Angle, Length

comptime _DIR = "assets/usd/"


def _reference() raises -> JsonDocument:
    """Return three.js's reading of the fixtures."""
    return parse_json(Path(_DIR + "usd.json").read_text())


def _same_number(got: Float64, doc: JsonDocument, node: Int, what: String) raises:
    """Assert a number is three.js's, a non-finite one as its text.

    Args:
        got: The number.
        doc: The reference.
        node: Its value.
        what: The name, for a failure.
    """
    if doc.kind(node) == STRING:
        var text = doc.string(node)
        if text == "NaN":
            assert_true(isnan(got), what + " is NaN")
        else:
            assert_true(isinf(got), what + " is infinite")
            assert_equal(got > 0, text == "Infinity", what)
        return
    var want = doc.number(node)
    assert_almost_equal(got, want, atol=1e-9 + abs(want) * 1e-12, msg=what)


def _same_value(
    layer: UsdLayer, id: Int, doc: JsonDocument, node: Int, what: String
) raises:
    """Assert a layer value is three.js's.

    Args:
        layer: The layer.
        id: The value.
        doc: The reference.
        node: Its value.
        what: The name, for a failure.
    """
    var kind = doc.kind(node)
    var got = layer.kind(id)
    if kind == STRING:
        var text = doc.string(node)
        if text == "__undefined__":
            assert_true(got == USD_UNDEFINED, what + " is undefined")
        elif got == USD_NUMBER:
            _same_number(layer.number(id), doc, node, what)
        else:
            assert_true(got == USD_STRING, what + " is a string")
            assert_equal(layer.text(id), text, what)
    elif kind == NUMBER:
        assert_true(got == USD_NUMBER, what + " is a number")
        _same_number(layer.number(id), doc, node, what)
    elif kind == BOOLEAN:
        assert_true(got == USD_BOOLEAN, what + " is a boolean")
        assert_equal(layer.number(id) != 0, doc.boolean(node), what)
    elif kind == NULL:
        assert_true(got == USD_NULL, what + " is null")
    elif kind == ARRAY:
        assert_true(layer.is_array(id), what + " is an array")
        assert_equal(layer.length(id), doc.length(node), what + " length")
        for k in range(doc.length(node)):
            var item = doc.at(node, k)
            var name = what + "[" + String(k) + "]"
            if got == USD_NUMBERS:
                _same_number(layer.values[id].numbers[k], doc, item, name)
            elif got == USD_STRINGS:
                assert_equal(layer.values[id].strings[k], doc.string(item), name)
            else:
                _same_value(layer, layer.values[id].items[k], doc, item, name)
    else:
        var samples = doc.length(node) == 2 and doc.has(node, "times")
        if samples:
            assert_true(got == USD_SAMPLES, what + " is samples")
            var times = doc.get(node, "times")
            var values = doc.get(node, "values")
            assert_equal(len(layer.values[id].numbers), doc.length(times))
            for k in range(doc.length(times)):
                _same_number(
                    layer.values[id].numbers[k], doc, doc.at(times, k), what
                )
                _same_value(
                    layer,
                    layer.values[id].items[k],
                    doc,
                    doc.at(values, k),
                    what + " sample",
                )
            return
        assert_true(got == USD_OBJECT, what + " is an object")
        assert_equal(len(layer.values[id].strings), doc.length(node), what)
        for k in range(doc.length(node)):
            var key = doc.key(node, k)
            _same_value(
                layer,
                layer.object_value(id, key),
                doc,
                doc.get(node, key),
                what + "." + key,
            )


def _same_layer(layer: UsdLayer, doc: JsonDocument, name: String) raises:
    """Assert a layer holds three.js's paths, spec types and fields.

    Args:
        layer: The layer.
        doc: The reference.
        name: The fixture.
    """
    var specs = doc.get(doc.get(doc.root(), "layers"), name)
    assert_equal(len(layer.paths), doc.length(specs), name + " paths")
    for k in range(doc.length(specs)):
        var entry = doc.at(specs, k)
        var path = doc.string(doc.get(entry, "path"))
        assert_equal(layer.paths[k], path, name)
        assert_equal(
            layer.specs[k].spec_type.value,
            doc.integer(doc.get(entry, "specType")),
            path,
        )
        var fields = doc.get(entry, "fields")
        assert_equal(len(layer.specs[k].names), doc.length(fields), path)
        for f in range(doc.length(fields)):
            var key = doc.key(fields, f)
            assert_equal(layer.specs[k].names[f], key, path)
            _same_value(
                layer,
                layer.specs[k].values[f],
                doc,
                doc.get(fields, key),
                path + "." + key,
            )


def test_usda_layers_match_three_js() raises:
    var doc = _reference()
    for name in [  # pragma: no branch
        "scene.usda",
        "values.usda",
        "variants.usda",
        "stage.usda",
        "geo.usda",
    ]:
        _same_layer(parse_usda_layer(Path(_DIR + name).read_text()), doc, name)


def test_usdc_layers_match_three_js() raises:
    var doc = _reference()
    for name in [  # pragma: no branch
        "scene.usdc",
        "values.usdc",
        "values_0_3.usdc",
        "values_0_6.usdc",
        "variants.usdc",
        "geo.usdc",
    ]:
        _same_layer(parse_usdc(Path(_DIR + name).read_bytes()), doc, name)


def _near_list(
    got: List[Float32], doc: JsonDocument, node: Int, what: String
) raises:
    """Assert numbers are three.js's, rounded to a millionth.

    Args:
        got: The numbers.
        doc: The reference: a list, or the length alone.
        node: Its value.
        what: The name, for a failure.
    """
    if doc.kind(node) == NUMBER:
        assert_equal(len(got), doc.integer(node), what + " length")
        return
    assert_equal(len(got), doc.length(node), what + " length")
    for k in range(len(got)):
        var want = doc.at(node, k)
        if doc.kind(want) == STRING:
            assert_true(isnan(got[k]), what + " is NaN")
        else:
            assert_almost_equal(
                Float64(got[k]), doc.number(want), atol=2e-5, msg=what
            )


def _near_color(got: Color, doc: JsonDocument, node: Int, what: String) raises:
    """Assert an sRGB color holds three.js's linear channels, to a byte.

    Args:
        got: The color.
        doc: The reference.
        node: Its three channels.
        what: The name, for a failure.
    """
    var channels = [got.r, got.g, got.b]
    for k in range(3):  # pragma: no branch
        assert_almost_equal(
            Float64(srgb_to_linear(Float32(channels[k]) / 255)),
            doc.number(doc.at(node, k)),
            atol=0.005,
            msg=what,
        )


def _texture_of(model: UsdModel, id: TextureId) raises -> UsdTexture:
    """Return what the model keeps of a texture.

    Args:
        model: What was added.
        id: The texture.

    Returns:
        Its entry.
    """
    for texture in model.textures:  # pragma: no branch
        if texture.id == id:
            return texture.copy()
    raise Error("no such texture")


def _same_map(
    assets: Assets,
    model: UsdModel,
    id: TextureId,
    doc: JsonDocument,
    node: Int,
    what: String,
) raises:
    """Assert a map is three.js's.

    Args:
        assets: The assets.
        model: What was added.
        id: The map.
        doc: The reference.
        node: Its entry, or `null`.
        what: The name, for a failure.
    """
    if doc.kind(node) == NULL:
        assert_true(id == NO_TEXTURE, what + " is none")
        return
    assert_true(id != NO_TEXTURE, what + " is there")
    var entry = _texture_of(model, id)
    ref texture = assets.textures.get(id)
    var url = doc.get(node, "url")
    if doc.kind(url) == NULL:
        assert_false(entry.loaded, what + " is not loaded")
    elif doc.string(url) == "blob":
        assert_true(entry.loaded and entry.in_archive, what + " is in the zip")
    else:
        assert_true(entry.loaded, what + " is loaded")
        assert_equal(entry.source, doc.string(url), what)
    var wraps: List[Wrap] = [REPEAT, CLAMP, MIRROR]
    var ws = doc.integer(doc.get(node, "wrapS")) - 1000
    var wt = doc.integer(doc.get(node, "wrapT")) - 1000
    assert_true(texture.wrap_s == wraps[ws], what + " wrapS")
    assert_true(texture.wrap_t == wraps[wt], what + " wrapT")
    var srgb = doc.string(doc.get(node, "colorSpace")) == "srgb"
    assert_true(texture.color_space == (SRGB if srgb else LINEAR), what)
    assert_equal(
        texture.channel.value, doc.integer(doc.get(node, "channel")), what
    )
    assert_almost_equal(
        Float64(texture.rotation.value),
        doc.number(doc.get(node, "rotation")),
        atol=1e-5,
        msg=what + " rotation",
    )
    var repeat = doc.get(node, "repeat")
    var offset = doc.get(node, "offset")
    assert_almost_equal(Float64(texture.repeat.x), doc.number(doc.at(repeat, 0)))
    assert_almost_equal(Float64(texture.repeat.y), doc.number(doc.at(repeat, 1)))
    assert_almost_equal(
        Float64(texture.offset.x), doc.number(doc.at(offset, 0)), atol=1e-5
    )
    assert_almost_equal(
        Float64(texture.offset.y), doc.number(doc.at(offset, 1)), atol=1e-5
    )
    for key in ["scale", "bias"]:  # pragma: no branch
        var want = doc.get(node, key)
        var got = entry.scale.copy() if key == "scale" else entry.bias.copy()
        if doc.kind(want) == NULL:
            assert_false(Bool(got), what + " " + key)
        else:
            assert_true(Bool(got), what + " " + key)
            assert_equal(len(got.value()), doc.length(want))
            for k in range(doc.length(want)):
                assert_almost_equal(got.value()[k], doc.number(doc.at(want, k)))


def _same_material(
    assets: Assets,
    model: UsdModel,
    id: MaterialId,
    doc: JsonDocument,
    node: Int,
    what: String,
) raises:
    """Assert a material is three.js's.

    Args:
        assets: The assets.
        model: What was added.
        id: The material.
        doc: The reference.
        node: Its entry.
        what: The name, for a failure.
    """
    ref m = assets.materials.get(id)
    _near_color(m.color, doc, doc.get(node, "color"), what + " color")
    _near_color(m.emissive, doc, doc.get(node, "emissive"), what + " emissive")
    _near_color(
        m.specular_color, doc, doc.get(node, "specularColor"), what + " specular"
    )
    var numbers: List[Float32] = [
        m.roughness,
        m.metalness,
        m.clearcoat,
        m.clearcoat_roughness,
        m.ior,
        m.opacity,
        m.alpha_test,
        m.normal_scale.x,
        m.normal_scale.y,
    ]
    var keys: List[String] = [
        "roughness",
        "metalness",
        "clearcoat",
        "clearcoatRoughness",
        "ior",
        "opacity",
        "alphaTest",
    ]
    for k in range(len(keys)):  # pragma: no branch
        assert_almost_equal(
            Float64(numbers[k]),
            doc.number(doc.get(node, keys[k])),
            atol=1e-5,
            msg=what + " " + keys[k],
        )
    var scale = doc.get(node, "normalScale")
    assert_almost_equal(Float64(numbers[7]), doc.number(doc.at(scale, 0)))
    assert_almost_equal(Float64(numbers[8]), doc.number(doc.at(scale, 1)))
    assert_equal(m.transparent, doc.boolean(doc.get(node, "transparent")), what)
    var maps: List[TextureId] = [
        m.map,
        m.emissive_map,
        m.normal_map,
        m.roughness_map,
        m.metalness_map,
        m.ao_map,
        m.specular_color_map,
    ]
    var names: List[String] = [
        "map",
        "emissiveMap",
        "normalMap",
        "roughnessMap",
        "metalnessMap",
        "aoMap",
        "specularColorMap",
    ]
    for k in range(len(names)):  # pragma: no branch
        _same_map(
            assets, model, maps[k], doc, doc.get(node, names[k]), what + " " + names[k]
        )


def _same_object(
    scene: Scene,
    assets: Assets,
    model: UsdModel,
    mut at: Int,
    doc: JsonDocument,
    node: Int,
    what: String,
) raises:
    """Assert an object and those under it are three.js's, depth first.

    Args:
        scene: The scene.
        assets: The assets.
        model: What was added.
        at: The object's place in `model.objects`; moved past those under
            it.
        doc: The reference.
        node: Its entry.
        what: The file, for a failure.
    """
    ref object = model.objects[at]
    var place = at
    var three = scene.get(object.node)
    var name = what + " " + doc.string(doc.get(node, "name"))
    assert_equal(three.name, doc.string(doc.get(node, "name")), what)
    var type = doc.string(doc.get(node, "type"))
    assert_equal(object.is_mesh, type == "Mesh", name + " is a mesh")
    if type == "Group":
        assert_true(three.object_type == GROUP_TYPE, name + " is a group")
    var position = doc.get(node, "position")
    var quaternion = doc.get(node, "quaternion")
    var scale = doc.get(node, "scale")
    var got: List[Float32] = [
        three.position.x,
        three.position.y,
        three.position.z,
        three.quaternion.x,
        three.quaternion.y,
        three.quaternion.z,
        three.quaternion.w,
        three.scale.x,
        three.scale.y,
        three.scale.z,
    ]
    var want = List[Float64]()
    for k in range(3):  # pragma: no branch
        want.append(doc.number(doc.at(position, k)))
    for k in range(4):  # pragma: no branch
        want.append(doc.number(doc.at(quaternion, k)))
    for k in range(3):  # pragma: no branch
        want.append(doc.number(doc.at(scale, k)))
    for k in range(10):  # pragma: no branch
        assert_almost_equal(Float64(got[k]), want[k], atol=1e-4, msg=name)
    if object.is_mesh:
        ref geometry = assets.geometries.get(object.geometry)
        var attributes = doc.get(node, "attributes")
        var count = 0
        for key in [POSITION, NORMAL, UV, UV1]:  # pragma: no branch
            if doc.has(attributes, String(key)):
                count += 1
                _near_list(
                    geometry.attribute_view(String(key)).data.copy(),
                    doc,
                    doc.get(attributes, String(key)),
                    name + " " + String(key),
                )
        assert_equal(geometry.attribute_count(), count, name + " attributes")
        var groups = doc.get(node, "groups")
        assert_equal(len(geometry.groups), doc.length(groups), name + " groups")
        for g in range(doc.length(groups)):
            var group = doc.at(groups, g)
            assert_equal(geometry.groups[g].start, doc.integer(doc.at(group, 0)))
            assert_equal(geometry.groups[g].count, doc.integer(doc.at(group, 1)))
            assert_equal(
                geometry.groups[g].material_index.value,
                doc.integer(doc.at(group, 2)),
            )
        var materials = doc.get(node, "materials")
        assert_equal(len(object.materials), doc.length(materials), name)
        for k in range(doc.length(materials)):
            _same_material(
                assets,
                model,
                object.materials[k],
                doc,
                doc.at(materials, k),
                name + " material " + String(k),
            )
    var children = doc.get(node, "children")
    at += 1
    var count = 0
    for k in range(doc.length(children)):
        assert_true(at < len(model.objects), name + " has a child")
        assert_equal(model.objects[at].parent, place, name + " child")
        _same_object(scene, assets, model, at, doc, doc.at(children, k), what)
        count += 1
    assert_equal(count, doc.length(children))


def _same_scene(
    scene: Scene, assets: Assets, model: UsdModel, doc: JsonDocument, key: String
) raises:
    """Assert a model is three.js's reading of a fixture.

    Args:
        scene: The scene.
        assets: The assets.
        model: What was added.
        doc: The reference.
        key: The fixture's entry.
    """
    var at = 0
    _same_object(
        scene, assets, model, at, doc, doc.get(doc.get(doc.root(), "scenes"), key), key
    )
    assert_equal(at, len(model.objects), key + " has no other objects")


def test_scenes_match_three_js() raises:
    var doc = _reference()
    for name in [  # pragma: no branch
        "scene.usda",
        "scene.usdc",
        "variants.usdc",
        "values.usdc",
        "package.usdz",
        "crate.usdz",
        "roundtrip.usdz",
    ]:
        var scene = Scene()
        var assets = Assets()
        var model = read_usd(_DIR + name, scene, assets)
        _same_scene(scene, assets, model, doc, name)


def test_text_matches_three_js() raises:
    var doc = _reference()
    var scene = Scene()
    var assets = Assets()
    var model = parse_usda(Path(_DIR + "scene.usda").read_text(), scene, assets)
    _same_scene(scene, assets, model, doc, "scene.usda text")
    assert_equal(len(model.textures), 0)


def _roundtrip_scene() raises -> Tuple[Scene, Assets]:
    """Return the scene `assets/usd/roundtrip.usdz` was written from."""
    var scene = Scene()
    var assets = Assets()
    var brick = texture_from_file("assets/brick.png", SRGB, REPEAT, COVERAGE)
    brick.repeat = Vector2(2, 2)
    brick.offset = Vector2(0.25, 0)
    brick.rotation = Angle(30.0, DEGREE)
    var map = assets.textures.add(brick^)
    var bumps = texture_from_file("assets/brick.png", LINEAR, MIRROR, IGNORED)
    var normal = assets.textures.add(bumps^)
    var m0 = Material(Color(hex=0x8040FF), kind=STANDARD)
    m0.roughness = 0.5
    m0.metalness = 0.25
    var m1 = Material(Color(hex=0xFFFFFF), kind=PHYSICAL)
    m1.map = map
    m1.normal_map = normal
    m1.clearcoat = 0.5
    m1.clearcoat_roughness = 0.25
    m1.ior = 1.25
    m1.emissive = Color(hex=0x202020)
    var crate = assets.geometries.add(
        box(Length(1.0, METER), Length(2.0, METER), Length(0.5, METER))
    )
    var tri = BufferGeometry()
    tri.set_attribute(
        String(POSITION),
        BufferAttribute([Float32(0), 0, 0, 1, 0, 0, 0, 1, 0], 3),
    )
    tri.set_attribute(
        String(NORMAL),
        BufferAttribute([Float32(0), 0, 1, 0, 0, 1, 0, 0, 1], 3),
    )
    tri.set_attribute(
        String(UV), BufferAttribute([Float32(0), 0, 1, 0, 0, 1], 2)
    )
    var lid = assets.geometries.add(tri^)
    var id0 = assets.materials.add(m0)
    var id1 = assets.materials.add(m1)
    var n0 = Object3D()
    n0.name = "Crate"
    n0.set_position(1, 2, 3)
    n0.set_scale(2, 2, 2)
    var crate_node = scene.add(n0^)
    var n1 = Object3D()
    n1.name = "Lid"
    n1.quaternion = Quaternion.from_axis_angle(
        Vector3(0, 1, 0), Angle(90.0, DEGREE)
    )
    n1.set_position(0, 1, 0)
    var lid_node = scene.attach(n1^, crate_node)
    scene.add_mesh(Mesh(crate, id0, crate_node))
    scene.add_mesh(Mesh(lid, id1, lid_node))
    return (scene^, assets^)


def test_round_trip_through_the_exporter() raises:
    # The fixture is what the exporter writes today, so three.js's reading
    # of it is three.js's reading of this port's export.
    var world = _roundtrip_scene()
    var archive = export_usdz(world[0], world[1])
    var fixture = Path(_DIR + "roundtrip.usdz").read_bytes()
    assert_equal(len(archive), len(fixture), "the exporter writes the fixture")
    for k in range(len(archive)):
        assert_equal(archive[k], fixture[k], "the exporter writes the fixture")
    var scene = Scene()
    var assets = Assets()
    var model = parse_usd(archive, scene, assets)
    _same_scene(scene, assets, model, _reference(), "roundtrip.usdz")
    # The geometry reads back as the exporter wrote it.
    var crate = model.objects[4].copy()
    ref geometry = assets.geometries.get(crate.geometry)
    assert_equal(len(geometry.attribute_view(String(POSITION)).data), 36 * 3)


def test_read_usdz_is_read_usd() raises:
    var scene = Scene()
    var assets = Assets()
    var model = read_usdz(_DIR + "crate.usdz", scene, assets)
    assert_equal(scene.get(model.objects[1].node).name, "Root")


def test_parent() raises:
    var scene = Scene()
    var assets = Assets()
    var holder = Object3D()
    holder.name = "Holder"
    var at = scene.add(holder^)
    var model = parse_usda(
        '#usda 1.0\ndef Xform "A"\n{\n}\n', scene, assets, at
    )
    assert_true(scene.get(model.root).parent == at)
    assert_equal(len(model.objects), 2)


def test_extension_and_folder() raises:
    assert_equal(lowercase_extension("a/b.USDZ"), "usdz")
    assert_equal(lowercase_extension("a.b/c"), "")
    assert_equal(lowercase_extension("abc"), "")
    assert_equal(url_base("a/b/c.usd"), "a/b/")
    assert_equal(url_base("c.usd"), "./")


def test_decode_text() raises:
    assert_equal(decode_text([0xEF, 0xBB, 0xBF, 0x41]), "A")
    assert_equal(decode_text([0x41, 0x42]), "AB")
    assert_equal(decode_text([0xEF, 0xBB]), "�")
    assert_equal(decode_text(List[UInt8]()), "")


def _zip(names: List[String], data: List[List[UInt8]]) raises -> List[UInt8]:
    """Return a stored archive of files.

    Args:
        names: The files' names.
        data: Their bytes.

    Returns:
        The archive.
    """
    var entries = List[ZipEntry]()
    for k in range(len(names)):  # pragma: no branch
        entries.append(ZipEntry(names[k], ZIP_STORED, data[k].copy()))
    return zip_archive(entries)


def _bytes(text: String) -> List[UInt8]:
    """Return a text's bytes.

    Args:
        text: The text.

    Returns:
        Its UTF-8 bytes.
    """
    return List[UInt8](text.as_bytes())


def test_archives() raises:
    var scene = Scene()
    var assets = Assets()
    var layer = '#usda 1.0\ndef Xform "A"\n{\n}\n'
    # The first file is the stage; a `.usd` of text is USDA. A later file
    # of the same name replaces the first in its place, and a file of any
    # other kind is dropped.
    var archive = _zip(
        ["dir/x.USD", "notes.txt", "dir/x.USD", "img.JPG"],
        [_bytes("#usda 1.0\n"), _bytes("hi"), _bytes(layer), _bytes("no")],
    )
    var model = parse_usd(archive, scene, assets)
    assert_equal(scene.get(model.objects[1].node).name, "A")
    # A `.usd` crate is the stage too.
    var crate = Path(_DIR + "geo.usdc").read_bytes()
    model = parse_usd(_zip(["a.usd"], [crate.copy()]), scene, assets)
    assert_equal(scene.get(model.objects[1].node).name, "Other")
    # A `.usdc` whose bytes are text is read as text.
    model = parse_usd(_zip(["a.usdc"], [_bytes(layer)]), scene, assets)
    assert_equal(scene.get(model.objects[1].node).name, "A")
    with assert_raises(contains="first file must be a USD layer"):
        _ = parse_usd(_zip(["a.png", "b.usda"], [_bytes("x"), _bytes(layer)]), scene, assets)
    with assert_raises(contains="first file must be a USD layer"):
        _ = parse_usd(_zip(List[String](), List[List[UInt8]]()), scene, assets)


def test_bytes_that_are_text() raises:
    var scene = Scene()
    var assets = Assets()
    var model = parse_usd(_bytes('#usda 1.0\ndef "B"\n{\n}\n'), scene, assets)
    assert_equal(scene.get(model.objects[1].node).name, "B")
    model = parse_usd(_bytes("P"), scene, assets)
    assert_equal(len(model.objects), 1)


def test_refusals() raises:
    var scene = Scene()
    var assets = Assets()
    with assert_raises():
        _ = read_usd(_DIR + "missing.usdz", scene, assets)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
