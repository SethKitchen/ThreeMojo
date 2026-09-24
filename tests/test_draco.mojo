# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`loaders.draco` against three.js's Draco decoder.

`assets/draco/` holds files written with Draco 1.5.7's encoder, built
from its source: sequential and Edgebreaker meshes at several speeds, with
seams, holes, handles, the valence traversal and metadata, and sequential
and KD-tree point clouds with every type. Some are changed by a byte to
reach a path the encoder never writes, and a few are made by hand: empty
geometry and bad counts. `three.json` holds what the WebAssembly decoder
that three.js 0.180 ships, Draco 1.5.6, gives for each, run in node as
`DRACOLoader`'s worker runs it: the points, the triangles, every
attribute as `Float32` for every point, and the geometry of
`DRACOLoader.parse`, or its error. Each value is compared by its bits.

The rest are small cases for paths no file reaches: bad bytes, and the
octahedron and prediction arithmetic at its edges.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from core.assets import Assets
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, UV1
from core.scene import Scene
from loaders.gltf import load_gltf
from loaders.draco import (
    DRACO_COMPRESSED,
    DRACO_CORNER,
    DRACO_INTEGER,
    DRACO_NORMALS,
    DRACO_POINT_CLOUD,
    DRACO_QUANTIZED,
    DRACO_RAW,
    DRACO_SEQUENTIAL,
    DRACO_TRIANGULAR_MESH,
    DRACO_VERTEX,
    DracoAttributeCoding,
    DracoElement,
    DracoEncoding,
    DracoGeometryType,
    decode_draco,
    draco_buffer_geometry,
    parse_draco,
    read_draco,
    read_sequential_index,
    sequential_index_width,
)
from loaders.draco_attributes import (
    DRACO_BOOL,
    DRACO_DIFFERENCE,
    DRACO_FLOAT32,
    DRACO_GENERIC,
    DRACO_INT8,
    DRACO_OCTAHEDRON,
    DRACO_PREDICTION_NONE,
    DRACO_TEX_COORDS_PORTABLE,
    DRACO_WRAP,
    DracoAttributeType,
    DracoDataType,
    DracoMeshData,
    DracoPrediction,
    DracoTransform,
    DracoPortable,
    Octahedron,
    PredictionScheme,
    PredictionTransform,
    _Positions,
    _abs_sum,
    _int_sqrt,
    octahedron_from_max,
)
from loaders.draco_buffer import (
    DirectBitDecoder,
    DracoBuffer,
    FoldedBitDecoder,
    RAnsBitDecoder,
    RAnsSymbolDecoder,
    decode_symbols,
    most_significant_bit,
    symbol_to_signed,
    to_int32,
    truncated_divide,
)
from loaders.draco_mesh import (
    DRACO_DEPTH_FIRST,
    DRACO_PREDICTION_DEGREE,
    DRACO_STANDARD_TRAVERSAL,
    DRACO_VALENCE_TRAVERSAL,
    NONE,
    DracoCornerTable,
    DracoTraversal,
    DracoTraversalMethod,
    _Edgebreaker,
    _Split,
    _Traversal,
)
from core.geometry_store import GeometryId
from loaders.json import JsonDocument, parse_json
from std.memory import bitcast
from std.pathlib import Path


def _bits(value: Float32) -> Int:
    """The bits of a float, to compare two floats exactly."""
    return Int(bitcast[DType.uint32](value))


struct _Reference(Movable):
    """`three.json`, and `three.bin`, which holds its arrays as 32-bit
    words: the JSON gives each array's first word and length."""

    var doc: JsonDocument
    var words: List[UInt8]

    def __init__(out self) raises:
        self.doc = parse_json(
            String(
                unsafe_from_utf8=Path("assets/draco/three.json").read_bytes()
            )
        )
        self.words = Path("assets/draco/three.bin").read_bytes()

    def file(self, name: String) raises -> Int:
        return self.doc.get(self.doc.root(), name)

    def array(self, node: Int) raises -> List[Int]:
        """The words an `[offset, length]` pair names."""
        var start = self.doc.integer(self.doc.at(node, 0))
        var count = self.doc.integer(self.doc.at(node, 1))
        var out = List[Int](capacity=count)
        for i in range(start, start + count):
            var at = 4 * i
            out.append(
                Int(self.words[at])
                | (Int(self.words[at + 1]) << 8)
                | (Int(self.words[at + 2]) << 16)
                | (Int(self.words[at + 3]) << 24)
            )
        return out^

    def attribute_bits(self, name: String, attribute: Int) raises -> List[Int]:
        var attributes = self.doc.get(self.file(name), "attributes")
        return self.array(
            self.doc.get(self.doc.at(attributes, attribute), "bits")
        )


