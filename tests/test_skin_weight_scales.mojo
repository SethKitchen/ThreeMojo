# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Skin weight normalization spans the finite Float32 range."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry
from core.interleaved_buffer import InterleavedBuffer
from objects.skinned_mesh import (
    SKIN_WEIGHT,
    normalize_skin_weights,
    normalized_skin_weights,
)
from std.testing import TestSuite, assert_almost_equal, assert_equal


def test_large_equal_weights_keep_their_proportions() raises:
    var got = normalized_skin_weights(SIMD[DType.float32, 4](1e38))
    assert_equal(got, SIMD[DType.float32, 4](0.25))


def test_large_unequal_weights_keep_their_proportions() raises:
    var got = normalized_skin_weights(SIMD[DType.float32, 4](3e38, 1e38, 0, 0))
    assert_almost_equal(got[0], Float32(0.75), atol=Float64(1e-6))
    assert_almost_equal(got[1], Float32(0.25), atol=Float64(1e-6))
    assert_equal(got[2], 0)
    assert_equal(got[3], 0)


def test_signed_weights_use_the_magnitude_sum() raises:
    var got = normalized_skin_weights(
        SIMD[DType.float32, 4](-1e38, 1e38, -1e38, 1e38)
    )
    assert_equal(got, SIMD[DType.float32, 4](-0.25, 0.25, -0.25, 0.25))


def test_subnormal_weights_do_not_need_a_reciprocal() raises:
    var got = normalized_skin_weights(SIMD[DType.float32, 4](1e-44))
    assert_equal(got, SIMD[DType.float32, 4](0.25))


def test_zero_weights_keep_the_first_bone_fallback() raises:
    var got = normalized_skin_weights(SIMD[DType.float32, 4](0))
    assert_equal(got, SIMD[DType.float32, 4](1, 0, 0, 0))


def test_geometry_normalization_reads_interleaved_weights() raises:
    var shared = InterleavedBuffer(
        [99, 1e38, 1e38, 1e38, 1e38, 88, 0, 0, 0, 0], 5
    )
    var geometry = BufferGeometry()
    geometry.set_attribute(SKIN_WEIGHT, BufferAttribute(shared, 4, 1))
    normalize_skin_weights(geometry)
    ref got = geometry.attribute_view(SKIN_WEIGHT)
    for lane in range(4):
        assert_equal(got.component(0, lane), Float32(0.25))
    assert_equal(got.component(1, 0), 1)
    assert_equal(got.component(1, 3), 0)
    assert_equal(shared.value(0), 99)
    assert_equal(shared.value(5), 88)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
