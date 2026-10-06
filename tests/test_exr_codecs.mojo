# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Missing EXR codecs against independent OpenEXR 3.1.5 decode fixtures."""

from render.exr import (
    decode,
    read_header,
    lines_per_block,
    ExrChannel,
    HALF_SAMPLES,
    FLOAT_SAMPLES,
    _DwaScheme,
    _DwaAcCompression,
    _dwa_decode,
    _pxr24_decode,
    _b44_decode,
    _inflate_exact,
    _dwa_lower,
    _sort_dwa_prefixes,
    _half_bits,
)
from render.png import zlib_stream
from render.texture import float_from_bytes
from std.testing import TestSuite, assert_equal, assert_true, assert_raises
from std.math import isfinite


def fixture_hex(path: String) raises -> List[UInt8]:
    """Read a whitespace-separated UTF-8 hex fixture without Python."""
    var text = open(path, "r").read_bytes()
    var result = List[UInt8]()
    var high = -1
    for byte in text:
        var c = Int(byte)
        if c == 10 or c == 13 or c == 32:
            continue
        var nibble = c - 48 if c <= 57 else c - 97 + 10
        if nibble < 0 or nibble > 15:
            raise Error("Invalid fixture hex")
        if high < 0:
            high = nibble
        else:
            result.append(UInt8(high * 16 + nibble))
            high = -1
    if high >= 0:
        raise Error("Odd fixture hex")
    return result^


def check_fixture(name: String, codec: Int) raises:
    """Compare every RGBA sample with a separately decoded reference."""
    var base = "assets/exr_codecs/" + name + ".exr"
    var bytes = fixture_hex(base + ".hex")
    var expected = fixture_hex(base + ".rgba.hex")
    var image = decode(bytes)
    assert_equal(len(expected), len(image.pixels) * 4)
    var max_error = Float32(0)
    var max_half_ulps = 0
    for i in range(len(image.pixels)):
        var at = i * 4
        var reference = float_from_bytes(
            expected[at], expected[at + 1], expected[at + 2], expected[at + 3]
        )
        var got = image.pixels[i]
        assert_true(isfinite(got), name)
        var error = abs(got - reference) / max(Float32(1), abs(reference))
        max_error = max(max_error, error)
        if codec >= 8 and got != reference:
            var got_bits = _half_bits(got)
            var ref_bits = _half_bits(reference)
            var got_order = (
                0x8000 - (got_bits & 0x7FFF) if got_bits
                & 0x8000 else 0x8000 + got_bits
            )
            var ref_order = (
                0x8000 - (ref_bits & 0x7FFF) if ref_bits
                & 0x8000 else 0x8000 + ref_bits
            )
            max_half_ulps = max(max_half_ulps, abs(got_order - ref_order))
        if (
            codec < 8
            or i % 4 == 3
            or name.endswith("_unknown")
            or name.endswith("_rle")
            or name.endswith("_uppercase_rule")
            or name.endswith("_incomplete_csc")
            or name.endswith("_incomplete_rle")
        ):
            assert_equal(got, reference, name + " sample " + String(i))
        else:
            assert_true(
                error <= 0.003,
                name
                + " sample "
                + String(i)
                + " got "
                + String(got)
                + " expected "
                + String(reference),
            )
    print(name, "max scaled error", max_error, "max half ULPs", max_half_ulps)


def test_all_five_codecs_against_openexr() raises:
    for codec in range(5, 10):
        for shape in range(9):
            check_fixture("c" + String(codec) + "_s" + String(shape), codec)


def test_dwa_variants_against_openexr() raises:
    var variants: List[String] = [
        "deflate",
        "legacy0",
        "legacy1",
        "insensitive",
        "rule_shadow",
        "uppercase_rule",
        "incomplete_csc",
        "incomplete_rle",
        "unknown",
        "rle",
    ]
    for codec in range(8, 10):
        for variant in variants:
            check_fixture("c" + String(codec) + "_" + variant, codec)


def _set32(mut bytes: List[UInt8], at: Int, value: Int):
    """Replace a fixture's bounded little-endian word."""
    for i in range(4):
        bytes[at + i] = UInt8((value >> (i * 8)) & 255)