def _assert_bits(want: List[Int], values: List[Float32]) raises:
    assert_equal(len(values), len(want))
    for i in range(len(values)):
        assert_equal(_bits(values[i]), want[i])


def _check_file(ref_: _Reference, name: String) raises:
    ref doc = ref_.doc
    var expected = ref_.file(name)
    var bytes = Path("assets/draco/" + name).read_bytes()
    if doc.has(expected, "error"):
        with assert_raises():
            _ = decode_draco(bytes)
        return
    var geometry = decode_draco(bytes)
    assert_equal(
        geometry.geometry_type.value, doc.integer(doc.get(expected, "type"))
    )
    assert_equal(geometry.points, doc.integer(doc.get(expected, "points")))
    if geometry.geometry_type == DRACO_TRIANGULAR_MESH:
        assert_equal(geometry.faces, ref_.array(doc.get(expected, "faces")))
    var attributes = doc.get(expected, "attributes")
    assert_equal(len(geometry.attributes), doc.length(attributes))
    for a in range(len(geometry.attributes)):
        var want = doc.at(attributes, a)
        ref attribute = geometry.attributes[a]
        assert_equal(
            attribute.attribute_type.value, doc.integer(doc.get(want, "type"))
        )
        assert_equal(
            attribute.data_type.value, doc.integer(doc.get(want, "data_type"))
        )
        assert_equal(
            attribute.components, doc.integer(doc.get(want, "components"))
        )
        assert_equal(
            attribute.normalized, doc.boolean(doc.get(want, "normalized"))
        )
        assert_equal(
            attribute.unique_id, doc.integer(doc.get(want, "unique_id"))
        )
        _assert_bits(
            ref_.array(doc.get(want, "bits")), geometry.float32_values(a)
        )
    var three = doc.get(expected, "three")
    var built = parse_draco(bytes)
    var names: List[String] = [
        String(POSITION),
        String(NORMAL),
        String(COLOR),
        String(UV),
    ]
    for n in names:
        assert_equal(built.has_attribute(n), doc.has(three, n))
        if not doc.has(three, n):
            continue
        var want = doc.get(three, n)
        ref view = built.attribute_view(n)
        assert_equal(view.item_size, doc.integer(doc.get(want, "components")))
        _assert_bits(ref_.array(doc.get(want, "bits")), view.data)


# A file three.js decodes and this port refuses: a triangle names a point
# the mesh does not have, which leaves three.js an index past its data.
comptime REFUSED: List[String] = ["seq_bad_index.drc"]


def test_files_match_three_js() raises:
    var reference = _Reference()
    ref doc = reference.doc
    for i in range(doc.length(doc.root())):
        var name = doc.key(doc.root(), i)
        if name in materialize[REFUSED]():
            with assert_raises(contains="a triangle names a missing point"):
                _ = decode_draco(Path("assets/draco/" + name).read_bytes())
            continue
        _check_file(reference, name)


def test_read_draco() raises:
    var geometry = read_draco("assets/draco/cube.drc")
    assert_true(geometry.has_attribute(String(POSITION)))
    with assert_raises():
        _ = read_draco("assets/draco/missing.drc")


def test_header_refusals() raises:
    var cube = Path("assets/draco/cube.drc").read_bytes()
    with assert_raises(contains="the file is not Draco"):
        _ = decode_draco([UInt8(68), UInt8(82)])
    var bad = cube.copy()
    bad[6] = 3
    with assert_raises(contains="bitstream 2.3 is not supported"):
        _ = decode_draco(bad)
    bad = cube.copy()
    bad[7] = 7
    with assert_raises(contains="a geometry type is not known"):
        _ = decode_draco(bad)
    bad = cube.copy()
    bad[8] = 2
    with assert_raises(contains="an encoding is not known"):
        _ = decode_draco(bad)


