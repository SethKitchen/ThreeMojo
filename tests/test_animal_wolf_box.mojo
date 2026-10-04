# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Nominal wolf bounds contain two pinned raw reference constructions.

Expected positive-primitive envelopes were calculated independently from
upstream c95ae49346aa8e140a924376cec6cf0073d99512 wolf-reference.json,
SHA-256 323c5195e0e10293f389bd076fefa7c374f680b56f27de2c3f76495aa2230b79.
Analytic supports cover the positive primitives; separate face probes sample
the blended per-part fields. Neither asserts a universal bound for arbitrary
caller-edited Traits, later warps/poses, or every point on a continuous face.
"""

from extensions.animals.options import (
    AnimalOptions,
    MALE,
    JUVENILE,
    Variant,
    animal_options,
    body_random,
)
from extensions.animals.species.wolf import (
    wolf_traits,
    wolf_rig,
    wolf_sculpt,
    wolf_box,
)
from extensions.sdf.field import Primitive, SdfModel
from extensions.sdf.ids import ELLIPSOID, CONE, SurfacePart
from extensions.sdf.vector import V3, dot
from std.math import sqrt
from std.testing import TestSuite, assert_true, assert_almost_equal


def _support(p: Primitive, direction: V3) raises -> Tuple[Float64, Float64]:
    var center = dot(p.c, direction)
    if p.kind == ELLIPSOID:
        var x = dot(p.ax, direction) * p.r.x
        var y = dot(p.ay, direction) * p.r.y
        var z = dot(p.az, direction) * p.r.z
        var radius = sqrt(x * x + y * y + z * z)
        return (center - radius, center + radius)
    if p.kind == CONE:
        var end = dot(p.b, direction)
        return (
            min(center - p.r.x, end - p.r.y),
            max(center + p.r.x, end + p.r.y),
        )
    raise Error(
        "The pinned positive wolf fixture gained another primitive kind"
    )


def _check(options: AnimalOptions, expected_low: V3, expected_high: V3) raises:
    var random = body_random(options.seed)
    var traits = wolf_traits(random, options)
    var rig = wolf_rig(traits)
    var model = SdfModel()
    wolf_sculpt(model, rig, traits)
    var low: List[Float64] = [1e300, 1e300, 1e300]
    var high: List[Float64] = [-1e300, -1e300, -1e300]
    var directions: List[V3] = [V3(1, 0, 0), V3(0, 1, 0), V3(0, 0, 1)]
    for p in model.prims:
        if p.carve:
            continue
        for axis in range(3):
            var bounds = _support(p, directions[axis])
            low[axis] = min(low[axis], bounds[0])
            high[axis] = max(high[axis], bounds[1])
    var expect_low: List[Float64] = [
        expected_low.x,
        expected_low.y,
        expected_low.z,
    ]
    var expect_high: List[Float64] = [
        expected_high.x,
        expected_high.y,
        expected_high.z,
    ]
    var box = wolf_box()
    var box_low: List[Float64] = [box[0].x, box[0].y, box[0].z]
    var box_high: List[Float64] = [box[1].x, box[1].y, box[1].z]
    for axis in range(3):
        assert_almost_equal(low[axis], expect_low[axis], atol=1e-12, rtol=1e-12)
        assert_almost_equal(
            high[axis], expect_high[axis], atol=1e-12, rtol=1e-12
        )
        assert_true(box_low[axis] < box_high[axis])
        assert_true(box_low[axis] <= low[axis])
        assert_true(box_high[axis] >= high[axis])
    var fields = List[List[Int]]()
    fields.append(model.part_list(SurfacePart(0)))
    fields.append(model.part_list(SurfacePart(1)))
    # Sample each of six faces at a fixed 9x9 grid, including its corners
    # and edges. This is a bounded field control, not a continuous proof.
    for axis in range(3):
        for side in range(2):
            for i in range(9):
                for j in range(9):
                    var xyz: List[Float64] = [0, 0, 0]
                    xyz[axis] = box_low[axis] if side == 0 else box_high[axis]
                    var a = (axis + 1) % 3
                    var b = (axis + 2) % 3
                    xyz[a] = box_low[a] + Float64(i) / 8 * (
                        box_high[a] - box_low[a]
                    )
                    xyz[b] = box_low[b] + Float64(j) / 8 * (
                        box_high[b] - box_low[b]
                    )
                    var q = V3(xyz[0], xyz[1], xyz[2])
                    for ids in fields:
                        assert_true(model.eval_list(ids, q) > 0.0)


def test_wolf_box_contains_auto_seed3_reference() raises:
    _check(
        animal_options(3),
        V3(-0.12457214651275743, -0.0020000000000000035, -0.6796013143635702),
        V3(0.12457214651275743, 0.9039221007046293, 0.775178253910684),
    )


def test_wolf_box_contains_black_juvenile_seed3_reference() raises:
    _check(
        animal_options(3, sex=MALE, age=JUVENILE, variant=Variant(1)),
        V3(-0.12457214651275743, -0.0020000000000000035, -0.5877257259237876),
        V3(0.12457214651275743, 0.914943353087105, 0.7373163169604167),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
