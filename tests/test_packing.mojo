# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.packing`: three.js's `packing.glsl` and the four depth
packings.

The expected bytes are three.js's shader arithmetic worked by hand in
Float32. Each step multiplies by a power of two or takes a fraction, so
each is exact, and the bytes are exact too.
"""

from math.vector2 import Vector2
from math.vector3 import Vector3
from render.packing import (
    BASIC_DEPTH_PACKING,
    RGBA_DEPTH_PACKING,
    RGB_DEPTH_PACKING,
    RG_DEPTH_PACKING,
    DepthPacking,
    check_distance_range,
    normalized_distance,
    pack_depth_to_rg,
    pack_depth_to_rgb,
    pack_depth_to_rgba,
    packed_depth_fragment,
    packed_distance_fragment,
    unpack_rg_to_depth,
    unpack_rgb_to_depth,
    unpack_rgba_to_depth,
    window_depth,
)
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def byte(channel: Float32) -> Int:
    """Return the byte an eight-bit target stores for a channel."""
    return Int(channel * 255 + 0.5)


def test_the_four_packings_are_three_js_numbers() raises:
    assert_equal(BASIC_DEPTH_PACKING.value, 3200)
    assert_equal(RGBA_DEPTH_PACKING.value, 3201)
    assert_equal(RGB_DEPTH_PACKING.value, 3202)
    assert_equal(RG_DEPTH_PACKING.value, 3203)
    for packing in [
        BASIC_DEPTH_PACKING,
        RGBA_DEPTH_PACKING,
        RGB_DEPTH_PACKING,
        RG_DEPTH_PACKING,
    ]:
        assert_true(packing.is_valid())
    # A value the type can hold and the code does not accept.
    assert_false(DepthPacking(3204).is_valid())
    assert_false(DepthPacking(0).is_valid())


def test_rgba_packs_a_depth_into_four_bytes() raises:
    # 0.3 in Float32 is 5033165 / 2^24 exactly: red 76, green 204, blue
    # 205, and nothing left for the alpha.
    var packed = pack_depth_to_rgba(0.3)
    assert_equal(byte(packed[0]), 76)
    assert_equal(byte(packed[1]), 204)
    assert_equal(byte(packed[2]), 205)
    assert_equal(packed[3], Float32(0))
    # 0.1 leaves 0.625 of a step for the alpha.
    var small = pack_depth_to_rgba(0.1)
    assert_equal(byte(small[0]), 25)
    assert_equal(byte(small[1]), 153)
    assert_equal(byte(small[2]), 153)
    assert_equal(small[3], Float32(0.625))
    # The two ends, as three.js clamps them.
    assert_equal(pack_depth_to_rgba(0), SIMD[DType.float32, 4](0, 0, 0, 0))
    assert_equal(pack_depth_to_rgba(-1), SIMD[DType.float32, 4](0, 0, 0, 0))
    assert_equal(pack_depth_to_rgba(1), SIMD[DType.float32, 4](1, 1, 1, 1))
    assert_equal(pack_depth_to_rgba(2), SIMD[DType.float32, 4](1, 1, 1, 1))


def test_rgba_unpacks_to_the_depth_it_packed() raises:
    for v in [Float32(0.1), 0.3, 0.5, 0.7071, 0.99999]:
        assert_almost_equal(
            unpack_rgba_to_depth(pack_depth_to_rgba(v)), v, atol=1e-7
        )
    # One half is red 128 and nothing else.
    var half = pack_depth_to_rgba(0.5)
    assert_equal(byte(half[0]), 128)
    assert_equal(half[1], Float32(0))
    assert_equal(unpack_rgba_to_depth(half), Float32(0.5))


def test_rgb_packs_a_depth_into_three_bytes() raises:
    var packed = pack_depth_to_rgb(0.3)
    assert_equal(byte(packed.x), 76)
    assert_equal(byte(packed.y), 204)
    # What is left, unscaled, as three.js leaves it: 0.80078125.
    assert_equal(packed.z, Float32(0.80078125))
    assert_equal(pack_depth_to_rgb(0).x, Float32(0))
    assert_equal(pack_depth_to_rgb(1).z, Float32(1))
    for v in [Float32(0.1), 0.3, 0.5, 0.99]:
        assert_almost_equal(
            unpack_rgb_to_depth(pack_depth_to_rgb(v)), v, atol=1e-6
        )


def test_rg_packs_a_depth_into_two_bytes() raises:
    var packed = pack_depth_to_rg(0.3)
    assert_equal(byte(packed.x), 76)
    assert_almost_equal(packed.y, Float32(0.8), atol=1e-5)
    assert_equal(pack_depth_to_rg(-0.5).y, Float32(0))
    assert_equal(pack_depth_to_rg(1.5).x, Float32(1))
    for v in [Float32(0.1), 0.3, 0.5, 0.99]:
        assert_almost_equal(
            unpack_rg_to_depth(pack_depth_to_rg(v)), v, atol=1e-6
        )
    # Unpacked as three.js reads it: red scaled down by 255/256, green by
    # a further 256.
    assert_equal(unpack_rg_to_depth(Vector2(1, 0)), Float32(255.0 / 256.0))


def test_a_depth_fragment_is_written_by_its_packing() raises:
    # NDC -0.4 is window depth 0.3.
    assert_almost_equal(window_depth(-0.4), Float32(0.3))
    var basic = packed_depth_fragment(BASIC_DEPTH_PACKING, -0.4, 0.5)
    assert_almost_equal(basic[0], Float32(0.7))
    assert_equal(basic[0], basic[2])
    assert_equal(basic[3], Float32(0.5))
    var rgba = packed_depth_fragment(RGBA_DEPTH_PACKING, 0.0, 0.5)
    assert_equal(byte(rgba[0]), 128)
    assert_equal(rgba[3], Float32(0))
    var rgb = packed_depth_fragment(RGB_DEPTH_PACKING, 0.0, 0.5)
    assert_equal(byte(rgb[0]), 128)
    assert_equal(rgb[3], Float32(1))
    var rg = packed_depth_fragment(RG_DEPTH_PACKING, 0.0, 0.5)
    assert_equal(byte(rg[0]), 128)
    assert_equal(rg[2], Float32(0))
    assert_equal(rg[3], Float32(1))


def test_a_distance_is_a_fraction_of_the_range() raises:
    var at = Vector3(0, 3, 4)
    # Five meters from the origin, half way from zero to ten.
    assert_almost_equal(
        normalized_distance(at, Vector3(0, 0, 0), 0, 10), Float32(0.5)
    )
    # From a reference of its own, and clamped at both ends.
    assert_almost_equal(
        normalized_distance(at, Vector3(0, 3, 0), 2, 6), Float32(0.5)
    )
    assert_equal(normalized_distance(at, Vector3(0, 0, 0), 6, 10), Float32(0))
    assert_equal(normalized_distance(at, Vector3(0, 0, 0), 1, 2), Float32(1))
    var packed = packed_distance_fragment(at, Vector3(0, 0, 0), 0, 10)
    assert_equal(byte(packed[0]), 128)
    assert_equal(packed[3], Float32(0))


def test_a_distance_range_must_be_one_it_can_measure_by() raises:
    check_distance_range(Vector3(1, 2, 3), 0, 1)
    with assert_raises(contains="reference"):
        check_distance_range(Vector3(nan[DType.float32](), 0, 0), 0, 1)
    with assert_raises(contains="reference"):
        check_distance_range(Vector3(0, inf[DType.float32](), 0), 0, 1)
    with assert_raises(contains="reference"):
        check_distance_range(Vector3(0, 0, nan[DType.float32]()), 0, 1)
    with assert_raises(contains="near"):
        check_distance_range(Vector3(0, 0, 0), -1, 1)
    with assert_raises(contains="near"):
        check_distance_range(Vector3(0, 0, 0), nan[DType.float32](), 1)
    with assert_raises(contains="far"):
        check_distance_range(Vector3(0, 0, 0), 1, 1)
    with assert_raises(contains="far"):
        check_distance_range(Vector3(0, 0, 0), 1, inf[DType.float32]())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