def test_geometry_lookups() raises:
    var geometry = decode_draco(Path("assets/draco/grid.drc").read_bytes())
    assert_equal(geometry.unique_attribute(3), 3)
    assert_equal(geometry.unique_attribute(99), NONE)
    var empty_mesh = decode_draco(
        Path("assets/draco/seq_empty.drc").read_bytes()
    )
    assert_equal(empty_mesh.unique_attribute(0), NONE)
    var empty = draco_buffer_geometry(geometry, [], [], True)
    assert_false(empty.has_attribute(String(POSITION)))
    var names: List[String] = [String(COLOR)]
    var ids: List[Int] = [geometry.named_attribute(DracoAttributeType(2))]
    var linear = draco_buffer_geometry(geometry, names, ids, False)
    ref colors = linear.attribute_view(String(COLOR))
    var raw = geometry.float32_values(ids[0])
    for i in range(len(raw)):
        assert_equal(colors.data[i], raw[i])


def test_types() raises:
    assert_true(DRACO_POINT_CLOUD.is_valid())
    assert_false(DracoGeometryType(2).is_valid())
    assert_true(DRACO_COMPRESSED.is_valid())
    assert_false(DracoEncoding(2).is_valid())
    assert_true(DRACO_NORMALS.is_valid())
    assert_false(DracoAttributeCoding(4).is_valid())
    assert_true(DRACO_CORNER.is_valid())
    assert_false(DracoElement(2).is_valid())
    assert_true(DRACO_BOOL.is_valid())
    assert_false(DracoDataType(12).is_valid())
    assert_true(DRACO_GENERIC.is_valid())
    assert_false(DracoAttributeType(5).is_valid())
    assert_true(DRACO_PREDICTION_NONE.is_valid())
    assert_false(DracoPrediction(7).is_valid())
    assert_true(DRACO_WRAP.is_valid())
    assert_false(DracoTransform(4).is_valid())
    assert_true(DRACO_VALENCE_TRAVERSAL.is_valid())
    assert_false(DracoTraversal(1).is_valid())
    assert_true(DRACO_PREDICTION_DEGREE.is_valid())
    assert_false(DracoTraversalMethod(2).is_valid())
    assert_true(DRACO_FLOAT32.is_valid() and not DRACO_FLOAT32.is_integral())
    assert_true(DRACO_INT8.is_integral())


def test_sequential_index_widths() raises:
    assert_equal(sequential_index_width(255), 1)
    assert_equal(sequential_index_width(256), 2)
    assert_equal(sequential_index_width(65536), 0)
    assert_equal(sequential_index_width(1 << 21), 4)
    var buffer = DracoBuffer([UInt8(0x80), UInt8(0x01), UInt8(7)])
    assert_equal(read_sequential_index(buffer, 0), 128)
    assert_equal(read_sequential_index(buffer, 1), 7)


def test_buffer_numbers() raises:
    var buffer = DracoBuffer(
        [UInt8(0xFF), UInt8(0xFE), UInt8(0x00), UInt8(0x00), UInt8(0x80)]
    )
    assert_equal(buffer.i8(), -1)
    assert_equal(buffer.read_unsigned(0), 0)
    assert_equal(buffer.i32(), to_int32(0x800000FE))
    with assert_raises(contains="the file ends early"):
        _ = buffer.u8()
    var long = DracoBuffer(List[UInt8](length=6, fill=0x80))
    with assert_raises(contains="a varint is too long"):
        _ = long.varint32()
    var wide = List[UInt8](length=9, fill=0xFF)
    wide.append(0x7F)
    var widest = DracoBuffer(wide^)
    assert_equal(widest.varint64(), -1)
    var signed = DracoBuffer([UInt8(3)])
    assert_equal(signed.signed_varint32(), -2)
    assert_equal(symbol_to_signed(4), 2)
    assert_equal(most_significant_bit(1), 0)
    assert_equal(most_significant_bit(0x80000000), 31)
    assert_equal(truncated_divide(-7, 2), -3)
    assert_equal(truncated_divide(7, -2), -3)
    assert_equal(truncated_divide(7, 2), 3)


def test_buffer_bits() raises:
    var buffer = DracoBuffer([UInt8(0b10110101)])
    _ = buffer.start_bits(False)
    assert_equal(buffer.bits(0), 0)
    assert_equal(buffer.bits(3), 0b101)
    assert_equal(buffer.bits(8), 0b10110)
    with assert_raises(contains="wider than 32 bits"):
        _ = buffer.bits(33)
    buffer.end_bits()
    assert_equal(buffer.pos, 1)


