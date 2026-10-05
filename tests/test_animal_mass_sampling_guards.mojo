# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scalar grid validation and ordinary finite sampler-field equivalence."""

from extensions.animals.anatomy.mass import _grid_dimension, _sample_distance
from extensions.sdf.field import FAR, SdfModel
from extensions.sdf.ids import BoneId
from extensions.sdf.vector import V3
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises


def test_grid_dimension_accepts_both_limits() raises:
    for count in [1.0, 2.0, 399.0, 400.0]:
        assert_equal(_grid_dimension(count), Int(count))


def test_grid_dimension_refuses_invalid_counts_before_conversion() raises:
    # These are scalar guard calls, with no geometry, workers or indexing.
    for count in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
        -1.0,
        0.0,
        401.0,
    ]:
        with assert_raises(contains="mass grid"):
            _ = _grid_dimension(count)


def test_checked_field_keeps_finite_evaluation_order() raises:
    for blend in [0.0, 0.04]:
        var model = SdfModel()
        _ = model.sphere("body", BoneId(0), V3(0, 0, 0), 0.5, k=blend)
        _ = model.sphere("side", BoneId(0), V3(0.4, 0, 0), 0.3, k=blend)
        _ = model.sphere(
            "cut", BoneId(0), V3(0, 0.2, 0), 0.2, k=blend, carve=True
        )
        var ids = List[Int]()
        assert_equal(_sample_distance(model, ids, V3(0, 0, 0)), Float64(FAR))
        for i in range(len(model.prims)):
            ids.append(i)
            for x in [-0.6, 0.0, 0.2, 0.6]:
                for y in [-0.3, 0.0, 0.3]:
                    var q = V3(x, y, 0.125)
                    assert_equal(
                        _sample_distance(model, ids, q), model.eval_list(ids, q)
                    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
