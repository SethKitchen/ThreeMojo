# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Regression tests for splat metadata bounds before allocation or reads."""

from loaders.gltf_gaussian_splat import _buffers, _read_accessor
from loaders.json import parse_json
from loaders.ksplat import ksplat_components, parse_ksplat
from loaders.spz import parse_raw_spz, parse_raw_spz_v4, spz_vectors
from std.testing import TestSuite, assert_equal, assert_raises
from test_gaussian_splat_loaders import (
    ksplat,
    one_splat_streams,
    put_u16,
    put_u32,
    raw_spz,
    read,
    section,
    spz4,
    zeros,
)


def test_a_splat_accessor_cannot_read_before_its_view() raises:
    var document = parse_json(
        '{"accessors":[{"bufferView":0,"byteOffset":-4,'
        '"componentType":5126,"count":1,"type":"SCALAR"}],'
        '"bufferViews":[{"buffer":0,"byteOffset":4,"byteLength":4}]}'
    )
    var buffers: List[List[UInt8]] = [zeros(8)]
    with assert_raises():
        _ = _read_accessor(document, buffers, 0)


def test_the_direct_spz4_parser_checks_its_magic_and_version() raises:
    var bytes = spz4(1, 0, one_splat_streams())
    bytes[0] = 0
    with assert_raises():
        _ = parse_raw_spz_v4(bytes)
    bytes = spz4(1, 0, one_splat_streams())
    put_u32(bytes, 4, 3)
    with assert_raises():
        _ = parse_raw_spz_v4(bytes)


def test_compressed_ksplat_centers_need_a_complete_bucket() raises:
    # The old parser reads the first row as its bucket's center.
    var bytes = ksplat(1, 1, 1)
    section(bytes, 0, 1, 1)
    bytes.extend(zeros(24))
    with assert_raises():
        _ = parse_ksplat(bytes)
    # A bucket shorter than three floats must not read into the row either.
    put_u32(bytes, 4096 + 8, 1)
    put_u32(bytes, 4096 + 12, 1)
    put_u32(bytes, 4096 + 32, 1)
    put_u16(bytes, 4096 + 20, 4)
    bytes.extend(zeros(4))
    with assert_raises():
        _ = parse_ksplat(bytes)


def test_splat_accessors_reject_invalid_metadata_before_allocation() raises:
    var accessors: List[String] = [
        '"count":-1,"bufferView":0',
        '"count":10000001,"bufferView":0',
        '"count":1,"bufferView":0,"byteOffset":2',
        '"count":1,"bufferView":0,"byteOffset":8',
        '"count":1,"byteOffset":4',
        '"count":1,"bufferView":-1',
        '"count":1,"bufferView":1',
    ]
    var buffers: List[List[UInt8]] = [zeros(8)]
    for fields in accessors:
        var document = parse_json(
            '{"accessors":[{"componentType":5126,"type":"SCALAR",'
            + fields
            + '}],"bufferViews":[{"buffer":0,"byteLength":4}]}'
        )
        with assert_raises():
            _ = _read_accessor(document, buffers, 0)
    var views: List[String] = [
        '"buffer":-1,"byteLength":4',
        '"buffer":1,"byteLength":4',
        '"buffer":0,"byteLength":-1',
        '"buffer":0,"byteLength":2',
        '"buffer":0,"byteLength":9',
        '"buffer":0,"byteOffset":-4,"byteLength":4',
        '"buffer":0,"byteOffset":9,"byteLength":0',
        '"buffer":0,"byteOffset":2,"byteLength":4',
        '"buffer":0,"byteOffset":4,"byteLength":9223372036854775807',
        '"buffer":0,"byteLength":8,"byteStride":-4',
        '"buffer":0,"byteLength":8,"byteStride":0',
        '"buffer":0,"byteLength":8,"byteStride":2',
        '"buffer":0,"byteLength":8,"byteStride":6',
        '"buffer":0,"byteLength":8,"byteStride":256',
    ]
    for fields in views:
        var document = parse_json(
            '{"accessors":[{"componentType":5126,"type":"SCALAR",'
            '"count":1,"bufferView":0}],"bufferViews":[{'
            + fields
            + "}]}"
        )
        with assert_raises():
            _ = _read_accessor(document, buffers, 0)


