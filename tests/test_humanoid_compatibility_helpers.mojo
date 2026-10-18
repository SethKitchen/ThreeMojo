# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The original humanoid helper imports keep IEEE edge behavior."""

from extensions.humanoid.skeleton.field import clamp_unit
from extensions.humanoid.skeleton.morph import smoothstep
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    max_f,
    PelvisChain,
    PelvisChainSet,
    chain_set_bounds,
)
from extensions.humanoid.skeleton.field import empty_bounds
from extensions.humanoid.skeleton.leg.femur.dimensions import (
    clamp_unit as femur_clamp_unit,
)
from extensions.water.optics import (
    fresnel,
    aces_channel,
    smoothstep as water_smoothstep,
)
from math.vector3 import Vector3
from std.math import inf, isnan, max, min, nan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def test_clamp_unit_preserves_nan_and_negative_zero() raises:
    assert_equal(clamp_unit(-2), Float32(-1))
    assert_equal(clamp_unit(2), Float32(1))
    assert_equal(clamp_unit(0.5), Float32(0.5))
    assert_true(isnan(clamp_unit(nan[DType.float32]())))
    assert_equal(
        bitcast[DType.uint32](clamp_unit(-Float32(0))), UInt32(0x80000000)
    )
    assert_equal(clamp_unit(inf[DType.float32]()), Float32(1))


def test_smoothstep_keeps_original_clamped_arithmetic() raises:
    var edges: List[Float32] = [-1, 0, 1]
    var values: List[Float32] = [
        -2,
        -1,
        -Float32(0),
        0.5,
        1,
        2,
        inf[DType.float32](),
        nan[DType.float32](),
    ]
    for edge0 in edges:
        for edge1 in edges:
            for x in values:
                var t = max(
                    Float32(0), min(Float32(1), (x - edge0) / (edge1 - edge0))
                )
                var expected = t * t * (3 - 2 * t)
                var got = smoothstep(edge0, edge1, x)
                if isnan(expected):
                    assert_true(isnan(got))
                else:
                    assert_equal(
                        bitcast[DType.uint32](got),
                        bitcast[DType.uint32](expected),
                    )


def test_max_f_keeps_operand_order_for_nan_and_zero() raises:
    assert_equal(max_f(2, 1), Float32(2))
    assert_equal(max_f(1, 2), Float32(2))
    assert_equal(max_f(nan[DType.float32](), 3), Float32(3))
    assert_true(isnan(max_f(3, nan[DType.float32]())))
    assert_equal(
        bitcast[DType.uint32](max_f(0, -Float32(0))), UInt32(0x80000000)
    )
    assert_equal(bitcast[DType.uint32](max_f(-Float32(0), 0)), UInt32(0))


def test_water_consumers_keep_nan_instead_of_saturating_to_one() raises:
    var value = nan[DType.float32]()
    assert_true(isnan(fresnel(value, 1.33)))
    assert_true(isnan(aces_channel(value)))
    assert_true(isnan(water_smoothstep(0, 1, value)))
    assert_equal(water_smoothstep(0, 1, 0.5), Float32(0.5))
    assert_true(isnan(femur_clamp_unit(value)))


def test_pelvis_bounds_use_original_radius_operand_order() raises:
    var origin = Vector3(0, 0, 0)
    var far = Vector3(10, 0, 0)
    var missing = nan[DType.float32]()
    var chain = PelvisChain(
        origin, far, origin, origin, origin, 1, 2, 1, 1, 1, 1, missing, 1, 1, 1
    )
    var got = chain_set_bounds(PelvisChainSet(1, chain, chain, chain), 0)
    var expected = empty_bounds()
    expected.include_sphere(origin, max_f(1, 1))
    expected.include_sphere(far, max_f(2, missing))
    expected.include_sphere(origin, max_f(1, 1))
    expected.include_sphere(origin, max_f(1, 1))
    expected.include_sphere(origin, max_f(1, 1))
    assert_equal(
        bitcast[DType.uint32](got.low.x), bitcast[DType.uint32](expected.low.x)
    )
    assert_equal(
        bitcast[DType.uint32](got.high.x),
        bitcast[DType.uint32](expected.high.x),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