def _first_block(bytes: List[UInt8]) raises -> Int:
    """Locate the first compressed payload in a trusted fixture."""
    var header = read_header(bytes)
    var per = lines_per_block(header.compression)
    return header.start + 8 * ((header.height() + per - 1) // per) + 8


def test_every_truncated_fixture_is_refused() raises:
    for codec in range(5, 10):
        var bytes = fixture_hex(
            "assets/exr_codecs/c" + String(codec) + "_s0.exr.hex"
        )
        for end in range(len(bytes)):
            with assert_raises():
                _ = decode(List[UInt8](bytes[:end]))


def test_dwa_counters_and_rules_are_bounded() raises:
    var original = fixture_hex("assets/exr_codecs/c8_s0.exr.hex")
    var block = _first_block(original)
    for counter in range(11):
        var bytes = original.copy()
        for i in range(8):
            bytes[block + counter * 8 + i] = 255
        with assert_raises(contains="DWA"):
            _ = decode(bytes)
    # Individual compressed ranges fit the file, but their sum does not.
    var bytes = original.copy()
    _set32(bytes, block + 16, len(bytes) - block)
    with assert_raises():
        _ = decode(bytes)
    # Rule table underflow, overflow and an unterminated suffix.
    for size in [0, 1, 65535]:
        bytes = original.copy()
        bytes[block + 88] = UInt8(size & 255)
        bytes[block + 89] = UInt8(size >> 8)
        with assert_raises():
            _ = decode(bytes)
    bytes = original.copy()
    var rule_end = (
        block + 88 + Int(bytes[block + 88]) + (Int(bytes[block + 89]) << 8)
    )
    for i in range(block + 90, rule_end):
        bytes[i] = 65
    with assert_raises():
        _ = decode(bytes)
    # The first rule is R, then scheme/csc and type.
    for flags in [12, 68, 18, 24]:
        bytes = original.copy()
        bytes[block + 92] = UInt8(flags)
        with assert_raises(contains="DWA"):
            _ = decode(bytes)
    for kind in [0, 3, 255]:
        bytes = original.copy()
        bytes[block + 93] = UInt8(kind)
        with assert_raises(contains="DWA"):
            _ = decode(bytes)


def _words(values: List[Int]) -> List[UInt8]:
    """Encode trusted half bit patterns for hostile DWA coefficient tests."""
    var out = List[UInt8]()
    for value in values:
        out.append(UInt8(value & 255))
        out.append(UInt8((value >> 8) & 255))
    return out^


def _zip_predict(bytes: List[UInt8]) -> List[UInt8]:
    """Apply ZIP's even/odd split and byte predictor before stored zlib."""
    var split = List[UInt8]()
    for i in range(0, len(bytes), 2):
        split.append(bytes[i])
    for i in range(1, len(bytes), 2):
        split.append(bytes[i])
    var previous = UInt8(0)
    for i in range(len(split)):
        var next = split[i]
        if i > 0:
            split[i] = next - previous + 128
        previous = next
    return zlib_stream(split)


def _dwa_test_stream(ac: List[Int], dc: List[Int]) -> List[UInt8]:
    """Build a checked one-channel DWA header around arbitrary tokens."""
    var a = zlib_stream(_words(ac))
    var d = _zip_predict(_words(dc))
    var fields: List[Int] = [
        2,
        0,
        0,
        len(a),
        len(d),
        0,
        0,
        0,
        len(ac),
        len(dc),
        1,
    ]
    var out = List[UInt8](length=88, fill=0)
    for i in range(11):
        _set32(out, i * 8, fields[i])
    out.extend([6, 0, 89, 0, 4, 1])
    out.extend(a^)
    out.extend(d^)
    return out^


def _dwa_test_decode(bytes: List[UInt8]) raises -> List[UInt8]:
    """Decode a complete 8-by-8 half-luminance DWA payload."""
    return _dwa_decode(
        bytes, 0, len(bytes), 8, 8, [ExrChannel("Y", HALF_SAMPLES, 1, 1)]
    )


def test_dwa_coefficients_are_bounded_and_finite() raises:
    assert_equal(len(_dwa_test_decode(_dwa_test_stream([0xFF00], [0]))), 128)
    for token in [0xFF40, 0xFFFF, 0x7C00, 0x7E00, 0xFC00]:
        with assert_raises(contains="DWA"):
            _ = _dwa_test_decode(_dwa_test_stream([token], [0]))
    with assert_raises(contains="finite"):
        _ = _dwa_test_decode(_dwa_test_stream([0xFF00], [0x7C00]))
    with assert_raises(contains="AC data"):
        _ = _dwa_test_decode(_dwa_test_stream([0], [0]))
    with assert_raises(contains="trailing values"):
        _ = _dwa_test_decode(_dwa_test_stream([0xFF00, 0], [0]))
    with assert_raises(contains="counts"):
        _ = _dwa_test_decode(_dwa_test_stream([], [0]))
    with assert_raises(contains="counts"):
        _ = _dwa_test_decode(_dwa_test_stream([0xFF00], []))
    with assert_raises(contains="counter"):
        _ = _dwa_test_decode(
            _dwa_test_stream(List[Int](length=64, fill=0), [0])
        )
    var bytes = _dwa_test_stream([0xFF00], [0])
    bytes.append(0)
    with assert_raises(contains="trailing bytes"):
        _ = _dwa_test_decode(bytes)
    bytes = _dwa_test_stream([0xFF00], [0])
    _set32(bytes, 64, 2)
    with assert_raises(contains="wrong length"):
        _ = _dwa_test_decode(bytes)


def _dwa_rle_stream(encoded: List[UInt8]) -> List[UInt8]:
    """Build a pure-RLE DWA stream with an exact 128-byte layout."""
    var data = zlib_stream(encoded)
    var out = List[UInt8](length=88, fill=0)
    _set32(out, 0, 2)
    _set32(out, 40, len(data))
    _set32(out, 48, len(encoded))
    _set32(out, 56, 128)
    out.extend([6, 0, 89, 0, 8, 1])
    out.extend(data^)
    return out^


def test_dwa_rle_and_unknown_stream_sizes_are_exact() raises:
    assert_equal(len(_dwa_test_decode(_dwa_rle_stream([127, 0]))), 128)
    var encoded_runs: List[List[UInt8]] = [[128], [127, 0, 0, 0], [126, 0]]
    for encoded in encoded_runs:
        with assert_raises():
            _ = _dwa_test_decode(_dwa_rle_stream(encoded))
    var bytes = _dwa_rle_stream([127, 0])
    _set32(bytes, 48, 257)
    with assert_raises(contains="counter"):
        _ = _dwa_test_decode(bytes)
    bytes = fixture_hex("assets/exr_codecs/c8_unknown.exr.hex")
    var at = _first_block(bytes)
    _set32(bytes, at + 8, 1)
    with assert_raises(contains="channel sizes"):
        _ = decode(bytes)
    bytes = fixture_hex("assets/exr_codecs/c8_rle.exr.hex")
    at = _first_block(bytes)
    _set32(bytes, at + 56, 1)
    with assert_raises(contains="channel sizes"):
        _ = decode(bytes)


def test_pxr24_and_b44_payloads_are_checked() raises:
    var channels: List[ExrChannel] = [ExrChannel("Y", HALF_SAMPLES, 1, 1)]
    var packed = zlib_stream([UInt8(0)])
    with assert_raises(contains="wrong length"):
        _ = _pxr24_decode(packed, 0, len(packed), 4, 4, channels)
    packed = zlib_stream(List[UInt8](length=33, fill=0))
    with assert_raises():
        _ = _pxr24_decode(packed, 0, len(packed), 4, 4, channels)
    var packed_blocks: List[List[UInt8]] = [[0], [0, 0, 0], [0, 0, 252, 0]]
    for packed_block in packed_blocks:
        with assert_raises():
            _ = _b44_decode(packed_block, 0, len(packed_block), 4, 4, channels)
    var float_channels: List[ExrChannel] = [
        ExrChannel("Y", FLOAT_SAMPLES, 1, 1)
    ]
    with assert_raises(contains="cut short"):
        _ = _b44_decode([0, 0, 0], 0, 3, 4, 4, float_channels)
    # Direct private boundaries also reject ranges outside the file.
    with assert_raises(contains="cut short"):
        _ = _b44_decode([0], -1, 1, 4, 4, channels)
    with assert_raises(contains="dimensions"):
        _ = _pxr24_decode([0], 0, 1, 0, 1, channels)
    with assert_raises(contains="too large"):
        _ = _pxr24_decode([0], 0, 1, 1 << 62, 256, channels)


def test_headers_and_chunk_coverage_are_checked_before_decode() raises:
    var bytes = fixture_hex("assets/exr_codecs/c8_s0.exr.hex")
    var at = _first_block(bytes)
    var size = (
        Int(bytes[at - 4])
        | (Int(bytes[at - 3]) << 8)
        | (Int(bytes[at - 2]) << 16)
        | (Int(bytes[at - 1]) << 24)
    )
    # A repeated first strip leaves another strip missing.
    _set32(bytes, at + size, 0)
    with assert_raises(contains="overlapping"):
        _ = decode(bytes)
    bytes = fixture_hex("assets/exr_codecs/c8_s0.exr.hex")
    _set32(bytes, at - 8, 1)
    with assert_raises(contains="misaligned"):
        _ = decode(bytes)
    bytes = fixture_hex("assets/exr_codecs/c8_s0.exr.hex")
    _set32(bytes, at - 4, 100000)
    with assert_raises(contains="larger"):
        _ = decode(bytes)
    # pLinear sits four bytes after the first channel's sample type.
    var channel_start = 8 + 9 + 7 + 4
    bytes = fixture_hex("assets/exr_codecs/c8_s0.exr.hex")
    bytes[channel_start + 6] = 2
    with assert_raises(contains="pLinear"):
        _ = decode(bytes)
    bytes = fixture_hex("assets/exr_codecs/c8_s0.exr.hex")
    bytes[channel_start + 18] = 65
    with assert_raises(contains="duplicate"):
        _ = decode(bytes)


def test_internal_dwa_modes_validate_unknown_values() raises:
    assert_true(_DwaScheme(0).is_valid())
    assert_true(_DwaScheme(2).is_valid())
    assert_true(not _DwaScheme(-1).is_valid())
    assert_true(not _DwaScheme(3).is_valid())
    assert_true(_DwaAcCompression(0).is_valid())
    assert_true(_DwaAcCompression(1).is_valid())
    assert_true(not _DwaAcCompression(2).is_valid())


def test_stream_and_coefficient_byte_budgets_precede_allocation() raises:
    with assert_raises(contains="byte budget"):
        _ = _inflate_exact([0], 0, 1, (1 << 30) + 1)
    var bytes = _dwa_test_stream([0xFF00], [0])
    _set32(bytes, 64, (1 << 27) + 1)
    with assert_raises(contains="counter"):
        _ = _dwa_decode(
            bytes,
            0,
            len(bytes),
            1 << 28,
            1,
            [ExrChannel("Y", HALF_SAMPLES, 1, 1)],
        )


def test_dwa_prefix_sort_and_ascii_rule_folding() raises:
    var prefixes: List[String] = ["z", "", "x.y", "a", "x", "aa", "a"]
    _sort_dwa_prefixes(prefixes)
    var expected: List[String] = ["", "a", "a", "aa", "x", "x.y", "z"]
    assert_equal(prefixes, expected)
    assert_equal(_dwa_lower("RgB.Y"), "rgb.y")
    assert_equal(_dwa_lower(chr(192) + "Y"), chr(192) + "y")


def test_many_channel_prefixes_have_bounded_work() raises:
    var channels = List[ExrChannel]()
    for i in range(20000):
        channels.append(
            ExrChannel("layer" + String(20000 - i) + ".Z", HALF_SAMPLES, 1, 1)
        )
    var payload = zlib_stream(List[UInt8](length=40000, fill=0))
    var bytes = List[UInt8](length=88, fill=0)
    _set32(bytes, 0, 2)
    _set32(bytes, 8, 40000)
    _set32(bytes, 16, len(payload))
    bytes.extend([2, 0])
    bytes.extend(payload^)
    assert_equal(len(_dwa_decode(bytes, 0, len(bytes), 1, 1, channels)), 40000)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
