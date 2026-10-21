# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Small boundary fixtures must reject large decoded sizes before allocation."""

from core.binary import append_little_endian_u32
from loaders.bytes import (
    bytes_match,
    hex_digit_value,
    is_exponent_mark,
    is_hex_digit,
    js_float_byte,
    js_float_byte_at,
    letter_or_underscore,
    space_tab_return,
)
from loaders.draco import (
    _Decoder,
    DRACO_POINT_CLOUD,
    DRACO_SEQUENTIAL,
    MAX_DRACO_ATTRIBUTE_BYTES,
    MAX_DRACO_POINTS,
    decode_draco,
)
from loaders.draco_buffer import DracoBuffer
from loaders.fbx_tree import (
    _BinaryReader,
    MAX_FBX_ARRAY_BYTES,
    FbxDocument,
    FBX_BINARY,
)
from loaders.gltf_layout import (
    AccessorLayout,
    check_buffer_range,
    MAX_GLTF_ACCESSOR_BYTES,
    MAX_GLTF_ACCESSOR_COUNT,
)
from loaders.meshopt import (
    decode_index_buffer,
    decode_index_sequence,
    decode_vertex_buffer,
    require_meshopt_output,
)
from loaders.ttf import _Data, _cmap
from loaders.vox import (
    _vox_cells,
    MAX_VOX_DIM,
    MAX_VOX_VOLUME_BYTES,
    VoxModel,
    parse_vox,
    vox_geometry,
)
from render.png import zlib_stream
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _le(value: Int) -> List[UInt8]:
    var out = List[UInt8]()
    append_little_endian_u32(out, value)
    return out^


def _be(mut out: List[UInt8], value: Int, width: Int):
    for shift in range((width - 1) * 8, -1, -8):
        out.append(UInt8((value >> shift) & 255))


def _chunk(
    name: String, body: List[UInt8], children: List[UInt8]
) -> List[UInt8]:
    var out = List[UInt8](name.as_bytes())
    out.extend(_le(len(body)))
    out.extend(_le(len(children)))
    out.extend(Span(body))
    out.extend(Span(children))
    return out^


def _vox(body: List[UInt8]) -> List[UInt8]:
    var out = List[UInt8]("VOX ".as_bytes())
    out.extend(_le(150))
    out.extend(Span(body))
    return out^


def _size(x: Int, y: Int, z: Int) -> List[UInt8]:
    var body = _le(x)
    body.extend(_le(y))
    body.extend(_le(z))
    return _chunk("SIZE", body, [])


def _cloud(points: Int) -> List[UInt8]:
    var out = List[UInt8]("DRACO".as_bytes())
    var header: List[UInt8] = [2, 3, 0, 0, 0, 0]
    out.extend(header^)
    out.extend(_le(points))
    return out^


