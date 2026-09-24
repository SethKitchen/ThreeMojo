# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`exporters.draco` against three.js's `DRACOExporter`.

`assets/draco/export/three_export.mjs` builds meshes and point clouds in
three.js 0.180 and exports each with a range of options, with draco3d
1.5.6's encoder, in node. `three.json` and `three.bin` hold the
geometries and the bytes of each file, or three.js's error. Each export
here must give the same bytes, or refuse the same geometry. The suite
checks a representative subset of the cases; `make draco-export-check`
checks them all. The files of the smaller geometries are then read back
with `loaders.draco` and compared with their geometry.

The rest are small cases for paths no export reaches: bad options, bad
geometry, and the writers and coders at their edges.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, BufferGeometry
from exporters.draco import (
    DRACO_EXPORT_MESH,
    DRACO_EXPORT_POINTS,
    DRACO_MESH_EDGEBREAKER_ENCODING,
    DRACO_MESH_SEQUENTIAL_ENCODING,
    DracoEncoderMethod,
    DracoExportOptions,
    DracoObjectKind,
    _srgb_colors,
    export_draco,
    write_draco,
    write_sequential_index,
)
from exporters.draco_log2 import musl_log2
from exporters.draco_predict import _abs_sum, _int_sqrt, wasm_i32
from exporters.draco_writer import (
    DRACO_RAW_SYMBOLS,
    DRACO_TAGGED_SYMBOLS,
    DracoSymbolCoding,
    DracoWriter,
    EntropyData,
    binary_entropy,
    encode_symbols,
    encode_symbols_with,
    entropy_data_bits,
)
from loaders.draco import (
    DRACO_TRIANGULAR_MESH,
    decode_draco,
    read_draco,
    read_sequential_index,
)
from loaders.draco_attributes import DracoAttributeType
from loaders.draco_buffer import DracoBuffer, decode_symbols
from loaders.json import JsonDocument, parse_json
from std.math import inf, isnan, nan, sqrt
from std.memory import bitcast
from std.pathlib import Path

comptime _DIR = "assets/draco/export/"


struct _Reference(Movable):
    """`three.json`, and `three.bin`, which holds 32-bit words: the input
    arrays one word a value, and each export's bytes."""

    var doc: JsonDocument
    var words: List[UInt8]

    def __init__(out self) raises:
        self.doc = parse_json(
            String(unsafe_from_utf8=Path(_DIR + "three.json").read_bytes())
        )
        self.words = Path(_DIR + "three.bin").read_bytes()

    def word(self, i: Int) -> Int:
        var at = 4 * i
        return (
            Int(self.words[at])
            | (Int(self.words[at + 1]) << 8)
            | (Int(self.words[at + 2]) << 16)
            | (Int(self.words[at + 3]) << 24)
        )

    def cases(self) raises -> Int:
        return self.doc.get(self.doc.root(), "cases")

    def geometry(
        self, name: String
    ) raises -> Tuple[BufferGeometry, DracoObjectKind]:
        ref doc = self.doc
        var g = doc.get(doc.get(doc.root(), "geometries"), name)
        var kind = DRACO_EXPORT_MESH
        if doc.string(doc.get(g, "kind")) == "points":
            kind = DRACO_EXPORT_POINTS
        var geometry = BufferGeometry()
        var attributes = doc.get(g, "attributes")
        for a in range(doc.length(attributes)):
            var key = doc.key(attributes, a)
            var entry = doc.get(attributes, key)
            var w = doc.get(entry, "words")
            var start = doc.integer(doc.at(w, 0))
            var values = List[Float32]()
            for i in range(start, start + doc.integer(doc.at(w, 1))):
                values.append(bitcast[DType.float32](UInt32(self.word(i))))
            geometry.set_attribute(
                key,
                BufferAttribute(
                    values^, doc.integer(doc.get(entry, "itemSize"))
                ),
            )
        if doc.has(g, "index"):
            var w = doc.get(g, "index")
            var start = doc.integer(doc.at(w, 0))
            var index = List[Int]()
            for i in range(start, start + doc.integer(doc.at(w, 1))):
                index.append(self.word(i))
            geometry.set_index(index^)
        return (geometry^, kind)

    def options(self, entry: Int) raises -> DracoExportOptions:
        ref doc = self.doc
        var o = doc.get(entry, "options")
        var options = DracoExportOptions()
        if doc.has(o, "encodeSpeed"):
            options.encode_speed = doc.integer(doc.get(o, "encodeSpeed"))
        if doc.has(o, "decodeSpeed"):
            options.decode_speed = doc.integer(doc.get(o, "decodeSpeed"))
        if doc.has(o, "encoderMethod"):
            options.encoder_method = DracoEncoderMethod(
                doc.integer(doc.get(o, "encoderMethod"))
            )
        if doc.has(o, "exportUvs"):
            options.export_uvs = doc.boolean(doc.get(o, "exportUvs"))
        if doc.has(o, "exportNormals"):
            options.export_normals = doc.boolean(doc.get(o, "exportNormals"))
        if doc.has(o, "exportColor"):
            options.export_color = doc.boolean(doc.get(o, "exportColor"))
        if doc.has(o, "quantization"):
            var q = doc.get(o, "quantization")
            options.quantization.clear()
            for i in range(doc.length(q)):
                options.quantization.append(doc.integer(doc.at(q, i)))
        return options^

    def expected(self, entry: Int) raises -> List[UInt8]:
        ref doc = self.doc
        var w = doc.get(entry, "bytes")
        var start = doc.integer(doc.at(w, 0))
        var out = List[UInt8]()
        for i in range(doc.integer(doc.at(w, 1))):
            out.append(self.words[4 * start + i])
        return out^


