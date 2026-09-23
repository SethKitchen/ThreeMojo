# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.pcd`.

`assets/pcd/` holds one cloud of five points in the three encodings. The
values expected here are what three.js 0.180's `PCDLoader` gives for
those files in node. Smaller files are written inline to reach every
branch and every refusal.
"""

from core.buffer_geometry import COLOR, NORMAL, POSITION
from loaders.pcd import (
    INTENSITY,
    PCD_ASCII,
    PCD_BINARY,
    PCD_BINARY_COMPRESSED,
    PCD_FLOAT,
    PCD_SIGNED,
    PCD_UNSIGNED,
    PcdDataFormat,
    PcdFieldType,
    PcdHeader,
    decode_pcd_value,
    decompress_lzf,
    parse_pcd,
    parse_pcd_header,
    pcd_data_format,
    pcd_field_type,
    read_pcd,
)
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(1e-6)


def text_bytes(text: String) -> List[UInt8]:
    """Return a text as the bytes of a file."""
    var bytes = List[UInt8]()
    for byte in text.as_bytes():
        bytes.append(byte)
    return bytes^


def put(mut bytes: List[UInt8], value: UInt64, size: Int):
    """Append the low `size` bytes of a value, least significant first."""
    for index in range(size):
        bytes.append(UInt8((value >> UInt64(index * 8)) & 0xFF))


def put_f32(mut bytes: List[UInt8], value: Float32):
    """Append a `Float32`, least significant byte first."""
    put(bytes, UInt64(bitcast[DType.uint32](value)), 4)


def assert_list(got: List[Float32], want: List[Float64]) raises:
    """Assert two lists of numbers match within tolerance."""
    assert_equal(len(got), len(want))
    for index in range(len(want)):
        assert_almost_equal(Float64(got[index]), want[index], atol=TOLERANCE)


def check_fixture(path: String) raises:
    """Check a fixture against what three.js gives for it."""
    var model = read_pcd(path)
    ref geometry = model.geometry
    assert_list(
        geometry.clone_attribute(String(POSITION)).packed(),
        [0, 0, 0, 1, 0, 0, 0, 1, 0, 0.5, 0.5, 1.5, -1.25, 2, -0.5],
    )
    assert_list(
        geometry.clone_attribute(String(NORMAL)).packed(),
        [
            0,
            0,
            1,
            0,
            1,
            0,
            1,
            0,
            0,
            0.6000000238418579,
            0,
            0.800000011920929,
            0,
            -1,
            0,
        ],
    )
    assert_list(
        geometry.clone_attribute(String(COLOR)).packed(),
        [
            1,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            1,
            0.2158605009317398,
            0.05126945674419403,
            0.014443843625485897,
            0.577580451965332,
            0.577580451965332,
            0.577580451965332,
        ],
    )
    assert_list(
        geometry.clone_attribute(String(INTENSITY)).packed(),
        [0.5, 0.25, 1, 0.75, 0],
    )
    assert_equal(model.labels, [1, 2, 3, -4, 70000])
    assert_equal(model.header.version, "0.7")
    assert_equal(model.header.viewpoint, "0 0 0 1 0 0 0")
    assert_equal(model.header.width, 5)
    assert_equal(model.header.height, 1)
    assert_equal(model.header.points, 5)
    assert_equal(len(model.header.fields), 9)


def test_the_three_fixtures_match_three_js() raises:
    check_fixture("assets/pcd/ascii.pcd")
    check_fixture("assets/pcd/binary.pcd")
    check_fixture("assets/pcd/binary_compressed.pcd")
    assert_true(read_pcd("assets/pcd/ascii.pcd").header.data == PCD_ASCII)
    assert_true(read_pcd("assets/pcd/binary.pcd").header.data == PCD_BINARY)
    assert_true(
        read_pcd("assets/pcd/binary_compressed.pcd").header.data
        == PCD_BINARY_COMPRESSED
    )
    with assert_raises():
        _ = read_pcd("assets/pcd/missing.pcd")


def test_names_of_formats_and_types() raises:
    assert_true(pcd_data_format("ascii") == PCD_ASCII)
    assert_true(pcd_data_format("binary") == PCD_BINARY)
    assert_true(pcd_data_format("binary_compressed") == PCD_BINARY_COMPRESSED)
    with assert_raises(contains="data format"):
        _ = pcd_data_format("binaryx")
    assert_true(pcd_field_type("F") == PCD_FLOAT)
    assert_true(pcd_field_type("I") == PCD_SIGNED)
    assert_true(pcd_field_type("U") == PCD_UNSIGNED)
    with assert_raises(contains="field type"):
        _ = pcd_field_type("f")
    assert_true(PCD_ASCII.is_valid())
    assert_true(PCD_BINARY_COMPRESSED.is_valid())
    assert_false(PcdDataFormat(-1).is_valid())
    assert_false(PcdDataFormat(3).is_valid())
    assert_false(PcdFieldType(-1).is_valid())
    assert_false(PcdFieldType(3).is_valid())


def test_sizes_each_type_takes() raises:
    assert_true(PCD_FLOAT.has_size(4))
    assert_true(PCD_FLOAT.has_size(8))
    assert_false(PCD_FLOAT.has_size(2))
    for size in [1, 2, 4, 8]:
        assert_true(PCD_SIGNED.has_size(size))
        assert_true(PCD_UNSIGNED.has_size(size))
        assert_false(PcdFieldType(3).has_size(size))
    assert_false(PCD_SIGNED.has_size(3))
    assert_false(PCD_UNSIGNED.has_size(16))


def test_decode_every_type_and_size() raises:
    var bytes = List[UInt8]()
    put(bytes, 0xFF, 1)  # 0
    put(bytes, 0xFFFE, 2)  # 1
    put(bytes, 0xFFFFFFFD, 4)  # 3
    put(bytes, 0xFFFFFFFFFFFFFFFC, 8)  # 7
    put_f32(bytes, -2.5)  # 15
    put(bytes, bitcast[DType.uint64](Float64(0.125)), 8)  # 19
    assert_equal(decode_pcd_value(bytes, 0, PCD_SIGNED, 1), -1)
    assert_equal(decode_pcd_value(bytes, 0, PCD_UNSIGNED, 1), 255)
    assert_equal(decode_pcd_value(bytes, 1, PCD_SIGNED, 2), -2)
    assert_equal(decode_pcd_value(bytes, 1, PCD_UNSIGNED, 2), 65534)
    assert_equal(decode_pcd_value(bytes, 3, PCD_SIGNED, 4), -3)
    assert_equal(decode_pcd_value(bytes, 3, PCD_UNSIGNED, 4), 4294967293)
    assert_equal(decode_pcd_value(bytes, 7, PCD_SIGNED, 8), -4)
    assert_equal(
        decode_pcd_value(bytes, 7, PCD_UNSIGNED, 8), 18446744073709551612.0
    )
    assert_equal(decode_pcd_value(bytes, 15, PCD_FLOAT, 4), -2.5)
    assert_equal(decode_pcd_value(bytes, 19, PCD_FLOAT, 8), 0.125)
    put(bytes, 0x7F, 1)  # 27
    assert_equal(decode_pcd_value(bytes, 27, PCD_SIGNED, 1), 127)
    with assert_raises(contains="cannot take"):
        _ = decode_pcd_value(bytes, 0, PCD_FLOAT, 2)
    with assert_raises(contains="cannot take"):
        _ = decode_pcd_value(bytes, 0, PcdFieldType(9), 4)
    with assert_raises(contains="ends inside"):
        _ = decode_pcd_value(bytes, -1, PCD_SIGNED, 1)
    with assert_raises(contains="ends inside"):
        _ = decode_pcd_value(bytes, 25, PCD_SIGNED, 4)


def test_lzf_literals_and_references() raises:
    # "abc", then "abcabc" by a reference of length 6 at distance 3, then
    # a long reference of length 12 at distance 1.
    var data: List[UInt8] = [2, 97, 98, 99, (4 << 5), 2, (7 << 5), 3, 0]
    var out = decompress_lzf(data, 3 + 6 + 12)
    assert_equal(String(from_utf8=Span(out)), "abcabcabc" + "cccccccccccc")
    assert_equal(len(decompress_lzf(List[UInt8](), 0)), 0)


def test_lzf_refusals() raises:
    with assert_raises(contains="larger than"):
        _ = decompress_lzf([2, 97, 98, 99], 2)
    with assert_raises(contains="run of literals"):
        _ = decompress_lzf([2, 97, 98], 3)
    with assert_raises(contains="back reference"):
        _ = decompress_lzf([0, 97, (1 << 5)], 4)
    with assert_raises(contains="back reference"):
        _ = decompress_lzf([0, 97, (7 << 5), 0], 20)
    with assert_raises(contains="larger than"):
        _ = decompress_lzf([0, 97, (1 << 5), 0], 3)
    with assert_raises(contains="before the start"):
        _ = decompress_lzf([0, 97, (1 << 5), 1], 4)
    with assert_raises(contains="declares"):
        _ = decompress_lzf([0, 97], 2)


def test_header_keywords_comments_and_defaults() raises:
    var header = parse_pcd_header(
        text_bytes(
            "# a comment\n\nversion .7 # trailing\nfields x y z\nsize 4 4"
            " 4\ntype F F F\nwidth 2\nheight 3\n  DATA ascii\n"
        )
    )
    assert_equal(header.version, ".7")
    assert_equal(header.points, 6)
    assert_equal(header.counts, [1, 1, 1])
    assert_equal(header.offsets, [0, 1, 2])
    assert_equal(header.row_size, 3)
    assert_equal(header.header_length, 100)
    assert_equal(header.field("y"), 1)
    assert_equal(header.field("w"), -1)
    assert_equal(PcdHeader().field("x"), -1)
    var bare = parse_pcd_header(
        text_bytes("FIELDS\nSIZE\nTYPE\nCOUNT\nUNKNOWN 3\nDATA binary\n")
    )
    assert_equal(len(bare.counts), 0)
    assert_equal(bare.row_size, 0)
    var empty = parse_pcd_header(text_bytes("DATA ascii\n"))
    assert_equal(empty.points, 0)
    assert_equal(len(empty.fields), 0)
    assert_equal(empty.header_length, 11)


def test_header_refusals() raises:
    with assert_raises(contains="no `DATA`"):
        _ = parse_pcd_header(text_bytes("FIELDS x\n"))
    with assert_raises(contains="followed by a space"):
        _ = parse_pcd_header(text_bytes("DATA"))
    with assert_raises(contains="followed by a space"):
        _ = parse_pcd_header(text_bytes("DATAX ascii\n"))
    with assert_raises(contains="ends on its"):
        _ = parse_pcd_header(text_bytes("DATA ascii"))
    with assert_raises(contains="data format"):
        _ = parse_pcd_header(text_bytes("DATA text\n"))
    with assert_raises(contains="not a whole number"):
        _ = parse_pcd_header(text_bytes("POINTS many\nDATA ascii\n"))
    with assert_raises(contains="negative"):
        _ = parse_pcd_header(text_bytes("WIDTH -2\nDATA ascii\n"))
    with assert_raises(contains="`SIZE`"):
        _ = parse_pcd_header(text_bytes("FIELDS x\nTYPE F\nDATA ascii\n"))
    with assert_raises(contains="`TYPE`"):
        _ = parse_pcd_header(text_bytes("FIELDS x\nSIZE 4\nDATA ascii\n"))
    with assert_raises(contains="`COUNT`"):
        _ = parse_pcd_header(
            text_bytes("FIELDS x y\nSIZE 4 4\nTYPE F F\nCOUNT 1\nDATA ascii\n")
        )
    with assert_raises(contains="a size its type"):
        _ = parse_pcd_header(
            text_bytes("FIELDS x\nSIZE 2\nTYPE F\nDATA ascii\n")
        )
    with assert_raises(contains="count below one"):
        _ = parse_pcd_header(
            text_bytes("FIELDS x\nSIZE 4\nTYPE F\nCOUNT 0\nDATA ascii\n")
        )
    with assert_raises(contains="field type"):
        _ = parse_pcd_header(text_bytes("FIELDS x\nTYPE D\nDATA ascii\n"))


def test_header_check_refuses_what_parsing_cannot_make() raises:
    var header = PcdHeader()
    header.data = PcdDataFormat(5)
    with assert_raises(contains="not valid"):
        header.check()
    header.data = PCD_ASCII
    header.points = -1
    with assert_raises(contains="negative number"):
        header.check()


def test_ascii_counts_integer_colors_and_crlf() raises:
    # `v` has two values, so `y` is the third column; `rgb` is a `U`.
    var file = (
        "FIELDS x v y z rgb\r\nSIZE 4 4 4 4 4\r\nTYPE F F F F U\r\n"
        "COUNT 1 2 1 1 1\r\nPOINTS 1\r\nDATA ascii\r\n"
        "1 9 9 2 3 16711680\r\n\r\n"
    )
    var model = parse_pcd(text_bytes(file))
    assert_list(
        model.geometry.clone_attribute(String(POSITION)).packed(), [1, 2, 3]
    )
    assert_list(
        model.geometry.clone_attribute(String(COLOR)).packed(), [1, 0, 0]
    )
    assert_false(model.geometry.has_attribute(String(NORMAL)))
    assert_equal(len(model.labels), 0)


def test_ascii_refusals() raises:
    var head = "FIELDS x y z\nSIZE 4 4 4\nTYPE F F F\nDATA ascii\n"
    with assert_raises(contains="fewer values"):
        _ = parse_pcd(text_bytes(head + "1 2\n"))
    with assert_raises(contains="not a number"):
        _ = parse_pcd(text_bytes(head + "1 2 z\n"))
    with assert_raises(contains="finite"):
        _ = parse_pcd(text_bytes(head + "1 2 1e39\n"))
    with assert_raises(contains="all of `x`"):
        _ = parse_pcd(
            text_bytes("FIELDS x y\nSIZE 4 4\nTYPE F F\nDATA ascii\n")
        )
    with assert_raises(contains="all of `normal_x`"):
        _ = parse_pcd(
            text_bytes("FIELDS normal_x\nSIZE 4\nTYPE F\nDATA ascii\n")
        )
    with assert_raises(contains="four bytes"):
        _ = parse_pcd(text_bytes("FIELDS rgb\nSIZE 2\nTYPE U\nDATA ascii\n"))
    with assert_raises(contains="whole number"):
        _ = parse_pcd(
            text_bytes("FIELDS label\nSIZE 4\nTYPE F\nDATA ascii\n2.5\n")
        )


def test_an_empty_cloud_has_no_attributes() raises:
    var model = parse_pcd(
        text_bytes("FIELDS x y z\nSIZE 4 4 4\nTYPE F F F\nDATA ascii\n")
    )
    assert_false(model.geometry.has_attribute(String(POSITION)))
    assert_false(model.geometry.has_attribute(String(INTENSITY)))


def binary_head(format: String, points: Int) -> String:
    """Return a header of `x y z`, a two-count `extra`, and `label`."""
    return (
        "FIELDS x y z extra label\nSIZE 4 4 4 2 8\nTYPE F F F U I\n"
        "COUNT 1 1 1 2 1\nPOINTS "
        + String(points)
        + "\nDATA "
        + format
        + "\n"
    )


def test_binary_counts_and_wide_labels() raises:
    var bytes = text_bytes(binary_head("binary", 2))
    for point in range(2):
        put_f32(bytes, Float32(point))
        put_f32(bytes, Float32(point) + 0.5)
        put_f32(bytes, -1)
        put(bytes, 7, 2)
        put(bytes, 8, 2)
        put(bytes, UInt64(bitcast[DType.uint64](Int64(-5 - point))), 8)
    var model = parse_pcd(bytes)
    assert_equal(model.header.row_size, 24)
    assert_list(
        model.geometry.clone_attribute(String(POSITION)).packed(),
        [0, 0.5, -1, 1, 1.5, -1],
    )
    assert_equal(model.labels, [-5, -6])
    bytes.resize(len(bytes) - 1, 0)
    with assert_raises(contains="ends before its 2 points"):
        _ = parse_pcd(bytes)


def test_binary_compressed_counts() raises:
    var columns = List[UInt8]()
    for axis in range(3):
        for point in range(2):
            put_f32(columns, Float32(point * 10 + axis))
    for _ in range(4):
        put(columns, 1, 2)
    put(columns, 11, 8)
    put(columns, 12, 8)
    # One literal run of every byte, in runs of at most 32.
    var packed = List[UInt8]()
    var at = 0
    while at < len(columns):
        var run = min(32, len(columns) - at)
        packed.append(UInt8(run - 1))
        for index in range(run):
            packed.append(columns[at + index])
        at += run
    var bytes = text_bytes(binary_head("binary_compressed", 2))
    put(bytes, UInt64(len(packed)), 4)
    put(bytes, UInt64(len(columns)), 4)
    bytes.extend(packed.copy())
    var model = parse_pcd(bytes)
    assert_list(
        model.geometry.clone_attribute(String(POSITION)).packed(),
        [0, 1, 2, 10, 11, 12],
    )
    assert_equal(model.labels, [11, 12])

    var short = text_bytes(binary_head("binary_compressed", 2))
    put(short, 4, 2)
    with assert_raises(contains="compressed sizes"):
        _ = parse_pcd(short)
    var cut = text_bytes(binary_head("binary_compressed", 2))
    put(cut, UInt64(len(packed) + 1), 4)
    put(cut, UInt64(len(columns)), 4)
    cut.extend(packed.copy())
    with assert_raises(contains="inside its compressed data"):
        _ = parse_pcd(cut)
    var small = text_bytes(binary_head("binary_compressed", 3))
    put(small, UInt64(len(packed)), 4)
    put(small, UInt64(len(columns)), 4)
    small.extend(packed^)
    with assert_raises(contains="too small"):
        _ = parse_pcd(small)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
