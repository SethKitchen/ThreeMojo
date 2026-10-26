# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A synthetic town package keeps its colors, slots and repeated bytes."""

from std.memory import bitcast
from std.os import makedirs
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tools._process import run_program
from tools._python_json import MISSING, PY_FLOAT, PY_INT, PyJson
from tools.carla_png import png_bytes
from tools.carla_town_build import build_town
from tools.carla_town_cube import cube_text
from render.jpeg import decode as decode_jpeg
from render.png import DecodedImage
from render.png import decode as decode_png


def test_two_colors_stay_apart_and_share_a_repeated_cell() raises:
    """Red and green stay distinct, and the repeated red cell shares one material.
    """
    var package = _package(["Red", "Red", "Green", "Green", "Red", "Red"])
    for kind in ["building", "vegetation"]:
        for lod in [0, 1]:
            var first = _node_material(package, kind + "_0_0_lod" + String(lod))
            var second = _node_material(
                package, kind + "_1_0_lod" + String(lod)
            )
            var third = _node_material(package, kind + "_2_0_lod" + String(lod))
            assert_equal(first, third)
            assert_true(first != second)
            var red = _covered_mean(_image(package, first), 0)
            var red_other = _covered_mean(_image(package, first), 1)
            var green = _covered_mean(_image(package, second), 1)
            var green_other = _covered_mean(_image(package, second), 0)
            assert_true(red > 80.0)
            assert_true(red - red_other > 70.0)
            assert_true(green > 80.0)
            assert_true(green - green_other > 70.0)


def test_slot_order_stays_visible() raises:
    """Each slot's color stays on its cube, in the near mesh and the far picture.
    """
    var package = _package(["Red", "Green", "Green", "Red", "Red", "Green"])
    for kind in ["building", "vegetation"]:
        for cell in range(3):
            var node = kind + "_" + String(cell) + "_0_lod0"
            var material = _node_material(package, node)
            var name = _material_name(package, material)
            var left = (name == "Red") == (cell != 1)
            var expected = 0.75
            if left:
                expected = -0.75
            var mean = _mean_x(package, node) - Float64(cell * 32)
            var gap = mean - expected
            if gap < 0.0:
                gap = -gap
            assert_true(gap < 0.001)
            var picture = _image(
                package,
                _node_material(package, kind + "_" + String(cell) + "_0_lod1"),
            )
            var left_x = 13
            var left_y = 1
            var left_x1 = 16
            var left_y1 = 5
            var right_x = 23
            var right_y = 1
            var right_x1 = 26
            var right_y1 = 5
            if kind != "building":
                left_x = 43
                left_y = 120
                left_x1 = 59
                left_y1 = 136
                right_x = 197
                right_y = 120
                right_x1 = 213
                right_y1 = 136
            var left_delta = _region(
                picture, left_x, left_y, left_x1, left_y1, 0
            ) - _region(picture, left_x, left_y, left_x1, left_y1, 1)
            var right_delta = _region(
                picture, right_x, right_y, right_x1, right_y1, 0
            ) - _region(picture, right_x, right_y, right_x1, right_y1, 1)
            var red_gap = left_delta
            var green_gap = -right_delta
            if cell == 1:
                red_gap = right_delta
                green_gap = -left_delta
            assert_true(red_gap > 70.0)
            assert_true(green_gap > 70.0)


def test_a_repeated_build_matches_byte_for_byte() raises:
    """Two builds of one fixture write the same package."""
    var first = _package(["Red", "Green", "Green", "Red", "Red", "Green"])
    var second = _package(["Red", "Green", "Green", "Red", "Red", "Green"])
    assert_equal(first.bytes, second.bytes)


def test_a_hidden_grid_slot_omits_that_cell() raises:
    """A cell whose slots are both the world grid is left out of the package."""
    var package = _package(
        [
            "WorldGridMaterial",
            "Red",
            "WorldGridMaterial",
            "Green",
            "WorldGridMaterial",
            "WorldGridMaterial",
        ]
    )
    for kind in ["building", "vegetation"]:
        for cell in [0, 1]:
            _ = _node_material(package, kind + "_" + String(cell) + "_0_lod1")
        assert_true(
            not _has_node(package, kind + "_2_0_lod0")
            and not _has_node(package, kind + "_2_0_lod1")
        )