# The geometries of many triangles or points, whose cases the suite takes
# only a few of: the index of each case within its geometry. Every case
# of the other geometries is in the suite.
comptime _BIG: List[String] = ["knot", "grid", "sphere", "points"]
comptime _BIG_CASES: List[List[Int]] = [
    # The standard traversal; the valence traversal with the best order,
    # the constrained multi-parallelogram and the geometric normals; the
    # valence traversal with the texture coordinates and colors.
    [0, 1, 2],
    # A coarse quantization with the valence traversal.
    [5],
    # The default, and speed 0 with its best order.
    [0, 1],
    # The KD-tree at level 6, at level 5 with colors, at level 6 with two
    # bits that run out before the splits end, and a sequence.
    [1, 11, 16, 19],
]


def suite_cases(reference: _Reference, round_trip: Bool) raises -> List[Int]:
    """The cases the suite checks: a representative subset of the 323.

    `tools/draco_export_check.mojo` checks them all. The round trip leaves
    out the big geometries, whose search for each triangle is quadratic.
    """
    ref doc = reference.doc
    var cases = reference.cases()
    var out = List[Int]()
    var seen = List[Int](length=len(materialize[_BIG]()), fill=0)
    for k in range(doc.length(cases)):
        var entry = doc.at(cases, k)
        var name = doc.string(doc.get(entry, "geometry"))
        var big = -1
        for b in range(len(materialize[_BIG]())):
            if materialize[_BIG]()[b] == name:
                big = b
        if big == -1:
            out.append(entry)
            continue
        var index = seen[big]
        seen[big] += 1
        if not round_trip and index in materialize[_BIG_CASES]()[big]:
            out.append(entry)
    return out^


def test_exports_match_three_js() raises:
    var reference = _Reference()
    ref doc = reference.doc
    for entry in suite_cases(reference, False):
        var built = reference.geometry(doc.string(doc.get(entry, "geometry")))
        var options = reference.options(entry)
        if doc.has(entry, "error"):
            with assert_raises():
                _ = export_draco(built[0], built[1], options)
            continue
        assert_equal(
            export_draco(built[0], built[1], options), reference.expected(entry)
        )


def _range(values: List[Float32], components: Int) -> Float64:
    """Draco's quantization range: the largest spread of any component."""
    var widest = 0.0
    var count = len(values) // components
    for c in range(components):
        var low = Float64(values[c])
        var high = low
        for v in range(count):
            low = min(low, Float64(values[v * components + c]))
            high = max(high, Float64(values[v * components + c]))
        widest = max(widest, high - low)
    if widest == 0:
        return 1.0
    return widest