def test_rans_symbols() raises:
    # A table of no symbols is valid; a tag stream needs one.
    var empty = DracoBuffer([UInt8(0), UInt8(0)])
    var table = RAnsSymbolDecoder(5)
    table.create(empty)
    assert_equal(table.count(), 0)
    var tagged = DracoBuffer([UInt8(0), UInt8(0), UInt8(1), UInt8(0)])
    with assert_raises(contains="a tag table is empty"):
        _ = decode_symbols(tagged, 3, 1)
    with assert_raises(contains="a symbol coding is not known"):
        var other = DracoBuffer([UInt8(2)])
        _ = decode_symbols(other, 1, 1)
    with assert_raises(contains="a symbol width is not from 1 to 18"):
        var other = DracoBuffer([UInt8(1), UInt8(19)])
        _ = decode_symbols(other, 1, 1)
    # Two symbols of half the probability each, read past the end of
    # their bytes.
    var two = DracoBuffer(
        [
            UInt8(1),
            UInt8(1),
            UInt8(2),
            UInt8(0x01),
            UInt8(0x20),
            UInt8(0x01),
            UInt8(0x20),
            UInt8(1),
            UInt8(0),
        ]
    )
    var values = decode_symbols(two, 40, 1)
    assert_equal(len(values), 40)
    assert_equal(values[39], 0)


def test_bit_decoders() raises:
    # A binary rANS stream of one byte, read far past its end.
    var buffer = DracoBuffer([UInt8(128), UInt8(1), UInt8(0x10)])
    var bits = RAnsBitDecoder()
    bits.start(buffer)
    assert_equal(bits.bits(0), 0)
    for _ in range(40):
        _ = bits.bit()
    var direct = DirectBitDecoder()
    var words = DracoBuffer(
        [
            UInt8(4),
            UInt8(0),
            UInt8(0),
            UInt8(0),
            UInt8(1),
            UInt8(0),
            UInt8(0),
            UInt8(0x80),
        ]
    )
    direct.start(words)
    assert_true(direct.bit())
    assert_equal(direct.bits(31), 1)
    assert_false(direct.bit())
    with assert_raises(contains="the bits run out"):
        _ = direct.bits(3)
    var halves = DirectBitDecoder()
    var two = DracoBuffer(
        [
            UInt8(4),
            UInt8(0),
            UInt8(0),
            UInt8(0),
            UInt8(0),
            UInt8(0),
            UInt8(0),
            UInt8(0),
        ]
    )
    halves.start(two)
    _ = halves.bits(20)
    with assert_raises(contains="the bits run out"):
        _ = halves.bits(20)
    with assert_raises(contains="a bit block size is not valid"):
        var bad = DracoBuffer([UInt8(3), UInt8(0), UInt8(0), UInt8(0)])
        var decoder = DirectBitDecoder()
        decoder.start(bad)
    var folded = FoldedBitDecoder()
    assert_equal(folded.bits(0), 0)


def test_corner_table() raises:
    var table = DracoCornerTable(1)
    assert_equal(table.opposite(NONE), NONE)
    assert_equal(table.vertex(NONE), NONE)
    with assert_raises(contains="a vertex that does not exist"):
        _ = table.left_most(0)


def test_valence_symbols() raises:
    var traversal = _Traversal(
        DRACO_VALENCE_TRAVERSAL, DracoBuffer(List[UInt8]())
    )
    traversal.context = 0
    traversal.context_symbols.append([9])
    traversal.context_left.append(1)
    assert_equal(traversal.symbol(), 8)
    assert_equal(traversal.symbol(), 8)


def test_split_order() raises:
    var decoder = _Edgebreaker(1, 3, DRACO_STANDARD_TRAVERSAL, 0)
    decoder.splits.append(_Split(0, 5))
    var found = decoder.split_at(2)
    assert_true(found[0])
    assert_equal(found[2], NONE)