struct _Package:
    var doc: PyJson
    var blob: List[UInt8]
    var bytes: List[UInt8]

    def __init__(
        out self, var doc: PyJson, var blob: List[UInt8], var bytes: List[UInt8]
    ):
        self.doc = doc^
        self.blob = blob^
        self.bytes = bytes^


struct _Cursor:
    var views: Int
    var accessors: Int

    def __init__(out self):
        self.views = 0
        self.accessors = 0


def _package(materials: List[String]) raises -> _Package:
    """Build one fixture town and return its binary glTF."""
    var root = mkdtemp(prefix="town package ")
    try:
        var raw = root + "/raw"
        var maps = root + "/maps"
        var layout = root + "/layout"
        var out = root + "/packages"
        _ = makedirs(raw)
        _ = makedirs(maps)
        _ = makedirs(layout)
        _ = makedirs(out)
        Path(maps + "/Fixture.xodr").write_text("<OpenDRIVE/>")
        Path(raw + "/Red.png").write_bytes(Span(_png(255, 0, 0)))
        Path(raw + "/Green.png").write_bytes(Span(_png(0, 255, 0)))
        Path(raw + "/Red.mat").write_text("Diffuse=Red\n")
        Path(raw + "/Green.mat").write_text("Diffuse=Green\n")
        var cube = PyJson.parse(cube_text())
        var positions = _flat(cube, cube.at(cube.root, "positions"), 3)
        var normals = _flat(cube, cube.at(cube.root, "normals"), 3)
        var uvs = _flat(cube, cube.at(cube.root, "uvs"), 2)
        var triangles = _ints(cube, cube.at(cube.root, "triangles"))
        _write_mesh(
            raw,
            "/Game/Carla/Static/Building/Fixture",
            positions,
            normals,
            uvs,
            triangles,
        )
        _write_mesh(
            raw,
            "/Game/Carla/Static/Vegetation/Trees/Fixture",
            positions,
            normals,
            uvs,
            triangles,
        )
        Path(layout + "/Fixture.jsonl").write_text(_rows(materials))
        _ = build_town("Fixture", 512, 32.0, raw, layout, maps, out)
        var path = out + "/carla.town.fixture/carla.town.fixture.glb"
        return _open_glb(Path(path).read_bytes())
    finally:
        _ = run_program(["rm", "-rf", root], 10.0)


def _rows(materials: List[String]) -> String:
    """Return three layout rows for each of the two fixture meshes."""
    var meshes = List[String]()
    meshes.append("/Game/Carla/Static/Building/Fixture")
    meshes.append("/Game/Carla/Static/Vegetation/Trees/Fixture")
    var rows = String("")
    for mesh in meshes:
        for index in range(3):
            rows += (
                '{"visible":true,"mesh":"StaticMesh '
                + mesh
                + '.Fixture","location":['
                + String(index * 3200)
                + ',0,0],"rotation":[0,0,0],"scale":[1,1,1],"materials":['
                + _reference(materials[index * 2])
                + ","
                + _reference(materials[index * 2 + 1])
                + "]}\n"
            )
    return rows


def _reference(name: String) -> String:
    """Return one layout material reference."""
    return '"MaterialInstanceConstant /Game/Fixture/' + name + "." + name + '"'


def _png(red: Int, green: Int, blue: Int) raises -> List[UInt8]:
    """Return a 4 by 4 RGB picture of one color."""
    var pixels = List[UInt8]()
    for _ in range(16):
        pixels.append(UInt8(red))
        pixels.append(UInt8(green))
        pixels.append(UInt8(blue))
    return png_bytes("RGB", 4, 4, pixels, False, 3, 2)