struct _Expected(Movable):
    """The attributes an export writes, as the decoder should read them."""

    var names: List[String]
    var components: List[Int]
    var values: List[List[Float32]]
    var tolerance: List[Float64]
    var normal: List[Bool]

    def __init__(
        out self,
        geometry: BufferGeometry,
        kind: DracoObjectKind,
        options: DracoExportOptions,
    ) raises:
        self.names = List[String]()
        self.components = List[Int]()
        self.values = List[List[Float32]]()
        self.tolerance = List[Float64]()
        self.normal = List[Bool]()
        var names: List[String] = [String(POSITION)]
        var types: List[Int] = [0]
        if kind == DRACO_EXPORT_MESH:
            if options.export_normals and geometry.has_attribute(NORMAL):
                names.append(String(NORMAL))
                types.append(1)
            if options.export_uvs and geometry.has_attribute(UV):
                names.append(String(UV))
                types.append(3)
        if options.export_color and geometry.has_attribute(COLOR):
            names.append(String(COLOR))
            types.append(2)
        for i in range(len(names)):
            ref view = geometry.attribute_view(names[i])
            var values = view.packed()
            if names[i] == COLOR:
                values = _srgb_colors(values, view.item_size)
            var bits = options.bits(DracoAttributeType(types[i]))
            var tolerance = 0.0
            if bits > 0:
                var step = _range(values, view.item_size) / Float64(
                    (1 << bits) - 1
                )
                tolerance = 0.51 * step + 1e-6
            if names[i] == NORMAL and bits > 0:
                # The least cosine between a normal and its folded copy.
                tolerance = 1.0 - 16.0 / Float64(1 << bits)
            self.names.append(names[i])
            self.components.append(view.item_size)
            self.values.append(values^)
            self.tolerance.append(tolerance)
            self.normal.append(names[i] == NORMAL and bits > 0)

    def matches(
        self, arrays: List[List[Float32]], point: Int, vertex: Int
    ) -> Bool:
        """True if decoded point `point` holds the values of vertex
        `vertex`, within the quantization."""
        for a in range(len(self.names)):
            var n = self.components[a]
            if self.normal[a]:
                var dot = 0.0
                var length = 0.0
                for c in range(3):
                    var want = Float64(self.values[a][vertex * 3 + c])
                    dot += want * Float64(arrays[a][point * 3 + c])
                    length += want * want
                if length > 1e-12 and dot / sqrt(length) < self.tolerance[a]:
                    return False
                continue
            for c in range(n):
                var want = Float64(self.values[a][vertex * n + c])
                var got = Float64(arrays[a][point * n + c])
                if abs(want - got) > self.tolerance[a]:
                    return False
        return True


def _has_nan(geometry: BufferGeometry) raises -> Bool:
    for v in geometry.attribute_view(POSITION).packed():
        if isnan(v):
            return True
    return False


def _check_round_trip(
    geometry: BufferGeometry,
    kind: DracoObjectKind,
    options: DracoExportOptions,
    bytes: List[UInt8],
) raises:
    """Read an export back, and find the geometry's corners in it."""
    var decoded = decode_draco(bytes)
    var expected = _Expected(geometry, kind, options)
    assert_equal(len(decoded.attributes), len(expected.names))
    var arrays = List[List[Float32]]()
    for a in range(len(expected.names)):
        assert_equal(decoded.attributes[a].components, expected.components[a])
        arrays.append(decoded.float32_values(a))
    var vertices = geometry.attribute_view(POSITION).count()
    if kind == DRACO_EXPORT_POINTS:
        for p in range(decoded.points):
            var found = False
            for v in range(vertices):
                if expected.matches(arrays, p, v):
                    found = True
                    break
            assert_true(found)
        for v in range(vertices):
            var found = False
            for p in range(decoded.points):
                if expected.matches(arrays, p, v):
                    found = True
                    break
            assert_true(found)
        return
    assert_true(decoded.geometry_type == DRACO_TRIANGULAR_MESH)
    var index = geometry.index.copy()
    ref positions = expected.values[0]
    var faces = len(index) // 3
    var decoded_faces = len(decoded.faces) // 3
    for f in range(decoded_faces):
        var found = False
        for g in range(faces):
            for r in range(3):
                var all = True
                for k in range(3):
                    if not expected.matches(
                        arrays,
                        decoded.faces[3 * f + k],
                        index[3 * g + (k + r) % 3],
                    ):
                        all = False
                        break
                if all:
                    found = True
                    break
            if found:
                break
        assert_true(found)
    # Each triangle with three distinct positions is written.
    for g in range(faces):
        var a = index[3 * g]
        var b = index[3 * g + 1]
        var c = index[3 * g + 2]
        if (
            _same(positions, a, b)
            or _same(positions, a, c)
            or _same(positions, b, c)
        ):
            continue
        var found = False
        for f in range(decoded_faces):
            for r in range(3):
                var all = True
                for k in range(3):
                    if not expected.matches(
                        arrays,
                        decoded.faces[3 * f + (k + r) % 3],
                        index[3 * g + k],
                    ):
                        all = False
                        break
                if all:
                    found = True
                    break
            if found:
                break
        assert_true(found)