def test_octahedron_edges() raises:
    var o = Octahedron(4)
    assert_equal(o.max_value, 14)
    assert_equal(o.center, 7)
    var a = o.canonicalize_coords(0, 0)
    assert_equal(a[0], 14)
    assert_equal(a[1], 14)
    var b = o.canonicalize_coords(0, 10)
    assert_equal(b[1], 4)
    var c = o.canonicalize_coords(14, 3)
    assert_equal(c[1], 11)
    var d = o.canonicalize_coords(3, 14)
    assert_equal(d[0], 11)
    var e = o.canonicalize_coords(10, 0)
    assert_equal(e[0], 4)
    var f = o.canonicalize_coords(0, 14)
    assert_equal(f[0], 14)
    var g = o.canonicalize_coords(14, 0)
    assert_equal(g[1], 14)
    var zero = o.canonicalize_vector(0, 0, 0)
    assert_equal(zero[0], 7)
    assert_equal(o.mod_max(-9), 6)
    with assert_raises(contains="normal bits are not from 2 to 30"):
        _ = Octahedron(31)
    with assert_raises(contains="a normal range is even"):
        _ = octahedron_from_max(16)


def test_prediction_arithmetic() raises:
    assert_equal(_abs_sum([0x7FFFFFFFFFFFFFFF, 5, 0]), 0x7FFFFFFFFFFFFFFF)
    assert_equal(_abs_sum([-0x7FFFFFFFFFFFFFFF - 1, 0, 0]), 0x7FFFFFFFFFFFFFFF)
    assert_equal(_int_sqrt(0), 0)
    assert_equal(_int_sqrt(17), 4)


def test_no_orientations() raises:
    var buffer = DracoBuffer(
        [
            UInt8(0),
            UInt8(0),
            UInt8(0),
            UInt8(0),
            UInt8(128),
            UInt8(1),
            UInt8(0),
            UInt8(0),
            UInt8(0),
            UInt8(0),
            UInt8(0),
            UInt8(9),
            UInt8(0),
            UInt8(0),
            UInt8(0),
        ]
    )
    var scheme = PredictionScheme(
        DRACO_TEX_COORDS_PORTABLE, PredictionTransform(DRACO_WRAP, 2)
    )
    scheme.read(buffer, 0)
    assert_equal(len(scheme.orientations), 0)
    assert_equal(scheme.transform.max_value, 9)


def test_tex_coords_on_a_point() raises:
    # Two corners of a triangle at one quantized position: the texture
    # coordinate prediction falls back to the next corner's value.
    var table = DracoCornerTable(1)
    table.corner_to_vertex = [0, 1, 2]
    table.vertex_corners = [0, 1, 2]
    var data = DracoMeshData(table^, [0, 1, 2], [0, 1, 2])
    var positions = _Positions(
        DracoPortable([5, 5, 5, 5, 5, 5, 9, 1, 4], 3), [0, 1, 2], [0, 1, 2]
    )
    var scheme = PredictionScheme(
        DRACO_TEX_COORDS_PORTABLE, PredictionTransform(DRACO_WRAP, 2)
    )
    var predicted = scheme._tex_coord(2, [3, 4, 7, 8, 0, 0], data, positions)
    assert_equal(predicted[0], 3)
    assert_equal(predicted[1], 4)


# --- glTF's KHR_draco_mesh_compression ----------------------------------------


def _gltf(
    size: Int, accessors: String, attributes: String, ids: String
) -> String:
    """A glTF document of one primitive whose Draco data is the whole
    binary chunk, `size` bytes, with its indices in the last accessor."""
    return (
        '{"asset":{"version":"2.0"},'
        + '"extensionsUsed":["KHR_draco_mesh_compression"],'
        + '"extensionsRequired":["KHR_draco_mesh_compression"],'
        + '"buffers":[{"byteLength":'
        + String(size)
        + '}],"bufferViews":[{"buffer":0,"byteLength":'
        + String(size)
        + '}],"accessors":['
        + accessors
        + '],"meshes":[{"primitives":[{"attributes":{'
        + attributes
        + '},"indices":0,"extensions":{"KHR_draco_mesh_compression":'
        + '{"bufferView":0,"attributes":{'
        + ids
        + '}}}}]}],"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}],'
        + '"scene":0}'
    )


def _accessor(component: Int, kind: String, normalized: Bool = False) -> String:
    """An accessor with no buffer view, as a Draco primitive's are."""
    var text = (
        '{"componentType":'
        + String(component)
        + ',"count":3,"type":"'
        + kind
        + '"'
    )
    if normalized:
        text += ',"normalized":true'
    return text + "}"


