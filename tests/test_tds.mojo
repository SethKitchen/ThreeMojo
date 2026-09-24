# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.tds`.

`assets/3ds/fixture.json` is what three.js 0.180's `TDSLoader` gives for
`assets/3ds/fixture.3ds` in node: the scale, each mesh's name,
transform, attributes, index, groups and materials. The first test
compares all of it. Files built inline reach every refusal.
"""

from core.assets import Assets
from core.buffer_geometry import NORMAL, POSITION, UV
from core.object3d import NO_PARENT, Object3D
from core.scene import Scene
from loaders.json import JsonDocument, parse_json
from loaders.tds import TdsMaterial, TdsModel, parse_3ds, read_3ds
from materials.material import ADDITIVE, DOUBLE_SIDE, FRONT_SIDE, MaterialId
from render.framebuffer import Color
from render.texture_store import NO_TEXTURE
from std.memory import bitcast
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def near(got: Float64, want: Float64, tolerance: Float64 = 1e-5) raises:
    """Assert two numbers agree within a tolerance relative to their size."""
    var scale = max(Float64(1), abs(want))
    if not (abs(got - want) <= tolerance * scale):
        raise Error("got " + String(got) + ", want " + String(want))


def check_list(got: List[Float32], doc: JsonDocument, node: Int) raises:
    """Assert numbers match a JSON array."""
    assert_equal(len(got), doc.length(node))
    for i in range(len(got)):
        near(Float64(got[i]), doc.number(doc.at(node, i)))


def hex(color: Color) -> String:
    """Return a color as three.js's `getHexString`."""
    comptime digits = "0123456789abcdef"
    var out = String()
    for byte in [color.r, color.g, color.b]:
        out += digits[byte=Int(byte) // 16]
        out += digits[byte=Int(byte) % 16]
    return out^


def check_material(
    doc: JsonDocument,
    want: Int,
    model: TdsModel,
    id: MaterialId,
    assets: Assets,
) raises:
    """Compare one material with three.js's."""
    var material = assets.materials.get(id)
    var entry = TdsMaterial()
    for i in range(len(model.material_ids)):
        if model.material_ids[i] == id:
            entry = model.materials[i].copy()
    assert_equal(entry.name, doc.string(doc.get(want, "name")))
    assert_equal(hex(material.color), doc.string(doc.get(want, "color")))
    assert_equal(hex(material.specular), doc.string(doc.get(want, "specular")))
    near(Float64(material.shininess), doc.number(doc.get(want, "shininess")))
    near(Float64(material.opacity), doc.number(doc.get(want, "opacity")))
    assert_equal(
        material.transparent, doc.boolean(doc.get(want, "transparent"))
    )
    var side = doc.integer(doc.get(want, "side"))
    assert_true(material.side == (DOUBLE_SIDE if side == 2 else FRONT_SIDE))
    assert_equal(
        material.blending == ADDITIVE,
        doc.integer(doc.get(want, "blending")) == 2,
    )
    assert_equal(entry.wireframe, doc.boolean(doc.get(want, "wireframe")))
    assert_equal(
        entry.wireframe_width,
        doc.integer(doc.get(want, "wireframeLinewidth")),
    )
    var map = doc.get(want, "map")
    assert_equal(material.map != NO_TEXTURE, not doc.is_null(map))
    if material.map != NO_TEXTURE:
        ref texture = assets.textures.get(material.map)
        var offset = doc.get(map, "offset")
        var repeat = doc.get(map, "repeat")
        near(Float64(texture.offset.x), doc.number(doc.at(offset, 0)))
        near(Float64(texture.offset.y), doc.number(doc.at(offset, 1)))
        near(Float64(texture.repeat.x), doc.number(doc.at(repeat, 0)))
        near(Float64(texture.repeat.y), doc.number(doc.at(repeat, 1)))
    assert_equal(
        material.bump_map != NO_TEXTURE,
        not doc.is_null(doc.get(want, "bumpMap")),
    )
    assert_equal(
        material.alpha_map != NO_TEXTURE,
        not doc.is_null(doc.get(want, "alphaMap")),
    )
    assert_equal(
        material.specular_map != NO_TEXTURE,
        not doc.is_null(doc.get(want, "specularMap")),
    )


def test_the_fixture_matches_three_js() raises:
    var scene = Scene()
    var assets = Assets()
    var model = read_3ds("assets/3ds/fixture.3ds", scene, assets)
    var doc = parse_json(Path("assets/3ds/fixture.json").read_text())
    var root = scene.get(model.root)
    var scale = doc.get(doc.root(), "scale")
    near(Float64(root.scale.x), doc.number(doc.at(scale, 0)))
    near(Float64(root.scale.z), doc.number(doc.at(scale, 2)))
    var meshes = doc.get(doc.root(), "meshes")
    assert_equal(len(model.nodes), doc.length(meshes))
    for i in range(len(model.nodes)):
        var want = doc.at(meshes, i)
        var node = scene.get(model.nodes[i])
        assert_equal(node.name, doc.string(doc.get(want, "name")))
        assert_equal(model.names[i], node.name)
        assert_true(node.parent == model.root)
        check_list(
            [node.position.x, node.position.y, node.position.z],
            doc,
            doc.get(want, "position"),
        )
        check_list(
            [
                node.quaternion.x,
                node.quaternion.y,
                node.quaternion.z,
                node.quaternion.w,
            ],
            doc,
            doc.get(want, "quaternion"),
        )
        check_list(
            [node.scale.x, node.scale.y, node.scale.z],
            doc,
            doc.get(want, "scale"),
        )
        ref geometry = assets.geometries.get(model.geometries[i])
        var attrs = doc.get(want, "attrs")
        assert_equal(geometry.attribute_count(), doc.length(attrs))
        for name in [String(POSITION), String(UV), String(NORMAL)]:
            if doc.has(attrs, name):
                check_list(
                    geometry.clone_attribute(name).packed(),
                    doc,
                    doc.get(attrs, name),
                )
        var index = doc.get(want, "index")
        assert_equal(len(geometry.index), doc.length(index))
        for k in range(len(geometry.index)):
            assert_equal(geometry.index[k], doc.integer(doc.at(index, k)))
        var groups = doc.get(want, "groups")
        assert_equal(len(geometry.groups), doc.length(groups))
        for g in range(len(geometry.groups)):
            var wg = doc.at(groups, g)
            assert_equal(geometry.groups[g].start, doc.integer(doc.at(wg, 0)))
            assert_equal(geometry.groups[g].count, doc.integer(doc.at(wg, 1)))
            assert_equal(
                geometry.groups[g].material_index.value,
                doc.integer(doc.at(wg, 2)),
            )
        var materials = doc.get(want, "materials")
        assert_equal(len(model.mesh_materials[i]), doc.length(materials))
        for m in range(len(model.mesh_materials[i])):
            check_material(
                doc,
                doc.at(materials, m),
                model,
                model.mesh_materials[i][m],
                assets,
            )
    # Quad, Tetra and Plain draw once; Duo draws each of its two groups.
    assert_equal(model.mesh_count, 5)
    assert_equal(len(scene.meshes), 5)
    assert_equal(len(model.textures), 4)
    ref second = assets.geometries.get(scene.meshes[4].geometry)
    assert_equal(second.index, [0, 2, 3])


def chunk(id: Int, body: List[UInt8]) -> List[UInt8]:
    """Return a chunk: its id, its size and its body."""
    var out = List[UInt8]()
    var size = len(body) + 6
    out.append(UInt8(id & 0xFF))
    out.append(UInt8(id >> 8))
    for k in range(4):
        out.append(UInt8((size >> (8 * k)) & 0xFF))
    out.extend(body.copy())
    return out^


def join(parts: List[List[UInt8]]) -> List[UInt8]:
    """Return byte lists end to end."""
    var out = List[UInt8]()
    for part in parts:
        out.extend(part.copy())
    return out^


def text(value: String) -> List[UInt8]:
    """Return a string and its zero."""
    var out = List[UInt8]()
    for byte in value.as_bytes():
        out.append(byte)
    out.append(0)
    return out^


def word(value: Int) -> List[UInt8]:
    """Return a little-endian 16-bit value."""
    return [UInt8(value & 0xFF), UInt8(value >> 8)]


def float(value: Float32) -> List[UInt8]:
    """Return a little-endian float."""
    var raw = bitcast[DType.uint32](value)
    var out = List[UInt8]()
    for k in range(4):
        out.append(UInt8((raw >> UInt32(8 * k)) & 0xFF))
    return out^


def file(data: List[List[UInt8]]) -> List[UInt8]:
    """Return a main chunk holding an editor chunk of parts."""
    return chunk(0x4D4D, chunk(0x3D3D, join(data)))


def triangle(extra: List[List[UInt8]]) -> List[UInt8]:
    """Return a named object of one triangle and more mesh chunks."""
    var pieces: List[List[UInt8]] = [word(3)]
    for value in [0, 0, 0, 1, 0, 0, 0, 1, 0]:
        pieces.append(float(Float32(value)))
    var points = join(pieces)
    var parts: List[List[UInt8]] = [chunk(0x4110, points)]
    parts.extend(extra.copy())
    return chunk(0x4000, join([text("T"), chunk(0x4100, join(parts))]))


def load(bytes: List[UInt8]) raises -> Int:
    """Read bytes and return how many meshes they drew."""
    var scene = Scene()
    var assets = Assets()
    var model = parse_3ds(bytes, scene, assets)
    return model.mesh_count


def test_other_files() raises:
    # A file whose first chunk is not a main chunk gives an empty root.
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    var empty = parse_3ds(chunk(0x1234, []), scene, assets, "", parent)
    assert_equal(len(empty.nodes), 0)
    assert_true(scene.get(empty.root).parent == parent)
    assert_equal(load(chunk(0x3DAA, [])), 0)
    assert_equal(load(chunk(0xC23D, chunk(0x3D3D, []))), 0)
    # A map whose file is not there keeps no texture.
    var missing = file(
        [
            chunk(
                0xAFFF,
                join(
                    [
                        chunk(0xA000, text("M")),
                        chunk(0xA200, chunk(0xA300, text("none.png"))),
                        chunk(0xA020, chunk(0x0099, [])),
                        chunk(0xA040, chunk(0x0099, [])),
                    ]
                ),
            ),
            triangle(
                [
                    chunk(
                        0x4120,
                        join(
                            [
                                word(1),
                                word(0),
                                word(1),
                                word(2),
                                word(0),
                                chunk(0x4130, join([text("None"), word(0)])),
                            ]
                        ),
                    )
                ]
            ),
        ]
    )
    var model = parse_3ds(missing, scene, assets)
    assert_equal(len(model.textures), 0)
    assert_true(model.materials[0].map.value().texture == NO_TEXTURE)
    assert_equal(model.materials[0].shininess, 0)
    assert_equal(model.mesh_count, 0)
    assert_equal(len(model.mesh_materials[0]), 0)
    # A mesh with no faces keeps its points as they are.
    assert_equal(load(file([triangle([])])), 1)
    # A group before any material, and empty arrays with a matrix.
    var matrix = List[List[UInt8]]()
    for value in [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]:
        matrix.append(float(Float32(value)))
    var bare = chunk(
        0x4000,
        join(
            [
                text("B"),
                chunk(
                    0x4100,
                    join(
                        [
                            chunk(0x4110, word(0)),
                            chunk(0x4140, word(0)),
                            chunk(0x4160, join(matrix)),
                            chunk(
                                0x4120,
                                join(
                                    [
                                        word(0),
                                        chunk(
                                            0x4130, join([text("X"), word(0)])
                                        ),
                                    ]
                                ),
                            ),
                        ]
                    ),
                ),
            ]
        ),
    )
    assert_equal(load(file([bare^])), 0)
    # Three groups and two materials: the middle group takes the second
    # material and the last draws nothing, as in three.js.
    var face = join([word(1), word(0), word(1), word(2), word(0)])
    var groups = join(
        [
            face^,
            chunk(0x4130, join([text("R"), word(1), word(0)])),
            chunk(0x4130, join([text("Q"), word(0)])),
            chunk(0x4130, join([text("S"), word(0)])),
        ]
    )
    var trio = file(
        [
            chunk(0xAFFF, chunk(0xA000, text("R"))),
            chunk(0xAFFF, chunk(0xA000, text("S"))),
            triangle([chunk(0x4120, groups)]),
        ]
    )
    assert_equal(load(trio), 2)


def test_refusals() raises:
    with assert_raises(contains="ends inside a value"):
        _ = load([0x4D, 0x4D, 6])
    with assert_raises(contains="shorter than its header"):
        _ = load([0x4D, 0x4D, 5, 0, 0, 0])
    with assert_raises(contains="runs past the end"):
        _ = load([0x4D, 0x4D, 9, 0, 0, 0])
    with assert_raises(contains="ends inside a value"):
        _ = load(file([chunk(0x0100, [0, 0])]))
    with assert_raises(contains="has no points"):
        _ = load(file([chunk(0x4000, join([text("E"), chunk(0x4100, [])]))]))
    with assert_raises(contains="color chunk with no value"):
        _ = load(file([chunk(0xAFFF, chunk(0xA020, []))]))
    with assert_raises(contains="percentage chunk with no value"):
        _ = load(file([chunk(0xAFFF, chunk(0xA050, []))]))
    with assert_raises(contains="before its file"):
        _ = load(file([chunk(0xAFFF, chunk(0xA200, chunk(0xA354, float(1))))]))
    with assert_raises(contains="map with no file"):
        _ = load(file([chunk(0xAFFF, chunk(0xA200, []))]))
    with assert_raises():
        _ = load(
            file(
                [
                    triangle(
                        [
                            chunk(
                                0x4120,
                                join(
                                    [
                                        word(1),
                                        word(0),
                                        word(1),
                                        word(9),
                                        word(0),
                                    ]
                                ),
                            )
                        ]
                    )
                ]
            )
        )
    var scene = Scene()
    var assets = Assets()
    with assert_raises():
        _ = read_3ds("assets/3ds/missing.3ds", scene, assets)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
