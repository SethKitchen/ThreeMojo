# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.vox`.

`assets/vox/fixture.json` is what three.js 0.180's `VOXLoader`,
`VOXMesh` and `VOXData3DTexture` give for `assets/vox/fixture.vox` in
node: three models, one of them all black and one with the file's
palette.
"""

from core.assets import Assets
from core.buffer_geometry import COLOR, NORMAL, POSITION
from core.object3d import Object3D
from core.scene import Scene
from loaders.json import JsonDocument, parse_json
from loaders.vox import (
    VoxModel,
    add_vox_mesh,
    parse_vox,
    read_vox,
    vox_data_3d_texture,
    vox_geometry,
    vox_has_colors,
    vox_material,
)
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def near(got: Float64, want: Float64) raises:
    """Assert two numbers agree to a `Float32`."""
    var scale = max(Float64(1), abs(want))
    if not (abs(got - want) <= 1e-6 * scale):
        raise Error("got " + String(got) + ", want " + String(want))


def check(got: List[Float32], doc: JsonDocument, node: Int) raises:
    """Assert numbers match a JSON array."""
    assert_equal(len(got), doc.length(node))
    for i in range(len(got)):
        near(Float64(got[i]), doc.number(doc.at(node, i)))


def test_the_fixture_matches_three_js() raises:
    var models = read_vox("assets/vox/fixture.vox")
    var doc = parse_json(Path("assets/vox/fixture.json").read_text())
    assert_equal(len(models), doc.length(doc.root()))
    for m in range(len(models)):
        var want = doc.at(doc.root(), m)
        ref model = models[m]
        var size = doc.get(want, "size")
        assert_equal(model.size_x, doc.integer(doc.at(size, 0)))
        assert_equal(model.size_y, doc.integer(doc.at(size, 1)))
        assert_equal(model.size_z, doc.integer(doc.at(size, 2)))
        var geometry = vox_geometry(model)
        check(
            geometry.clone_attribute(String(POSITION)).packed(),
            doc,
            doc.get(want, "position"),
        )
        check(
            geometry.clone_attribute(String(NORMAL)).packed(),
            doc,
            doc.get(want, "normal"),
        )
        var color = doc.get(want, "color")
        assert_equal(
            geometry.has_attribute(String(COLOR)), not doc.is_null(color)
        )
        if not doc.is_null(color):
            check(geometry.clone_attribute(String(COLOR)).packed(), doc, color)
        var material = vox_material(model)
        assert_equal(
            material.vertex_colors, doc.boolean(doc.get(want, "vertexColors"))
        )
        var volume = vox_data_3d_texture(model)
        var cells = doc.get(want, "volume")
        var texels = volume.image.pixels.copy()
        assert_equal(len(texels), doc.length(cells) * 4)
        for i in range(doc.length(cells)):
            assert_equal(Int(texels[i * 4]), doc.integer(doc.at(cells, i)))
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    var node = add_vox_mesh(models[0], scene, assets, parent)
    assert_true(scene.get(node).parent == parent)
    assert_equal(len(scene.meshes), 1)


def u32(value: Int) -> List[UInt8]:
    """Return a little-endian 32-bit value."""
    var out = List[UInt8]()
    for k in range(4):
        out.append(UInt8((value >> (8 * k)) & 0xFF))
    return out^


def chunk(id: String, content: List[UInt8]) -> List[UInt8]:
    """Return a chunk with no children."""
    var out = List[UInt8]()
    for byte in id.as_bytes():
        out.append(byte)
    out.extend(u32(len(content)))
    out.extend(u32(0))
    out.extend(content.copy())
    return out^


def vox(body: List[UInt8]) -> List[UInt8]:
    """Return a VOX file of chunks."""
    var out: List[UInt8] = [86, 79, 88, 32]
    out.extend(u32(150))
    out.extend(body.copy())
    return out^


def size(x: Int, y: Int, z: Int) -> List[UInt8]:
    """Return a SIZE chunk."""
    var content = u32(x)
    content.extend(u32(y))
    content.extend(u32(z))
    return chunk("SIZE", content)


def xyzi(voxels: List[UInt8]) -> List[UInt8]:
    """Return an XYZI chunk."""
    var content = u32(len(voxels) // 4)
    content.extend(voxels.copy())
    return chunk("XYZI", content)


def test_refusals_and_edges() raises:
    var empty = parse_vox(vox([]))
    assert_equal(len(empty), 0)
    var hollow = size(1, 1, 1)
    hollow.extend(xyzi([]))
    assert_equal(parse_vox(vox(hollow))[0].voxel_count(), 0)
    var bare = VoxModel(2, 1, 1)
    assert_false(vox_has_colors(bare))
    assert_equal(vox_geometry(bare).vertex_count(), 0)
    var odd = bare.copy()
    odd.data = [0, 0, 0, 1]
    odd.palette = [0]
    with assert_raises(contains="past the palette"):
        _ = vox_geometry(odd)
    with assert_raises(contains="not a VOX file"):
        _ = parse_vox([86, 79, 88, 33, 150, 0, 0, 0])
    with assert_raises(contains="not supported"):
        _ = parse_vox([86, 79, 88, 32, 200, 0, 0, 0])
    with assert_raises(contains="ends inside a chunk"):
        _ = parse_vox([86, 79])
    with assert_raises(contains="too short"):
        _ = parse_vox(vox(chunk("SIZE", u32(1))))
    with assert_raises(contains="voxels before any SIZE"):
        _ = parse_vox(vox(xyzi([])))
    with assert_raises(contains="palette before any SIZE"):
        _ = parse_vox(vox(chunk("RGBA", [])))
    var short = size(1, 1, 1)
    short.extend(chunk("XYZI", u32(3)))
    with assert_raises(contains="ends inside its voxels"):
        _ = parse_vox(vox(short))
    for axis in range(3):
        var voxel: List[UInt8] = [0, 0, 0, 1]
        voxel[axis] = 1
        var outside = size(1, 1, 1)
        outside.extend(xyzi(voxel))
        with assert_raises(contains="outside its model"):
            _ = parse_vox(vox(outside))
    with assert_raises():
        _ = vox_data_3d_texture(VoxModel(0, 1, 1))
    with assert_raises():
        _ = read_vox("assets/vox/missing.vox")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