def _write_mesh(
    raw: String,
    mesh: String,
    positions: List[Float64],
    normals: List[Float64],
    uvs: List[Float64],
    triangles: List[Int],
) raises:
    """Write one two-part glTF whose cubes sit left and right of the origin."""
    var rest = String(mesh[byte=6:])
    var directory = raw
    var start = 0
    var raw_bytes = rest.as_bytes()
    for index in range(len(raw_bytes)):
        if raw_bytes[index] == 47:
            directory += "/" + String(rest[byte=start:index])
            start = index + 1
    _ = run_program(["mkdir", "-p", directory], 10.0)
    var path = directory + "/" + String(rest[byte=start:]) + ".gltf"
    var blob = List[UInt8]()
    var views = String("[")
    var accessors = String("[")
    var primitives = String("[")
    var materials = String("[")
    var cursor = _Cursor()
    for part in range(2):
        var shift = -0.75
        if part == 1:
            shift = 0.75
        var shifted = List[Float64]()
        for index in range(len(positions) // 3):
            shifted.append(positions[index * 3] + shift)
            shifted.append(positions[index * 3 + 1])
            shifted.append(positions[index * 3 + 2])
        if part > 0:
            materials += ","
            primitives += ","
        materials += '{"name":"Own' + String(part) + '"}'
        primitives += '{"material":' + String(part) + ',"attributes":{'
        primitives += _field(
            blob, views, accessors, cursor, "POSITION", shifted, 3
        )
        primitives += ","
        primitives += _field(
            blob, views, accessors, cursor, "NORMAL", normals, 3
        )
        primitives += ","
        primitives += _field(
            blob, views, accessors, cursor, "TEXCOORD_0", uvs, 2
        )
        primitives += '},"indices":'
        primitives += _indices(blob, views, accessors, cursor, triangles)
        primitives += "}"
    var text = (
        '{"buffers":[{"uri":"Fixture.bin","byteLength":'
        + String(len(blob))
        + '}],"bufferViews":'
        + views
        + "]"
        + ',"accessors":'
        + accessors
        + "]"
        + ',"materials":'
        + materials
        + "]"
        + ',"meshes":[{"primitives":'
        + primitives
        + "]}]}"
    )
    Path(path).write_text(text)
    Path(String(path[byte = 0 : path.byte_length() - 4]) + "bin").write_bytes(
        Span(blob)
    )


def _open_glb(data: List[UInt8]) raises -> _Package:
    """Split a binary glTF into its JSON document and its buffer."""
    if len(data) < 20 or _u32(data, 0) != 0x46546C67 or _u32(data, 4) != 2:
        raise Error("package is not a glTF 2 binary")
    var json_length = _u32(data, 12)
    var json_kind = _u32(data, 16)
    if json_kind != 0x4E4F534A:
        raise Error("package JSON chunk is missing")
    var blob_at = 20 + json_length
    var blob_length = _u32(data, blob_at)
    if _u32(data, blob_at + 4) != 0x004E4942:
        raise Error("package binary chunk is missing")
    var json_bytes = List[UInt8]()
    for index in range(json_length):
        json_bytes.append(data[20 + index])
    var blob = List[UInt8]()
    for index in range(blob_length):
        blob.append(data[blob_at + 8 + index])
    var kept = List[UInt8]()
    for index in range(len(data)):
        kept.append(data[index])
    return _Package(
        PyJson.parse(String(from_utf8_lossy=Span(json_bytes))), blob^, kept^
    )


def _node_material(package: _Package, name: String) raises -> Int:
    """Return the first material index of the node named `name`."""
    var nodes = package.doc.at(package.doc.root, "nodes")
    for index in range(package.doc.length(nodes)):
        var node = package.doc.item(nodes, index)
        if package.doc.text(package.doc.at(node, "name")) == name:
            var mesh = package.doc.item(
                package.doc.at(package.doc.root, "meshes"),
                Int(package.doc.text(package.doc.at(node, "mesh"))),
            )
            var primitive = package.doc.item(
                package.doc.at(mesh, "primitives"), 0
            )
            return Int(package.doc.text(package.doc.at(primitive, "material")))
    raise Error("missing node " + name)


def _has_node(package: _Package, name: String) raises -> Bool:
    """Return whether the package has a node named `name`."""
    var nodes = package.doc.at(package.doc.root, "nodes")
    for index in range(package.doc.length(nodes)):
        var node = package.doc.item(nodes, index)
        if package.doc.text(package.doc.at(node, "name")) == name:
            return True
    return False


def _material_name(package: _Package, material: Int) raises -> String:
    """Return a material's name."""
    var node = package.doc.item(
        package.doc.at(package.doc.root, "materials"), material
    )
    return package.doc.text(package.doc.at(node, "name"))


def _image(package: _Package, material: Int) raises -> DecodedImage:
    """Return the base-color image of one material."""
    var materials = package.doc.at(package.doc.root, "materials")
    var entry = package.doc.item(materials, material)
    var pbr = package.doc.at(entry, "pbrMetallicRoughness")
    var texture = Int(
        package.doc.text(
            package.doc.at(package.doc.at(pbr, "baseColorTexture"), "index")
        )
    )
    var source = Int(
        package.doc.text(
            package.doc.at(
                package.doc.item(
                    package.doc.at(package.doc.root, "textures"), texture
                ),
                "source",
            )
        )
    )
    var image = package.doc.item(
        package.doc.at(package.doc.root, "images"), source
    )
    var view = package.doc.item(
        package.doc.at(package.doc.root, "bufferViews"),
        Int(package.doc.text(package.doc.at(image, "bufferView"))),
    )
    var start = 0
    var offset = package.doc.get(view, "byteOffset")
    if offset != MISSING:
        start = Int(package.doc.text(offset))
    var count = Int(package.doc.text(package.doc.at(view, "byteLength")))
    var bytes = List[UInt8]()
    for index in range(count):
        bytes.append(package.blob[start + index])
    var mime = package.doc.text(package.doc.at(image, "mimeType"))
    if mime == "image/png":
        return decode_png(bytes)
    if mime == "image/jpeg":
        return decode_jpeg(bytes)
    raise Error("unsupported package image")


def _covered_mean(image: DecodedImage, channel: Int) raises -> Float64:
    """Return the mean of one channel where alpha is not zero."""
    var total = 0.0
    var count = 0
    var pixels = image.width * image.height
    for index in range(pixels):
        if Int(image.pixels[index * 4 + 3]) > 0:
            total += Float64(Int(image.pixels[index * 4 + channel]))
            count += 1
    if count == 0:
        raise Error("image has no covered pixel")
    return total / Float64(count)


def _region(
    image: DecodedImage, x0: Int, y0: Int, x1: Int, y1: Int, channel: Int
) -> Float64:
    """Return the mean of one channel inside a pixel rectangle."""
    var total = 0.0
    var count = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            var index = (y * image.width + x) * 4 + channel
            total += Float64(Int(image.pixels[index]))
            count += 1
    return total / Float64(count)


def _mean_x(package: _Package, name: String) raises -> Float64:
    """Return the mean X of a node's first position accessor."""
    var nodes = package.doc.at(package.doc.root, "nodes")
    for index in range(package.doc.length(nodes)):
        var node = package.doc.item(nodes, index)
        if package.doc.text(package.doc.at(node, "name")) != name:
            continue
        var mesh = package.doc.item(
            package.doc.at(package.doc.root, "meshes"),
            Int(package.doc.text(package.doc.at(node, "mesh"))),
        )
        var primitive = package.doc.item(package.doc.at(mesh, "primitives"), 0)
        var attributes = package.doc.at(primitive, "attributes")
        var accessor_index = Int(
            package.doc.text(package.doc.at(attributes, "POSITION"))
        )
        var accessor = package.doc.item(
            package.doc.at(package.doc.root, "accessors"), accessor_index
        )
        var view = package.doc.item(
            package.doc.at(package.doc.root, "bufferViews"),
            Int(package.doc.text(package.doc.at(accessor, "bufferView"))),
        )
        var start = 0
        var offset = package.doc.get(view, "byteOffset")
        if offset != MISSING:
            start = Int(package.doc.text(offset))
        var count = Int(package.doc.text(package.doc.at(accessor, "count")))
        var total = 0.0
        for point in range(count):
            total += _f32(package.blob, start + point * 12)
        return total / Float64(count)
    raise Error("missing node " + name)


def _flat(doc: PyJson, node: Int, width: Int) raises -> List[Float64]:
    """Return a nested JSON array as one list."""
    var out = List[Float64]()
    for index in range(doc.length(node)):
        var row = doc.item(node, index)
        for axis in range(width):
            out.append(_num(doc, doc.item(row, axis)))
    return out^


def _ints(doc: PyJson, node: Int) raises -> List[Int]:
    """Return nested triangle indexes."""
    var out = List[Int]()
    for index in range(doc.length(node)):
        var row = doc.item(node, index)
        for axis in range(3):
            var item = doc.item(row, axis)
            if doc.kind(item) == PY_INT:
                out.append(Int(doc.text(item)))
            else:
                out.append(Int(_num(doc, item)))
    return out^


def _num(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number."""
    if doc.kind(node) == PY_FLOAT:
        return doc.number(node)
    if doc.kind(node) == PY_INT:
        return Float64(Int(doc.text(node)))
    raise Error("cube number is not numeric")


def _f32_store(mut out: List[UInt8], value: Float64):
    """Append one little-endian float32."""
    var bits = UInt32(bitcast[DType.uint32](Float32(value)))
    out.append(UInt8(bits & 0xFF))
    out.append(UInt8((bits >> 8) & 0xFF))
    out.append(UInt8((bits >> 16) & 0xFF))
    out.append(UInt8((bits >> 24) & 0xFF))


def _u32_store(mut out: List[UInt8], value: Int):
    """Append one little-endian uint32."""
    var bits = UInt32(value)
    out.append(UInt8(bits & 0xFF))
    out.append(UInt8((bits >> 8) & 0xFF))
    out.append(UInt8((bits >> 16) & 0xFF))
    out.append(UInt8((bits >> 24) & 0xFF))


def _u32(data: List[UInt8], at: Int) -> Int:
    """Return one little-endian uint32."""
    return (
        Int(data[at])
        | (Int(data[at + 1]) << 8)
        | (Int(data[at + 2]) << 16)
        | (Int(data[at + 3]) << 24)
    )


def _f32(data: List[UInt8], at: Int) -> Float64:
    """Return one little-endian float32 as float64."""
    var bits = (
        UInt32(data[at])
        | (UInt32(data[at + 1]) << 8)
        | (UInt32(data[at + 2]) << 16)
        | (UInt32(data[at + 3]) << 24)
    )
    return Float64(bitcast[DType.float32](bits))


def _comma(mut text: String, count: Int):
    """Insert a comma before the next JSON element."""
    if count > 0:
        text += ","


def _field(
    mut blob: List[UInt8],
    mut views: String,
    mut accessors: String,
    mut cursor: _Cursor,
    name: String,
    values: List[Float64],
    width: Int,
) -> String:
    """Append one float accessor and return its attribute entry."""
    var offset = len(blob)
    for index in range(len(values)):
        _f32_store(blob, values[index])
    _comma(views, cursor.views)
    _comma(accessors, cursor.accessors)
    views += (
        '{"buffer":0,"byteOffset":'
        + String(offset)
        + ',"byteLength":'
        + String(len(blob) - offset)
        + "}"
    )
    accessors += (
        '{"bufferView":'
        + String(cursor.views)
        + ',"componentType":5126,"count":'
        + String(len(values) // width)
        + ',"type":"VEC'
        + String(width)
        + '"}'
    )
    var accessor_index = cursor.accessors
    cursor.views += 1
    cursor.accessors += 1
    return '"' + name + '":' + String(accessor_index)


def _indices(
    mut blob: List[UInt8],
    mut views: String,
    mut accessors: String,
    mut cursor: _Cursor,
    values: List[Int],
) -> String:
    """Append one index accessor and return its index."""
    var offset = len(blob)
    for index in range(len(values)):
        _u32_store(blob, values[index])
    _comma(views, cursor.views)
    _comma(accessors, cursor.accessors)
    views += (
        '{"buffer":0,"byteOffset":'
        + String(offset)
        + ',"byteLength":'
        + String(len(blob) - offset)
        + "}"
    )
    accessors += (
        '{"bufferView":'
        + String(cursor.views)
        + ',"componentType":5125,"count":'
        + String(len(values))
        + ',"type":"SCALAR"}'
    )
    var accessor_index = cursor.accessors
    cursor.views += 1
    cursor.accessors += 1
    return String(accessor_index)


def main() raises:
    """Run the synthetic town package tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