def _same(positions: List[Float32], a: Int, b: Int) -> Bool:
    """True if two vertices have the same position, bit for bit."""
    for c in range(3):
        if bitcast[DType.uint32](positions[3 * a + c]) != bitcast[DType.uint32](
            positions[3 * b + c]
        ):
            return False
    return True


def test_exports_round_trip() raises:
    var reference = _Reference()
    ref doc = reference.doc
    for entry in suite_cases(reference, True):
        if doc.has(entry, "error"):
            continue
        var built = reference.geometry(doc.string(doc.get(entry, "geometry")))
        if _has_nan(built[0]):
            continue
        var options = reference.options(entry)
        _check_round_trip(
            built[0], built[1], options, reference.expected(entry)
        )


def _triangles() raises -> BufferGeometry:
    """Two triangles of a square, with normals, uvs and colors."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION,
        BufferAttribute([0.0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0], 3),
    )
    geometry.set_attribute(
        NORMAL, BufferAttribute([0.0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1], 3)
    )
    geometry.set_attribute(UV, BufferAttribute([0.0, 0, 1, 0, 0, 1, 1, 1], 2))
    geometry.set_attribute(
        COLOR,
        BufferAttribute(
            [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 1, 1, 1], 3
        ),
    )
    geometry.set_index([0, 1, 2, 2, 1, 3])
    return geometry^


def test_defaults_are_three_js() raises:
    var options = DracoExportOptions()
    assert_equal(options.decode_speed, 5)
    assert_equal(options.encode_speed, 5)
    assert_true(options.encoder_method == DRACO_MESH_EDGEBREAKER_ENCODING)
    assert_equal(options.quantization, [16, 8, 8, 8, 8])
    assert_true(options.export_uvs)
    assert_true(options.export_normals)
    assert_false(options.export_color)
    assert_equal(options.bits(DracoAttributeType(4)), 8)
    options.quantization = [12]
    assert_equal(options.bits(DracoAttributeType(0)), 12)
    assert_equal(options.bits(DracoAttributeType(1)), -1)
    assert_equal(options.speed(), 5)


def test_types() raises:
    assert_true(DRACO_MESH_SEQUENTIAL_ENCODING.is_valid())
    assert_true(DRACO_MESH_EDGEBREAKER_ENCODING.is_valid())
    assert_false(DracoEncoderMethod(2).is_valid())
    assert_true(DRACO_EXPORT_MESH.is_valid())
    assert_true(DRACO_EXPORT_POINTS.is_valid())
    assert_false(DracoObjectKind(2).is_valid())
    assert_true(DRACO_TAGGED_SYMBOLS.is_valid())
    assert_true(DRACO_RAW_SYMBOLS.is_valid())
    assert_false(DracoSymbolCoding(2).is_valid())


def test_refusals() raises:
    var geometry = _triangles()
    with assert_raises(contains="an object kind is not known"):
        _ = export_draco(geometry, DracoObjectKind(7))
    with assert_raises(contains="an encoder method is not known"):
        _ = export_draco(
            geometry,
            DRACO_EXPORT_MESH,
            DracoExportOptions(encoder_method=DracoEncoderMethod(3)),
        )
    var speeds: List[Tuple[Int, Int]] = [(-1, 5), (11, 5), (5, -1), (5, 11)]
    for speed in speeds:
        with assert_raises(contains="a speed is not from 0 to 10"):
            _ = export_draco(
                geometry,
                DRACO_EXPORT_MESH,
                DracoExportOptions(
                    encode_speed=speed[0], decode_speed=speed[1]
                ),
            )
    with assert_raises(contains="quantization bits are above 30"):
        _ = export_draco(
            geometry,
            DRACO_EXPORT_MESH,
            DracoExportOptions(quantization=[31]),
        )
    with assert_raises(contains="normals need two quantization bits"):
        _ = export_draco(
            geometry,
            DRACO_EXPORT_MESH,
            DracoExportOptions(quantization=[8, 1]),
        )
    var bad = BufferGeometry()
    with assert_raises(contains="a geometry has no positions"):
        _ = export_draco(bad)
    bad.set_attribute(POSITION, BufferAttribute(List[Float32](), 3))
    with assert_raises(contains="a geometry has no vertices"):
        _ = export_draco(bad)
    bad.set_attribute(POSITION, BufferAttribute([0.0, 0, 0, 1], 2))
    with assert_raises(contains="a position attribute has 2 components"):
        _ = export_draco(bad)
    bad = _triangles()
    bad.set_attribute(UV, BufferAttribute([0.0, 0, 1, 1, 0, 1], 3))
    with assert_raises(contains="a uv attribute has 3 components"):
        _ = export_draco(bad)
    bad = _triangles()
    bad.set_attribute(NORMAL, BufferAttribute([0.0, 0, 1], 3))
    with assert_raises(contains="does not have one value for each vertex"):
        _ = export_draco(bad)
    bad = _triangles()
    bad.set_attribute(COLOR, BufferAttribute([0.0, 0, 1, 1, 0, 1, 1, 1], 2))
    with assert_raises(contains="a color attribute has 2 components"):
        _ = export_draco(
            bad, DRACO_EXPORT_MESH, DracoExportOptions(export_color=True)
        )
    bad = _triangles()
    bad.set_index([0, 1, 4])
    with assert_raises(contains="a triangle names a missing vertex"):
        _ = export_draco(bad)
    bad = _triangles()
    bad.set_attribute(
        NORMAL,
        BufferAttribute(
            [inf[DType.float32](), 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1], 3
        ),
    )
    with assert_raises(contains="a normal is infinite"):
        _ = export_draco(bad)
    bad = _triangles()
    bad.set_attribute(
        POSITION,
        BufferAttribute(
            [nan[DType.float32](), 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0], 3
        ),
    )
    with assert_raises(contains="a value to quantize is not finite"):
        _ = export_draco(bad)


def test_without_an_index() raises:
    # three.js passes one triangle for each vertex, and Draco reads past the
    # end of the index. This writes one triangle for each three vertices.
    var geometry = _triangles().to_non_indexed()
    var indexed = geometry.clone()
    indexed.set_index([0, 1, 2, 3, 4, 5])
    assert_equal(export_draco(geometry), export_draco(indexed))
    var two = BufferGeometry()
    two.set_attribute(POSITION, BufferAttribute([0.0, 0, 0, 1, 0, 0], 3))
    with assert_raises(contains="all triangles are degenerate"):
        _ = export_draco(two)
    var sequential = DracoExportOptions(
        encoder_method=DRACO_MESH_SEQUENTIAL_ENCODING
    )
    # Draco writes points without triangles, and its decoder, as this one,
    # refuses more points than three for each triangle.
    var bytes = export_draco(two, DRACO_EXPORT_MESH, sequential)
    with assert_raises(contains="there are too many points"):
        _ = decode_draco(bytes)


def test_write_draco() raises:
    var path = "out/test_draco_export.drc"
    write_draco(
        path,
        _triangles(),
        DRACO_EXPORT_MESH,
        DracoExportOptions(export_color=True),
    )
    var geometry = read_draco(path)
    assert_equal(geometry.attribute_view(POSITION).count(), 4)
    assert_true(geometry.has_attribute(COLOR))
    assert_equal(len(geometry.index), 6)


def test_one_value() raises:
    # A range of zero quantizes across a range of one, as in Draco.
    var point = BufferGeometry()
    point.set_attribute(POSITION, BufferAttribute([1.0, 2, 3], 3))
    var methods: List[DracoEncoderMethod] = [
        DRACO_MESH_EDGEBREAKER_ENCODING,
        DRACO_MESH_SEQUENTIAL_ENCODING,
    ]
    for method in methods:
        var bytes = export_draco(
            point,
            DRACO_EXPORT_POINTS,
            DracoExportOptions(encoder_method=method),
        )
        var decoded = decode_draco(bytes)
        assert_equal(decoded.points, 1)
        assert_equal(decoded.float32_values(0), [Float32(1), 2, 3])


def test_one_texture_prediction() raises:
    # Three corners with one uv leave the texture prediction nothing to
    # orient.
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION, BufferAttribute([0.0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    geometry.set_attribute(
        UV, BufferAttribute([0.5, 0.5, 0.5, 0.5, 0.5, 0.5], 2)
    )
    geometry.set_index([0, 1, 2])
    var bytes = export_draco(
        geometry,
        DRACO_EXPORT_MESH,
        DracoExportOptions(encode_speed=0, decode_speed=0),
    )
    var decoded = decode_draco(bytes)
    assert_true(decoded.geometry_type == DRACO_TRIANGULAR_MESH)
    assert_equal(len(decoded.faces), 3)
    var positions = decoded.float32_values(0)
    var uvs = decoded.float32_values(1)
    ref want = geometry.attribute_view(UV).data
    for p in range(decoded.points):
        # The vertex is the one whose position this point has.
        var vertex = Int(positions[3 * p]) + 2 * Int(positions[3 * p + 1])
        assert_true(abs(uvs[2 * p] - want[2 * vertex]) < 0.01)
        assert_true(abs(uvs[2 * p + 1] - want[2 * vertex + 1]) < 0.01)


def test_sequential_indices() raises:
    var widths: List[Int] = [1, 2, 0, 4]
    for width in widths:
        var out = DracoWriter()
        write_sequential_index(out, 200, width)
        var buffer = DracoBuffer(out.bytes.copy())
        assert_equal(read_sequential_index(buffer, width), 200)


def _round_trip_symbols(symbols: List[Int], components: Int, level: Int) raises:
    var out = DracoWriter()
    encode_symbols(out, symbols, components, level)
    var buffer = DracoBuffer(out.bytes.copy())
    assert_equal(decode_symbols(buffer, len(symbols), components), symbols)


def test_symbols() raises:
    # Wide symbols are tagged even when the raw estimate is smaller.
    _round_trip_symbols(List[Int](length=10000, fill=1 << 19), 1, 7)
    # Many distinct symbols at the highest level take the widest state,
    # and a common one a probability of three bytes.
    var many = List[Int](length=20000, fill=0)
    for i in range(20000):
        many.append(i % 9000)
    _round_trip_symbols(many, 1, 10)
    var raw = DracoWriter()
    encode_symbols_with(raw, many, 1, 10, DRACO_RAW_SYMBOLS, List[Int](), 9000)
    var buffer = DracoBuffer(raw.bytes.copy())
    assert_equal(decode_symbols(buffer, len(many), 1), many)
    # One common symbol and many rare ones overshoot the precision, and
    # the common one gives up the excess.
    var rare = List[Int](length=100000, fill=0)
    for i in range(1, 300):
        rare.append(i)
    _round_trip_symbols(rare, 1, 0)
    var nothing = DracoWriter()
    encode_symbols(nothing, List[Int](), 1, 7)
    assert_equal(len(nothing.bytes), 0)
    with assert_raises(contains="a symbol coding is not known"):
        encode_symbols_with(nothing, [1], 1, 7, DracoSymbolCoding(2), [1], 1)
    var all = List[Int]()
    for i in range(1 << 18):
        all.append(i)
    with assert_raises(contains="there are too many distinct symbols"):
        encode_symbols_with(
            nothing, all, 1, 7, DRACO_RAW_SYMBOLS, List[Int](), 1 << 18
        )


def test_estimates() raises:
    assert_equal(binary_entropy(0, 0), 0.0)
    assert_equal(binary_entropy(4, 0), 0.0)
    assert_equal(binary_entropy(4, 4), 0.0)
    assert_equal(binary_entropy(4, 2), 1.0)
    assert_equal(entropy_data_bits(EntropyData(0.0, 1, 0, 1)), 0)
    assert_equal(entropy_data_bits(EntropyData(2.0, 2, 1, 1)), 0)


def test_musl_log2() raises:
    assert_equal(musl_log2(1.0), 0.0)
    assert_equal(musl_log2(8.0), 3.0)
    assert_equal(musl_log2(0.5), -1.0)
    # Near one, and away from it: musl's bits. The host's `log2` gives
    # 0x4030598002600057 for 83507.
    assert_equal(bitcast[DType.uint64](musl_log2(1.01)), 0x3F8D664ECEE35B7F)
    assert_equal(bitcast[DType.uint64](musl_log2(83507.0)), 0x4030598002600056)
    with assert_raises(contains="a logarithm of a number that is not"):
        _ = musl_log2(0.0)


def test_integer_edges() raises:
    assert_equal(wasm_i32(-3.7), -3)
    assert_equal(wasm_i32(nan[DType.float64]()), -2147483648)
    assert_equal(wasm_i32(3e9), -2147483648)
    assert_equal(_int_sqrt(UInt64(0)), 0)
    assert_equal(_int_sqrt(UInt64(17)), 4)
    assert_equal(_abs_sum([1, -2, 3]), 6)
    var big = 0x7FFFFFFFFFFFFFFF
    assert_equal(_abs_sum([big, 1, 0]), big)
    assert_equal(_abs_sum([-big - 1, 0, 0]), big)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