def _draco_primitive(
    file: String, accessors: String, attributes: String, ids: String
) raises -> Assets:
    """Load a document of one Draco primitive; its geometry is the
    first in the assets."""
    var bytes = Path("assets/draco/" + file).read_bytes()
    var text = _gltf(len(bytes), accessors, attributes, ids)
    var scene = Scene()
    var assets = Assets()
    _ = load_gltf(text, bytes, "", scene, assets)
    return assets^


def _gltf_refusal(
    file: String, accessors: String, attributes: String, ids: String
) raises -> String:
    try:
        _ = _draco_primitive(file, accessors, attributes, ids)
    except reason:
        return String(reason)
    return String()


def test_a_gltf_primitive_reads_its_draco_data() raises:
    var reference = _Reference()
    var accessors = (
        _accessor(5125, "SCALAR")
        + ","
        + _accessor(5126, "VEC3")
        + ","
        + _accessor(5126, "VEC3")
        + ","
        + _accessor(5126, "VEC2")
        + ","
        + _accessor(5121, "VEC3", True)
        + ","
        + _accessor(5126, "VEC2")
    )
    var assets = _draco_primitive(
        "grid.drc",
        accessors,
        '"POSITION":1,"NORMAL":2,"TEXCOORD_0":3,"COLOR_0":4,"TEXCOORD_1":5',
        '"POSITION":0,"NORMAL":1,"TEXCOORD_0":2,"COLOR_0":3',
    )
    ref geometry = assets.geometries.get(GeometryId(0))
    _assert_bits(
        reference.attribute_bits("grid.drc", 0),
        geometry.attribute_view(POSITION).data,
    )
    _assert_bits(
        reference.attribute_bits("grid.drc", 1),
        geometry.attribute_view(NORMAL).data,
    )
    _assert_bits(
        reference.attribute_bits("grid.drc", 2),
        geometry.attribute_view(UV).data,
    )
    # A normalized byte is the byte over 255, the float Draco gives.
    _assert_bits(
        reference.attribute_bits("grid.drc", 3),
        geometry.attribute_view(COLOR).data,
    )
    # TEXCOORD_1 is not in the Draco data: its accessor has no view.
    ref second = geometry.attribute_view(UV1).data
    assert_equal(len(second), 6)
    assert_equal(second[5], 0)
    # The triangles are Draco's, not the accessor's.
    assert_equal(
        geometry.index,
        reference.array(reference.doc.get(reference.file("grid.drc"), "faces")),
    )


def test_a_draco_attribute_reads_at_its_accessors_type() raises:
    var grid = decode_draco(Path("assets/draco/grid.drc").read_bytes())
    var raw = grid.integer_values(3, DracoDataType(2))
    for component in [5123, 5125]:
        var accessors = (
            _accessor(5125, "SCALAR")
            + ","
            + _accessor(5126, "VEC3")
            + ","
            + _accessor(component, "VEC3", True)
        )
        var assets = _draco_primitive(
            "grid.drc",
            accessors,
            '"POSITION":1,"COLOR_0":2',
            '"POSITION":0,"COLOR_0":3',
        )
        ref geometry = assets.geometries.get(GeometryId(0))
        ref colors = geometry.attribute_view(COLOR).data
        for i in range(len(raw)):
            var expected = Float32(raw[i])
            if component == 5123:
                expected /= 65535
            assert_equal(colors[i], expected)
    # A point cloud: its signed bytes as shorts, its unsigned bytes as
    # normalized shorts, its integers as floats, and the accessor's
    # indices, since a point cloud has no triangles.
    var reference = _Reference()
    var points = decode_draco(Path("assets/draco/points.drc").read_bytes())
    var accessors = (
        _accessor(5125, "SCALAR")
        + ","
        + _accessor(5126, "VEC3")
        + ","
        + _accessor(5126, "VEC2")
        + ","
        + _accessor(5122, "VEC2")
        + ","
        + _accessor(5122, "VEC4", True)
    )
    var cloud_assets = _draco_primitive(
        "points.drc",
        accessors,
        '"POSITION":1,"TEXCOORD_0":2,"TEXCOORD_1":3,"COLOR_0":4',
        '"POSITION":0,"TEXCOORD_0":8,"TEXCOORD_1":4,"COLOR_0":1',
    )
    ref cloud = cloud_assets.geometries.get(GeometryId(0))
    _assert_bits(
        reference.attribute_bits("points.drc", 8),
        cloud.attribute_view(UV).data,
    )
    _assert_bits(
        reference.attribute_bits("points.drc", 4),
        cloud.attribute_view(UV1).data,
    )
    var bytes = points.integer_values(1, DracoDataType(2))
    ref colors = cloud.attribute_view(COLOR).data
    for i in range(len(bytes)):
        assert_equal(colors[i], Float32(bytes[i]) / 32767)
    assert_equal(len(cloud.index), 3)


