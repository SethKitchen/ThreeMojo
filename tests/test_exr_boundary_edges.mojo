# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Small EXR guard fixtures; refused dimensions never allocate image storage."""

from render.exr import (
    ExrChannel,
    HALF_SAMPLES,
    FLOAT_SAMPLES,
    _need,
    _channels,
    _channel_bytes,
    _block_bytes,
    _inflate_exact,
    _checked_channel_bytes,
    _dwa_rules,
    _b44_linear,
    _dwa_linear,
    _dwa_prefix,
    _dwa_lower,
    _dwa_group,
    _dwa_decode,
    _store_word,
)
from render.png import MAX_PIXELS, zlib_stream
from tests.test_exr import channel
from tests.test_exr_codecs import _set32, _words, _zip_predict
from std.testing import TestSuite, assert_equal, assert_raises


def test_checked_ranges_reject_negative_count_and_past_end_start() raises:
    _need(0, 0, 0)
    _need(3, 3, 0)
    with assert_raises(contains="cut short"):
        _need(3, 0, -1)
    with assert_raises(contains="cut short"):
        _need(3, 4, 0)


def test_channel_list_requires_an_entry_name_and_final_null() raises:
    var unnamed = channel("", 1)
    unnamed.append(0)
    with assert_raises(contains="empty or duplicate"):
        _ = _channels(unnamed, 0, len(unnamed))
    var no_terminator = channel("Y", 1)
    with assert_raises(contains="final null"):
        _ = _channels(no_terminator, 0, len(no_terminator))
    var bad_terminator = channel("Y", 1)
    bad_terminator.append(1)
    with assert_raises(contains="final null"):
        _ = _channels(bad_terminator, 0, len(bad_terminator))


def test_empty_channels_and_each_block_dimension_are_refused() raises:
    var channels: List[ExrChannel] = [ExrChannel("Y", HALF_SAMPLES, 1, 1)]
    assert_equal(_channel_bytes([]), 0)
    assert_equal(_block_bytes(1, 1, channels), 2)
    with assert_raises(contains="dimensions"):
        _ = _block_bytes(1, 0, channels)
    with assert_raises(contains="dimensions"):
        _ = _block_bytes(1, 1, [])
    # Three Float32 channels exceed the four-byte-per-pixel total budget.
    # This guard runs before allocation; only these three records exist.
    channels = [
        ExrChannel("R", FLOAT_SAMPLES, 1, 1),
        ExrChannel("G", FLOAT_SAMPLES, 1, 1),
        ExrChannel("B", FLOAT_SAMPLES, 1, 1),
    ]
    with assert_raises(contains="too large"):
        _ = _block_bytes(MAX_PIXELS, 1, channels)


def test_empty_compressed_stream_matches_only_zero_output() raises:
    assert_equal(len(_inflate_exact([], 0, 0, 0)), 0)
    with assert_raises(contains="missing"):
        _ = _inflate_exact([], 0, 0, 1)
    with assert_raises(contains="byte budget"):
        _ = _inflate_exact([], 0, 0, -1)


def test_half_lookup_nonfinite_and_negative_values_are_zero() raises:
    for bits in [0x7C00, 0x7E00, 0xFC00, 0xFE00]:
        assert_equal(_b44_linear(bits), 0)
        assert_equal(_dwa_linear(bits), 0)
    assert_equal(_b44_linear(0xBC00), 0)
    assert_equal(_b44_linear(0x8001), 0)
    assert_equal(_b44_linear(0x3C00), 0)
    assert_equal(_dwa_linear(0x3C00), 0x3C00)
    assert_equal(_dwa_linear(0xBC00), 0xBC00)


def test_empty_dwa_names_and_zero_width_store_are_noops() raises:
    var parts = _dwa_prefix("")
    assert_equal(parts[0], "")
    assert_equal(parts[1], "")
    assert_equal(_dwa_lower(""), "")
    var bytes: List[UInt8] = [17]
    _store_word(bytes, 1, 255, 0)
    assert_equal(bytes[0], UInt8(17))