def _cmap12(groups: List[Int]) -> List[UInt8]:
    var out = List[UInt8]()
    _be(out, 0, 2)
    _be(out, 1, 2)
    _be(out, 3, 2)
    _be(out, 10, 2)
    _be(out, 12, 4)
    _be(out, 12, 2)
    _be(out, 0, 2)
    _be(out, 16 + len(groups) * 4, 4)
    _be(out, 0, 4)
    _be(out, len(groups) // 3, 4)
    for value in groups:
        _be(out, value, 4)
    return out^


def test_byte_matches_check_the_real_span_without_integer_wrap() raises:
    var bytes = List[UInt8]("abc".as_bytes())
    assert_true(bytes_match(Span(bytes), 0, 3, "abc"))
    assert_true(bytes_match(Span(bytes), 1, 2, "b"))
    assert_false(bytes_match(Span(bytes), -1, 3, "a"))
    assert_false(bytes_match(Span(bytes), 0, 4, "a"))
    assert_false(bytes_match(Span(bytes), 0, -1, "a"))
    assert_false(bytes_match(Span(bytes), 3, 3, "a"))
    assert_false(bytes_match(Span(bytes), 0, 2, "abc"))
    assert_false(bytes_match(Span(bytes), 9223372036854775807, 3, "ab"))
    assert_false(bytes_match(Span(bytes), 0, 9223372036854775807, "a"))
    assert_false(bytes_match(Span(bytes), 0, 3, "abd"))


def test_shared_byte_classifiers_keep_ascii_boundaries() raises:
    var letters = List[UInt8](
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_".as_bytes()
    )
    var number_bytes = List[UInt8]("0123456789.+-e".as_bytes())
    for byte in range(128):
        assert_equal(space_tab_return(UInt8(byte)), byte in [9, 13, 32])
        assert_equal(
            letter_or_underscore(UInt8(byte)),
            UInt8(byte) in letters,
        )
        assert_equal(is_exponent_mark(UInt8(byte)), byte in [69, 101])
        assert_equal(
            js_float_byte(UInt8(byte)),
            UInt8(byte) in number_bytes,
        )
    var digits: List[Int] = [47, 48, 57, 58, 64, 65, 70, 71, 96, 97, 102, 103]
    var values: List[Int] = [-1, 0, 9, -1, -1, 10, 15, -1, -1, 10, 15, -1]
    for i in range(len(digits)):
        assert_equal(hex_digit_value(digits[i]), values[i])
        assert_equal(is_hex_digit(digits[i]), values[i] >= 0)
    var bytes = List[UInt8]("7e!".as_bytes())
    for at in [-1, 0, 1, 2, 3]:
        assert_equal(js_float_byte_at(Span(bytes), at), at in [0, 1])


def test_gltf_layout_range_and_alignment_boundaries() raises:
    check_buffer_range(8, 8, 0)
    for pair in [(-1, 0), (9, 0), (0, -1), (8, 1)]:
        with assert_raises(contains="buffer view runs past"):
            check_buffer_range(8, pair[0], pair[1])
    var kinds: List[String] = [
        "SCALAR",
        "VEC2",
        "VEC3",
        "VEC4",
        "MAT2",
        "MAT3",
        "MAT4",
    ]
    var widths: List[Int] = [1, 2, 3, 4, 4, 9, 16]
    for size in [1, 2, 4]:
        for k in range(len(kinds)):
            var layout = AccessorLayout(kinds[k], size)
            assert_equal(layout.width, widths[k])
            assert_equal(len(layout.offsets()), widths[k])
    with assert_raises(contains="component size"):
        _ = AccessorLayout("SCALAR", 3)
    with assert_raises(contains="not known"):
        _ = AccessorLayout("VEC5", 1)
    var scalar = AccessorLayout("SCALAR", 2)
    for offset in [-1, 1]:
        with assert_raises(contains="aligned byteOffset"):
            scalar.check(0, offset)
    var matrix = AccessorLayout("MAT2", 1)
    assert_equal(matrix.span(0, 0, 0, 0, 0, False)[1], 8)
    assert_equal(matrix.span(2, 0, 0, 14, 8, True)[1], 8)
    with assert_raises(contains="misaligned"):
        _ = matrix.span(0, 5, 0, 4, 0, False)
    with assert_raises(contains="misaligned"):
        _ = matrix.span(0, 0, 1, 8, 0, False)
    for stride in [4, 9, 256]:
        with assert_raises(contains="invalid byteStride"):
            _ = matrix.span(1, 0, 0, 8, stride, True)
    with assert_raises(contains="past its buffer view"):
        _ = matrix.span(1, 0, 0, 5, 0, False)
    with assert_raises(contains="past its buffer view"):
        _ = matrix.span(2, 0, 0, 13, 0, False)


def test_gltf_decoded_component_width_sets_the_allocation_limit() raises:
    var scalar = AccessorLayout("SCALAR", 1)
    scalar.check(MAX_GLTF_ACCESSOR_COUNT, 0)
    with assert_raises(contains="count is invalid"):
        scalar.check(MAX_GLTF_ACCESSOR_COUNT + 1, 0)
    with assert_raises(contains="count is invalid"):
        scalar.check(-1, 0)
    var matrix = AccessorLayout("MAT4", 1)
    var limit = MAX_GLTF_ACCESSOR_BYTES // (16 * 8)
    matrix.check(limit, 0)
    with assert_raises(contains="count is invalid"):
        matrix.check(limit + 1, 0)
    with assert_raises(contains="count is invalid"):
        matrix.check(9223372036854775807, 0)


def test_all_meshopt_modes_refuse_oversized_output_before_reading() raises:
    require_meshopt_output((1 << 30) // 4, 4)
    with assert_raises(contains="too large to decode"):
        _ = decode_vertex_buffer((1 << 30) // 4 + 1, 4, [])
    with assert_raises(contains="too large to decode"):
        _ = decode_index_buffer((1 << 30) // 4 + 2, 4, [])
    with assert_raises(contains="too large to decode"):
        _ = decode_index_sequence(9223372036854775807, 4, [])
    var tiny: List[UInt8] = [0xA0, 0, 0, 0, 0]
    with assert_raises(contains="malformed buffer data: -2"):
        _ = decode_vertex_buffer((1 << 30) // 4, 4, tiny)
    with assert_raises(contains="malformed buffer data: -3"):
        _ = decode_vertex_buffer(0, 4, tiny)


def test_meshopt_exhausted_component_header_still_refuses_the_stream() raises:
    var stream: List[UInt8] = [0xA0]
    # Two full escape groups consume enough bytes to pass the minimum
    # header-size guard, then consume the third component's header too.
    for _ in range(2):
        stream.append(2)
        for _ in range(8):
            stream.append(255)
        for _ in range(16):
            stream.append(0)
    with assert_raises(contains="malformed buffer data: -2"):
        _ = decode_vertex_buffer(16, 4, stream)


def test_fbx_array_budget_counts_decoded_width_and_all_arrays() raises:
    var empty = List[UInt8]()
    var reader = _BinaryReader(Span(empty))
    reader.reserve_array(MAX_FBX_ARRAY_BYTES // 8 - 1)
    reader.reserve_array(1)
    assert_equal(reader.array_bytes, MAX_FBX_ARRAY_BYTES)
    reader.reserve_array(0)
    with assert_raises(contains="too large to expand"):
        reader.reserve_array(1)
    for encoding in [0, 1]:
        var bytes = _le(MAX_FBX_ARRAY_BYTES // 8 + 1)
        bytes.extend(_le(encoding))
        bytes.extend(_le(0))
        var oversized = _BinaryReader(Span(bytes))
        with assert_raises(contains="too large to expand"):
            _ = oversized.array(98)


def test_fbx_array_data_cannot_cross_its_record_boundary() raises:
    for encoding in [0, 1]:
        var raw: List[UInt8] = [1]
        var stored = raw.copy() if encoding == 0 else zlib_stream(raw)
        var record = _le(14 + 13)
        record.extend(_le(1))
        record.extend(_le(13 + len(stored)))
        record.append(1)
        record.append(65)
        record.append(98)
        record.extend(_le(1))
        record.extend(_le(encoding))
        record.extend(_le(len(stored)))
        record.extend(stored^)
        var reader = _BinaryReader(Span(record))
        reader.version = 7400
        var document = FbxDocument(FBX_BINARY)
        with assert_raises(contains="file ends inside a record"):
            reader.record(document, 0, 1)
    var empty = List[UInt8]()
    var reader = _BinaryReader(Span(empty))
    with assert_raises(contains="file ends inside a record"):
        reader.need(-1)


def test_draco_point_count_and_cumulative_attribute_budget() raises:
    for count in [-1, MAX_DRACO_POINTS + 1]:
        with assert_raises(contains="point count"):
            _ = decode_draco(_cloud(count))
    var empty_cloud = _cloud(MAX_DRACO_POINTS)
    empty_cloud.append(0)
    assert_equal(decode_draco(empty_cloud).points, MAX_DRACO_POINTS)
    var decoder = _Decoder(DracoBuffer([]), DRACO_POINT_CLOUD, DRACO_SEQUENTIAL)
    decoder.geometry.points = MAX_DRACO_POINTS
    decoder.reserve_attribute(1)
    assert_equal(decoder.attribute_bytes, MAX_DRACO_ATTRIBUTE_BYTES)
    with assert_raises(contains="attributes are too large"):
        decoder.reserve_attribute(1)
    var large = _cloud(MAX_DRACO_POINTS)
    var attributes: List[UInt8] = [1, 1, 0, 2, 2, 0, 0, 0]
    large.extend(attributes^)
    with assert_raises(contains="attributes are too large"):
        _ = decode_draco(large)
    var truncated = _cloud(MAX_DRACO_POINTS)
    var raw: List[UInt8] = [1, 1, 0, 2, 1, 0, 0, 0]
    truncated.extend(raw^)
    with assert_raises(contains="file ends early"):
        _ = decode_draco(truncated)


def test_vox_dimensions_and_cumulative_volume_are_checked_without_allocating() raises:
    assert_equal(
        _vox_cells(MAX_VOX_DIM, MAX_VOX_DIM, MAX_VOX_DIM), MAX_VOX_VOLUME_BYTES
    )
    assert_equal(_vox_cells(0, 1, 1), 0)
    for axis in range(3):
        for bad in [-1, MAX_VOX_DIM + 1]:
            var dims: List[Int] = [1, 1, 1]
            dims[axis] = bad
            with assert_raises(contains="out of range"):
                _ = vox_geometry(VoxModel(dims[0], dims[1], dims[2]))
    var bytes = _size(MAX_VOX_DIM, MAX_VOX_DIM, MAX_VOX_DIM)
    assert_equal(len(parse_vox(_vox(bytes))), 1)
    bytes.extend(_size(1, 1, 1))
    with assert_raises(contains="volumes are too large"):
        _ = parse_vox(_vox(bytes))


def test_vox_chunk_fields_cannot_borrow_the_next_chunk() raises:
    var short = _size(1, 1, 1)
    short.extend(_chunk("XYZI", [], []))
    short.extend(_chunk("JUNK", _le(0), []))
    with assert_raises(contains="too short for its count"):
        _ = parse_vox(_vox(short))
    short = _size(1, 1, 1)
    short.extend(_chunk("XYZI", _le(1), []))
    short.extend(_chunk("JUNK", _le(0), []))
    with assert_raises(contains="too short for its voxels"):
        _ = parse_vox(_vox(short))
    short = _size(1, 1, 1)
    short.extend(_chunk("RGBA", [], []))
    short.extend(_chunk("JUNK", List[UInt8](length=1024, fill=0), []))
    with assert_raises(contains="too short for its palette"):
        _ = parse_vox(_vox(short))


def test_vox_declared_content_and_children_stay_inside_their_parent() raises:
    var truncated = _chunk("JUNK", [], [])
    truncated[4] = 1
    with assert_raises(contains="ends inside a chunk's content"):
        _ = parse_vox(_vox(truncated))
    truncated = _chunk("MAIN", [], [])
    truncated[8] = 1
    with assert_raises(contains="children run past its parent"):
        _ = parse_vox(_vox(truncated))
    var child = _chunk("JUNK", [], [])
    child[4] = 1
    var nested = _chunk("MAIN", [], child)
    nested.extend(_chunk("JUNK", [], []))
    with assert_raises(contains="ends inside a chunk's content"):
        _ = parse_vox(_vox(nested))
    with assert_raises(contains="chunk header"):
        _ = parse_vox(_vox([0]))
    var partial = _chunk("MAIN", [], [0])
    partial.extend(_chunk("JUNK", [], []))
    with assert_raises(contains="chunk header"):
        _ = parse_vox(_vox(partial))


def test_vox_known_chunks_skip_declared_trailing_bytes_and_read_siblings() raises:
    var content = _le(0)
    content.append(255)
    var body = _size(1, 1, 1)
    body.extend(_chunk("XYZI", content, []))
    var palette = List[UInt8](length=1025, fill=0)
    body.extend(_chunk("RGBA", palette, []))
    var nested = _chunk("MAIN", [], _chunk("MAIN", [], body))
    nested.extend(_size(2, 2, 2))
    var models = parse_vox(_vox(nested))
    assert_equal(len(models), 2)
    assert_equal(models[0].voxel_count(), 0)
    assert_equal(models[1].size_x, 2)


def test_cmap_ranges_are_checked_before_expansion_and_are_disjoint() raises:
    for groups in [
        List[Int]([2, 1, 0]),
        List[Int]([0, 0x110000, 0]),
        List[Int]([0, 0x10FFFF, 0, 0, 0, 0]),
        List[Int]([2, 3, 0, 1, 1, 0]),
    ]:
        var bytes = _cmap12(groups)
        with assert_raises():
            _ = _cmap(_Data(Span(bytes)), 0)
    var bytes = _cmap12([0, 0, 0, 0x10FFFF, 0x10FFFF, 1])
    var map = _cmap(_Data(Span(bytes)), 0)
    assert_equal(len(map), 2)
    assert_equal(map[0x10FFFF], 1)
    bytes = _cmap12([])
    assert_equal(len(_cmap(_Data(Span(bytes)), 0)), 0)


def test_cmap_groups_cannot_read_beyond_the_declared_subtable() raises:
    var bytes = _cmap12([0, 0, 0])
    bytes[19] = 15
    with assert_raises(contains="subtable runs past its bounds"):
        _ = _cmap(_Data(Span(bytes)), 0)
    bytes[19] = 255
    with assert_raises(contains="subtable runs past its bounds"):
        _ = _cmap(_Data(Span(bytes)), 0)
    bytes[19] = 16
    with assert_raises(contains="groups run past their subtable"):
        _ = _cmap(_Data(Span(bytes)), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