def test_bad_draco_primitives_are_refused() raises:
    var two = _accessor(5125, "SCALAR") + "," + _accessor(5126, "VEC3")
    # A Booleans attribute reads as bytes, then is not a color.
    assert_true(
        "COLOR_0 must be"
        in _gltf_refusal(
            "points_wide.drc",
            two + "," + _accessor(5121, "SCALAR"),
            '"POSITION":1,"COLOR_0":2',
            '"POSITION":0,"COLOR_0":1',
        )
    )
    assert_true(
        "a float attribute is read as integers"
        in _gltf_refusal(
            "grid.drc",
            two + "," + _accessor(5122, "VEC3"),
            '"POSITION":1,"NORMAL":2',
            '"POSITION":0,"NORMAL":1',
        )
    )
    assert_true(
        "does not fit"
        in _gltf_refusal(
            "grid.drc",
            two + "," + _accessor(5120, "VEC2"),
            '"POSITION":1,"TEXCOORD_1":2',
            '"POSITION":0,"TEXCOORD_1":4',
        )
    )
    assert_true(
        "not in the Draco data"
        in _gltf_refusal("grid.drc", two, '"POSITION":1', '"POSITION":9')
    )
    assert_true(
        "component type that is not known"
        in _gltf_refusal(
            "grid.drc",
            two + "," + _accessor(5124, "VEC3"),
            '"POSITION":1,"COLOR_0":2',
            '"POSITION":0,"COLOR_0":3',
        )
    )
    # No points: no values, and then no color of one component.
    assert_true(
        "COLOR_0 must be"
        in _gltf_refusal(
            "empty_kd.drc",
            two + "," + _accessor(5120, "SCALAR"),
            '"POSITION":1,"COLOR_0":2',
            '"POSITION":0,"COLOR_0":1',
        )
    )
    var empty = decode_draco(
        Path("assets/draco/empty_raw_points.drc").read_bytes()
    )
    assert_equal(len(empty.integer_values(0, DracoDataType(2))), 0)
    # With no Draco attributes, every attribute is its accessor's.
    var plain = _draco_primitive("grid.drc", two, '"POSITION":1', "")
    assert_equal(
        plain.geometries.get(GeometryId(0)).attribute_view(POSITION).data[0],
        0,
    )
    var bytes = Path("assets/draco/grid.drc").read_bytes()
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains="needs attributes"):
        _ = load_gltf(
            '{"asset":{"version":"2.0"},"buffers":[{"byteLength":'
            + String(len(bytes))
            + '}],"bufferViews":[{"buffer":0,"byteLength":0}],'
            + '"accessors":['
            + two
            + '],"meshes":[{"primitives":[{"attributes":{"POSITION":1},'
            + '"extensions":{"KHR_draco_mesh_compression":{"bufferView":0}}}]}]}',
            bytes,
            "",
            scene,
            assets,
        )
    with assert_raises(contains="needs attributes"):
        _ = load_gltf(
            '{"asset":{"version":"2.0"},"buffers":[{"byteLength":'
            + String(len(bytes))
            + '}],"bufferViews":[{"buffer":0,"byteLength":0}],'
            + '"accessors":['
            + two
            + '],"meshes":[{"primitives":[{"attributes":{"POSITION":1},'
            + '"extensions":{"KHR_draco_mesh_compression":{"bufferView":0,'
            + '"attributes":1}}}]}]}',
            bytes,
            "",
            scene,
            assets,
        )
    with assert_raises(contains="the file is not Draco"):
        _ = load_gltf(
            '{"asset":{"version":"2.0"},"buffers":[{"byteLength":'
            + String(len(bytes))
            + '}],"bufferViews":[{"buffer":0,"byteLength":0}],'
            + '"accessors":['
            + two
            + '],"meshes":[{"primitives":[{"attributes":{"POSITION":1},'
            + '"extensions":{"KHR_draco_mesh_compression":{"bufferView":0,'
            + '"attributes":{}}}}]}]}',
            bytes,
            "",
            scene,
            assets,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