def test_dwa_group_refuses_each_short_dc_condition_before_decode() raises:
    var out = List[UInt8](length=2, fill=17)
    var channels: List[ExrChannel] = [ExrChannel("Y", HALF_SAMPLES, 1, 1)]
    for dc_start in [0, 1]:
        var ac_at = 0
        var dc_at = dc_start
        with assert_raises(contains="DC data"):
            _dwa_group(out, [], [], ac_at, dc_at, [0], channels, [0], 1, 1, 2)
        assert_equal(out[0], UInt8(17))
        assert_equal(out[1], UInt8(17))


def _group_stream(assignments: List[Int], dct: Bool) -> List[UInt8]:
    """Build CSC rules and two bounded 8-by-8 HALF channels."""
    var ac = List[UInt8]()
    var dc = List[UInt8]()
    var unknown = List[UInt8]()
    if dct:
        ac = zlib_stream(_words([0xFF00, 0xFF00]))
        dc = _zip_predict(_words([0, 0]))
    else:
        unknown = zlib_stream(List[UInt8](length=256, fill=0))
    var bytes = List[UInt8](length=88, fill=0)
    _set32(bytes, 0, 2)
    _set32(bytes, 8, 0 if dct else 256)
    _set32(bytes, 16, len(unknown))
    _set32(bytes, 24, len(ac))
    _set32(bytes, 32, len(dc))
    _set32(bytes, 64, 2 if dct else 0)
    _set32(bytes, 72, 2 if dct else 0)
    _set32(bytes, 80, 1)
    bytes.extend([UInt8(2 + len(assignments) * 4), UInt8(0)])
    for component in range(len(assignments)):
        bytes.append(UInt8(89 + assignments[component]))
        bytes.append(0)
        bytes.append(UInt8((component + 1) * 16 + (4 if dct else 0)))
        bytes.append(1)
    bytes.extend(unknown^)
    bytes.extend(ac^)
    bytes.extend(dc^)
    return bytes^


def test_dwa_color_group_rejects_every_repeated_channel_pair() raises:
    var channels: List[ExrChannel] = [
        ExrChannel("Y", HALF_SAMPLES, 1, 1),
        ExrChannel("Z", HALF_SAMPLES, 1, 1),
    ]
    var cases: List[List[Int]] = [[0, 0, 1], [0, 1, 0], [0, 1, 1]]
    for assignments in cases:
        var bytes = _group_stream(assignments, True)
        with assert_raises(contains="repeats a channel"):
            _ = _dwa_decode(bytes, 0, len(bytes), 8, 8, channels)


def test_incomplete_dwa_color_group_decodes_standalone_channels() raises:
    var bytes = _group_stream([0, 1], True)
    var channels: List[ExrChannel] = [
        ExrChannel("Y", HALF_SAMPLES, 1, 1),
        ExrChannel("Z", HALF_SAMPLES, 1, 1),
    ]
    var got = _dwa_decode(bytes, 0, len(bytes), 8, 8, channels)
    assert_equal(got, List[UInt8](length=256, fill=0))


def test_dwa_color_group_requires_dct_scheme() raises:
    var channels: List[ExrChannel] = [
        ExrChannel("Y", HALF_SAMPLES, 1, 1),
        ExrChannel("Z", HALF_SAMPLES, 1, 1),
        ExrChannel("R", HALF_SAMPLES, 1, 1),
    ]
    var unknown = zlib_stream(List[UInt8](length=384, fill=0))
    var bytes = List[UInt8](length=88, fill=0)
    _set32(bytes, 0, 2)
    _set32(bytes, 8, 384)
    _set32(bytes, 16, len(unknown))
    bytes.extend([14, 0, 89, 0, 16, 1, 90, 0, 32, 1, 82, 0, 48, 1])
    bytes.extend(unknown^)
    with assert_raises(contains="must use DCT"):
        _ = _dwa_decode(bytes, 0, len(bytes), 8, 8, channels)


