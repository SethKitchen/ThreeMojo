# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Finite right-handed SDF frames, including parallel and extreme inputs."""

from extensions.sdf.field import SdfModel
from extensions.sdf.ids import BoneId
from extensions.sdf.vector import Frame, V3, cross, dot, frame_zy, length
from std.math import isfinite, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _orthonormal(f: Frame, expected_z: V3) raises:
    for a in [f.x, f.y, f.z]:
        assert_true(isfinite(a.x) and isfinite(a.y) and isfinite(a.z))
        assert_almost_equal(length(a), 1.0, atol=1e-12)
    assert_almost_equal(dot(f.x, f.y), 0.0, atol=1e-12)
    assert_almost_equal(dot(f.x, f.z), 0.0, atol=1e-12)
    assert_almost_equal(dot(f.y, f.z), 0.0, atol=1e-12)
    assert_almost_equal(dot(cross(f.x, f.y), f.z), 1.0, atol=1e-12)
    assert_almost_equal(length(f.z - expected_z), 0.0, atol=1e-12)


def test_parallel_cardinal_axes_are_right_handed() raises:
    for d in [
        V3(1, 0, 0),
        V3(-1, 0, 0),
        V3(0, 1, 0),
        V3(0, -1, 0),
        V3(0, 0, 1),
        V3(0, 0, -1),
    ]:
        _orthonormal(frame_zy(d, d), d)
        _orthonormal(frame_zy(d, -d), d)
        _orthonormal(frame_zy(d, V3(0, 0, 0)), d)
        var near = d + V3(1e-9, -2e-9, 3e-9)
        _orthonormal(frame_zy(d, near), d)
    var planar = V3(1.0 / sqrt(2.0), 1.0 / sqrt(2.0), 0.0)
    _orthonormal(frame_zy(V3(1, 1, 0), V3(1, 1, 0)), planar)
    var ordinary = frame_zy(V3(0, 0, 2), V3(0, 3, 0))
    assert_equal(ordinary.x.x, 1.0)
    assert_equal(ordinary.y.y, 1.0)
    assert_equal(ordinary.z.z, 1.0)


def test_extreme_finite_directions_keep_their_orientation() raises:
    for scale in [Float64(5e-324), Float64(1.7976931348623157e308)]:
        for d in [
            V3(1, 0, 0),
            V3(-1, 0, 0),
            V3(0, 1, 0),
            V3(0, -1, 0),
            V3(0, 0, 1),
            V3(0, 0, -1),
        ]:
            _orthonormal(frame_zy(d * scale, d * scale), d)
        var diagonal = V3(1.0 / sqrt(2.0), 0.0, 1.0 / sqrt(2.0))
        _orthonormal(frame_zy(V3(scale, 0, scale), V3(0, scale, 0)), diagonal)
        var triple = V3(1.0 / sqrt(3.0), 1.0 / sqrt(3.0), 1.0 / sqrt(3.0))
        _orthonormal(
            frame_zy(V3(scale, scale, scale), V3(scale, scale, scale)), triple
        )
        var f = frame_zy(V3(0, 0, 1), V3(scale, scale, 0))
        _orthonormal(f, V3(0, 0, 1))
        assert_almost_equal(f.y.x, 1.0 / sqrt(2.0), atol=1e-12)
        assert_almost_equal(f.y.y, 1.0 / sqrt(2.0), atol=1e-12)


def test_visual_fallback_is_canonical_for_invalid_forward() raises:
    var inf = 1e300 * 1e300
    var nan = inf - inf
    for d in [
        V3(0, 0, 0),
        V3(inf, 0, 0),
        V3(0, inf, 0),
        V3(0, 0, inf),
        V3(nan, 0, 0),
    ]:
        var f = frame_zy(d, V3(0, 1, 0))
        _orthonormal(f, V3(0, 0, 1))
        assert_equal(f.x.x, 1.0)
        assert_equal(f.y.y, 1.0)
    for up in [V3(inf, 0, 0), V3(0, inf, 0), V3(0, 0, inf), V3(0, nan, 0)]:
        _orthonormal(frame_zy(V3(1, 0, 0), up), V3(1, 0, 0))


def test_model_construction_refuses_invalid_orientation() raises:
    var inf = 1e300 * 1e300
    var m = SdfModel()
    for d in [V3(0, 0, 0), V3(inf, 0, 0), V3(0, inf, 0), V3(0, 0, inf)]:
        with assert_raises(contains="axis"):
            _ = m.ell("invalid", BoneId(0), V3(0, 0, 0), V3(1, 1, 1), axis=d)
    for up in [V3(inf, 0, 0), V3(0, inf, 0), V3(0, 0, inf)]:
        with assert_raises(contains="up hint"):
            _ = m.ell("invalid", BoneId(0), V3(0, 0, 0), V3(1, 1, 1), up=up)
    # A valid extreme direction and a parallel hint remain valid inputs.
    _ = m.ell(
        "finite",
        BoneId(0),
        V3(0, 0, 0),
        V3(1, 2, 3),
        axis=V3(5e-324, 0, 0),
        up=V3(1, 0, 0),
    )
    _orthonormal(
        Frame(m.prims[0].ax, m.prims[0].ay, m.prims[0].az), V3(1, 0, 0)
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
