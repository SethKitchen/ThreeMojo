# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Analytic occupancy fixtures for overlap and conservative clearance."""

from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.limb.diagnostics import diagnose_pair
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
    assert_raises,
)
from units.si import Length


@fieldwise_init
struct ConstantField(DistanceField, ImplicitlyCopyable):
    var value: Float32

    def distance(self, point: Vector3) -> Float32:
        return self.value


def test_pair_exact_boxes_and_no_hit_limit() raises:
    var inside = ConstantField(-1)
    var outside = ConstantField(1)
    var low = Vector3(0, 0, 0)
    var high = Vector3(0.023, 0.037, 0.019)
    var d = diagnose_pair(inside, low, high, inside, low, high, Length(0.01))
    assert_equal(d.samples, 24)
    assert_equal(d.overlap_samples, d.samples)
    assert_almost_equal(
        d.overlap_volume.value, high.x * high.y * high.z, atol=1.0e-11
    )
    assert_almost_equal(d.field_witness.value, -1)
    var empty_first = diagnose_pair(
        outside, low, high, inside, low, high, Length(0.01)
    )
    var empty_second = diagnose_pair(
        inside, low, high, outside, low, high, Length(0.01)
    )
    assert_equal(empty_first.overlap_samples, 0)
    assert_equal(empty_second.overlap_samples, 0)
    assert_almost_equal(empty_first.field_witness.value, 1)
    for shift in [Vector3(0.1, 0, 0), Vector3(0, 0.1, 0), Vector3(0, 0, 0.1)]:
        var separated = diagnose_pair(
            inside, low, high, inside, low + shift, high + shift, Length(0.01)
        )
        assert_true(separated.bounds_gap.value > 0)
        assert_equal(separated.samples, 0)
    var touching = diagnose_pair(
        inside,
        low,
        high,
        inside,
        Vector3(high.x, 0, 0),
        Vector3(2 * high.x, high.y, high.z),
        Length(0.01),
    )
    assert_equal(touching.samples, 0)
    assert_almost_equal(touching.bounds_gap.value, 0)


def test_bad_diagnostic_requests_and_field_values_fail() raises:
    var solid = ConstantField(-1)
    var low = Vector3(0, 0, 0)
    var high = Vector3(0.04, 0.04, 0.04)
    for step in [
        Float32(0),
        Float32(1.0e-30),
        Float32(0.03),
        inf[DType.float32](),
        nan[DType.float32](),
    ]:
        with assert_raises():
            _ = diagnose_pair(solid, low, high, solid, low, high, Length(step))
    for bad in [Vector3(0, 0, 0.04), Vector3(0, 0.04, 0), Vector3(0.04, 0, 0)]:
        with assert_raises(contains="ordered"):
            _ = diagnose_pair(solid, bad, high, solid, low, high, Length(0.01))
    with assert_raises(contains="finite"):
        _ = diagnose_pair(
            solid,
            Vector3(nan[DType.float32](), 0, 0),
            high,
            solid,
            low,
            high,
            Length(0.01),
        )
    with assert_raises(contains="finite"):
        _ = diagnose_pair(
            solid,
            low,
            high,
            solid,
            low,
            Vector3(inf[DType.float32](), 1, 1),
            Length(0.01),
        )
    with assert_raises(contains="length range"):
        _ = diagnose_pair(
            solid,
            Vector3(-3.0e38, 0, 0),
            Vector3(-2.0e38, 1, 1),
            solid,
            Vector3(2.0e38, 0, 0),
            Vector3(3.0e38, 1, 1),
            Length(0.01),
        )
    for value in [nan[DType.float32](), inf[DType.float32]()]:
        var bad = ConstantField(value)
        with assert_raises(contains="field value"):
            _ = diagnose_pair(bad, low, high, solid, low, high, Length(0.01))
        with assert_raises(contains="field value"):
            _ = diagnose_pair(solid, low, high, bad, low, high, Length(0.01))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