def test_an_empty_accessor_still_checks_its_buffer_view() raises:
    var buffers: List[List[UInt8]] = [zeros(4)]
    var document = parse_json(
        '{"accessors":[{"bufferView":0,"componentType":5126,"count":0,'
        '"type":"SCALAR"}],"bufferViews":[{"buffer":0,"byteLength":8}]}'
    )
    with assert_raises():
        _ = _read_accessor(document, buffers, 0)


def test_spz_stream_lengths_do_not_wrap_signed_integers() raises:
    for high in [1, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF]:
        var bytes = spz4(1, 0, one_splat_streams())
        put_u32(bytes, 20, 0xFFFFFFFF)
        put_u32(bytes, 24, high)
        with assert_raises(contains="stream is past the end"):
            _ = parse_raw_spz_v4(bytes)


def test_spz_tables_cannot_overlap_the_header() raises:
    var bytes = spz4(0, 0, List[List[UInt8]]())
    put_u32(bytes, 16, 0)
    with assert_raises(contains="table of contents"):
        _ = parse_raw_spz_v4(bytes)
    put_u32(bytes, 16, len(bytes) + 1)
    with assert_raises(contains="table of contents"):
        _ = parse_raw_spz_v4(bytes)
    put_u32(bytes, 16, 20)
    assert_equal(parse_raw_spz_v4(bytes).count(), 0)


def test_the_raw_spz_splat_limit_matches_version_four() raises:
    var bytes = raw_spz(2, 0, 0, 0)
    put_u32(bytes, 8, 10000001)
    with assert_raises(contains="too many splats"):
        _ = parse_raw_spz(bytes)


def test_negative_harmonic_degrees_raise_an_error() raises:
    with assert_raises(contains="degree -1"):
        _ = ksplat_components(-1)
    with assert_raises(contains="degree -1"):
        _ = spz_vectors(-1)


def test_ksplat_bucket_counts_must_describe_the_stored_table() raises:
    for field in [8, 32, 36]:
        var bytes = read("level1.ksplat")
        put_u32(bytes, 4096 + field, 0 if field == 8 else 0xFFFFFFFF)
        with assert_raises(contains="KSPLAT"):
            _ = parse_ksplat(bytes)
    # An uncompressed section still must not read a truncated bucket table.
    var bytes = ksplat(0, 1, 1)
    section(bytes, 0, 1, 1)
    put_u32(bytes, 4096 + 12, 1000)
    bytes.extend(zeros(44))
    with assert_raises(contains="invalid KSPLAT bucket data"):
        _ = parse_ksplat(bytes)


def test_gltf_buffer_lengths_bound_the_bytes_available_to_views() raises:
    var binary = zeros(8)
    var document = parse_json('{"buffers":[{"byteLength":4}]}')
    var buffers = _buffers(document, binary, "")
    assert_equal(len(buffers[0]), 4)
    document = parse_json(
        '{"buffers":[{"byteLength":4}],"accessors":[{"bufferView":0,'
        '"componentType":5126,"type":"SCALAR","count":1}],'
        '"bufferViews":[{"buffer":0,"byteOffset":4,"byteLength":4}]}'
    )
    with assert_raises(contains="past its buffer"):
        _ = _read_accessor(document, buffers, 0)
    for text in [
        '{"buffers":[{"byteLength":-1}]}',
        '{"buffers":[{"byteLength":9}]}',
        '{"buffers":[{"byteLength":4},{"byteLength":4}]}',
        '{"buffers":[{"byteLength":2,"uri":"data:;base64,AA=="}]}',
    ]:
        document = parse_json(text)
        with assert_raises(contains="glTF"):
            _ = _buffers(document, binary, "")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
