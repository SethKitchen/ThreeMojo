# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Constructor-valid bounded scalar controls for checked field arithmetic."""

from extensions.animals.anatomy.mass import _sample_distance
from extensions.sdf.field import SdfModel
from extensions.sdf.ids import BoneId
from extensions.sdf.vector import V3
from std.math import inf, isfinite
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)


def test_checked_lens_preserves_nonfinite_far_operand() raises:
    var model = SdfModel()
    var index = model.lens(
        "ordinary",
        BoneId(0),
        V3(0, 0, 0),
        V3(1, 0, 0),
        V3(0, 1, 0),
        V3(0, 0, 1),
        0.2,
        0.05,
        -0.1,
        0.1,
        k=0,
    )
    assert_equal(index, 0)
    assert_equal(len(model.prims), 1)
    var ids: List[Int] = [index]
    var center = _sample_distance(model, ids, V3(0, 0, 0))
    assert_equal(center, Float64(-0.1))
    var far = _sample_distance(model, ids, V3(1e200, 0, 0))
    assert_equal(far, inf[DType.float64]())
    assert_equal(len(model.prims), 1)
    assert_equal(model.prims[0].r.x, Float64(0.2))
    assert_equal(model.prims[0].c.x, Float64(0))


def test_checked_lens_fold_preserves_nonfinite_accumulator() raises:
    var model = SdfModel()
    for i in range(4):
        var index = model.lens(
            "lens" + String(i),
            BoneId(0),
            V3(0, 0, 0),
            V3(1, 0, 0),
            V3(0, 1, 0),
            V3(0, 0, 1),
            1e308,
            0,
            -1e308,
            1e308,
            k=1.7e308,
        )
        assert_equal(index, i)
    assert_equal(len(model.prims), 4)
    var point = V3(0, 0, 0)
    for i in range(4):
        assert_equal(model.distance(i, point), Float64(-1e308))
    var expected: List[Float64] = [
        -1.0720588235294118,
        -1.4617930108894768,
        -1.6872572091074396,
    ]
    var ids = List[Int]()
    for i in range(3):
        ids.append(i)
        var value = _sample_distance(model, ids, point)
        assert_true(isfinite(value))
        assert_almost_equal(value / 1e308, expected[i], rtol=1e-14, atol=0)
    ids.append(3)
    assert_equal(_sample_distance(model, ids, point), -inf[DType.float64]())
    assert_equal(len(model.prims), 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
