# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fixed uint32 witnesses and packed-state controls for strand coverage."""

from math.vector3 import Vector3
from render.fragment_flags import _strand_cell, strand_hash_threshold
from render.raster_state import RasterState
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def test_strand_state_roundtrips_without_changing_ordinary_flags() raises:
    var ordinary = RasterState(alpha_hash=True)
    assert_false(ordinary.strand_hash)
    assert_equal(ordinary.ops_word() & (1 << 26), 0)
    var strand = ordinary
    strand.strand_hash = True
    assert_equal(strand.ops_word() ^ ordinary.ops_word(), 1 << 26)
    var unpacked = RasterState.unpacked(
        strand.ops_word(), strand.stencil_word()
    )
    assert_true(unpacked.alpha_hash)
    assert_true(unpacked.strand_hash)
    assert_equal(unpacked.ops_word(), strand.ops_word())
    assert_equal(unpacked.stencil_word(), strand.stencil_word())


def test_strand_hash_matches_unsigned_integer_reference() raises:
    # These numerators are computed from unsigned modular arithmetic,
    # independently of the Mojo source and its floating-point operations.
    var positions: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(0.25, 0, 0),
        Vector3(-0.25, 0, 0),
        Vector3(3, 5, 7),
        Vector3(-1, 2, -3),
    ]
    var numerators: List[Int] = [20384, 27528, 22225, 9704, 7721]
    for index in range(len(positions)):
        var actual = strand_hash_threshold(
            positions[index], Vector3(1, 0, 0), Vector3(0, 1, 0)
        )
        assert_equal(actual, (Float32(numerators[index]) + 0.5) / 65536)
        assert_true(actual > 0 and actual < 1)
    assert_equal(_strand_cell(-0.25, 4), UInt32(65535))
    assert_equal(_strand_cell(16384.25, 4), UInt32(1))
    assert_equal(_strand_cell(inf[DType.float32](), 4), UInt32(0x7F800000))


def test_fixed_seed_has_no_frame_or_submission_order_input() raises:
    var bins = List[Int](length=16, fill=0)
    for sample in range(4096):
        var position = Vector3(Float32(sample) * 0.25, 0, 0)
        var first = strand_hash_threshold(
            position, Vector3(1, 0, 0), Vector3(0, 1, 0)
        )
        var repeated = strand_hash_threshold(
            position, Vector3(1, 0, 0), Vector3(0, 1, 0)
        )
        assert_equal(first, repeated)
        bins[Int(first * 16)] += 1
    for index in range(16):
        assert_true(bins[index] > 180 and bins[index] < 340)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