def test_dwa_rle_budget_uses_only_its_own_channels() raises:
    # The whole image has 256 decoded bytes, but its RLE channel has 128.
    # A declared 257-byte RLE stream fits the total budget, not that channel.
    var bytes = List[UInt8](length=88, fill=0)
    _set32(bytes, 0, 2)
    _set32(bytes, 8, 128)
    _set32(bytes, 48, 257)
    _set32(bytes, 56, 128)
    bytes.extend([6, 0, 89, 0, 8, 1])
    var channels: List[ExrChannel] = [
        ExrChannel("Y", HALF_SAMPLES, 1, 1),
        ExrChannel("Z", HALF_SAMPLES, 1, 1),
    ]
    with assert_raises(contains="RLE data exceeds"):
        _ = _dwa_decode(bytes, 0, len(bytes), 8, 8, channels)


def test_channel_byte_total_is_checked_without_large_allocations() raises:
    assert_equal(_checked_channel_bytes(0), 0)
    assert_equal(_checked_channel_bytes(MAX_PIXELS), MAX_PIXELS)
    with assert_raises(contains="channel layout is too large"):
        _ = _checked_channel_bytes(MAX_PIXELS + 1)


def test_empty_dwa_group_work_preserves_output_and_cursors() raises:
    # This internal helper has no positive-size precondition. Zero block
    # count or zero components must leave its caller-owned buffers intact.
    var channels: List[ExrChannel] = [ExrChannel("Y", HALF_SAMPLES, 1, 1)]
    for variant in range(3):
        var width = 0 if variant == 0 else 1
        var lines = 0 if variant == 1 else 1
        var group: List[Int] = [] if variant == 2 else [0]
        var output = List[UInt8](length=2, fill=17)
        var ac_at = 0
        var dc_at = 0
        _dwa_group(
            output, [], [], ac_at, dc_at, group, channels, [0], width, lines, 2
        )
        assert_equal(output, List[UInt8](length=2, fill=17))
        assert_equal(ac_at, 0)
        assert_equal(dc_at, 0)


def test_dwa_csc_byte_boundaries_keep_valid_and_invalid_rules() raises:
    for flags in [0, 4, 52]:
        var bytes: List[UInt8] = [6, 0, 89, 0, UInt8(flags), 1]
        var at = 0
        var rules = _dwa_rules(bytes, at, len(bytes), 2)
        assert_equal(len(rules), 1)
        assert_equal(rules[0].csc, 2 if flags == 52 else -1)
        assert_equal(at, 6)
    for flags in [68, 244]:
        var bytes: List[UInt8] = [6, 0, 89, 0, UInt8(flags), 1]
        var at = 0
        with assert_raises(contains="invalid DWA channel rule"):
            _ = _dwa_rules(bytes, at, len(bytes), 2)


def test_dwa_disjoint_prefix_groups_consume_dc_values_exactly_once() raises:
    # A complete RGB group sorts after incomplete and standalone prefixes.
    # Complete groups consume DC first. Distinct singleton values then make
    # skipped, repeated, or reordered consumption observable in the output.
    var names: List[String] = ["z.R", "z.G", "z.B", "b.R", "b.G", "m.Y"]
    var channels = List[ExrChannel]()
    for name in names:
        channels.append(ExrChannel(name, HALF_SAMPLES, 1, 1, True))
    var ac = zlib_stream(_words(List[Int](length=6, fill=0xFF00)))
    var dc = _zip_predict(_words([0, 0, 0, 0x4800, 0x4C00, 0x5000]))
    var bytes = List[UInt8](length=88, fill=0)
    _set32(bytes, 0, 2)
    _set32(bytes, 24, len(ac))
    _set32(bytes, 32, len(dc))
    _set32(bytes, 64, 6)
    _set32(bytes, 72, 6)
    _set32(bytes, 80, 1)
    bytes.extend([18, 0, 82, 0, 20, 1, 71, 0, 36, 1, 66, 0, 52, 1, 89, 0, 4, 1])
    bytes.extend(ac^)
    bytes.extend(dc^)
    var got = _dwa_decode(bytes, 0, len(bytes), 8, 8, channels)
    # A DC coefficient is divided by8: HALF8,16,32 produce HALF1,2,4.
    var values: List[Int] = [0, 0, 0, 0x3C00, 0x4000, 0x4400]
    var expected = List[Int]()
    for _ in range(8):
        for value in values:
            for _ in range(8):
                expected.append(value)
    assert_equal(got, _words(expected))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
