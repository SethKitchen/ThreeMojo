# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Nonallocating regressions for curve parameter and count boundaries."""

from math.curve import (
    CUBIC,
    ELLIPSE,
    LINE,
    QUADRATIC,
    SPLINE,
    Curve,
    CurveKind,
    arc,
    cubic_bezier,
    line,
    quadratic_bezier,
    spline,
    u_to_t,
)
from math.curve3 import (
    CATMULL_ROM3,
    CUBIC3,
    LINE3,
    QUADRATIC3,
    CatmullRomType,
    Curve3,
    Curve3Kind,
    CurvePath3,
    catmull_rom3,
    cubic_bezier3,
    line3,
    quadratic_bezier3,
)
from math.curve_checks import (
    check_curve_parameter,
    curve_count_product,
    curve_count_sum,
    curve_sample_count,
)
from math.curve_extras import ExtraCurveKind, helix_curve
from math.path import Path, resolution_of
from math.space_curve import (
    SpaceCurve3,
    chord_tangent,
    frames3_of,
    frames_of,
    length_of,
    lengths_of,
    point_at,
    points_of,
    spaced_points3,
    spaced_points_of,
    tangent_at,
    u_to_t as space_u_to_t,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import inf, nan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_raises
from units.si import Angle, Length, METER, RADIAN


def curves2() raises -> List[Curve]:
    """Return one valid curve of each planar kind."""
    var a = Vector2(0, 0)
    var b = Vector2(1, 1)
    var c = Vector2(2, 0)
    return [
        line(a, b),
        quadratic_bezier(a, b, c),
        cubic_bezier(a, a, b, c),
        spline([a, b, c]),
        arc(a, Length(1, METER), Angle(0, RADIAN), Angle(1, RADIAN)),
    ]


def curves3() raises -> List[Curve3]:
    """Return one valid curve of each spatial kind."""
    var a = Vector3(0, 0, 0)
    var b = Vector3(1, 1, 0)
    var c = Vector3(2, 0, 0)
    return [
        line3(a, b),
        quadratic_bezier3(a, b, c),
        cubic_bezier3(a, a, b, c),
        catmull_rom3([a, b, c]),
    ]


def test_bounded_parameters_are_checked_before_dispatch() raises:
    var planar = curves2()
    var spatial = curves3()
    var bad: List[Float32] = [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
        bitcast[DType.float32](UInt32(0x80000001)),
        bitcast[DType.float32](UInt32(0x3F800001)),
    ]
    for value in bad:
        for curve in planar:
            with assert_raises():
                _ = curve.point(value)
            with assert_raises():
                _ = curve.tangent(value)
            with assert_raises():
                _ = curve.point_at(value)
            with assert_raises():
                _ = curve.tangent_at(value)
        for curve in spatial:
            with assert_raises():
                _ = curve.point(value)
            with assert_raises():
                _ = curve.tangent(value)
            with assert_raises():
                _ = curve.point_at(value)
            with assert_raises():
                _ = curve.tangent_at(value)
        var path = CurvePath3()
        path.add(spatial[0].copy())
        with assert_raises():
            _ = path.point(value)
        with assert_raises():
            _ = path.tangent(value)
        with assert_raises():
            _ = u_to_t([0, 1], value)
    with assert_raises():
        _ = u_to_t(List[Float32](), 0.5)
    with assert_raises():
        _ = u_to_t([0], 0.5)


def test_space_parameters_are_checked_before_narrowing_or_clamping() raises:
    var curve = SpaceCurve3(line3(Vector3(0, 0, 0), Vector3(1, 0, 0)))
    # The finite outside values round to Float32 endpoints or fit inside the
    # chord delta. Validation must happen before either operation.
    var bad: List[Float64] = [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
        bitcast[DType.float64](UInt64(0x8000000000000001)),
        bitcast[DType.float64](UInt64(0x3FF0000000000001)),
        -1e-50,
        1.00000001,
    ]
    for value in bad:
        with assert_raises():
            _ = curve.point3(value)
        with assert_raises():
            _ = curve.tangent3(value)
        with assert_raises():
            _ = chord_tangent(curve, value)
        with assert_raises():
            _ = point_at(curve, value)
        with assert_raises():
            _ = tangent_at(curve, value)
        with assert_raises():
            _ = space_u_to_t([0, 1], value)
    with assert_raises():
        _ = space_u_to_t(List[Float64](), 0.5)
    with assert_raises():
        _ = space_u_to_t([0], 0.5)
    assert_equal(curve.point3(0)[0], Float64(0))
    assert_equal(curve.point3(1)[0], Float64(1))
    check_curve_parameter(0)
    check_curve_parameter(1)


def refuse_planar(curve: Curve) raises:
    """Check every evaluation boundary rejects a malformed planar curve."""
    with assert_raises():
        _ = curve.point(0.5)
    with assert_raises():
        _ = curve.tangent(0.5)
    with assert_raises():
        _ = curve.point_at(0.5)
    with assert_raises():
        _ = curve.tangent_at(0.5)
    with assert_raises():
        _ = curve.arc_divisions()
    with assert_raises():
        _ = resolution_of(curve, 1)


def refuse_spatial(curve: Curve3) raises:
    """Check every evaluation boundary rejects a malformed spatial curve."""
    with assert_raises():
        _ = curve.point(0.5)
    with assert_raises():
        _ = curve.tangent(0.5)
    with assert_raises():
        _ = curve.point_at(0.5)
    with assert_raises():
        _ = curve.tangent_at(0.5)
    with assert_raises():
        _ = curve.arc_divisions()
    var wrapper = SpaceCurve3(curve)
    with assert_raises():
        _ = wrapper.point3(0.5)
    with assert_raises():
        _ = wrapper.tangent3(0.5)
    var path = CurvePath3()
    path.add(curve.copy())
    with assert_raises():
        _ = path.sample(1)
    with assert_raises():
        _ = path.point(0.5)
    with assert_raises():
        _ = path.tangent(0.5)


def test_mutable_kinds_and_control_counts_are_checked() raises:
    var planar = curves2()
    for index in range(len(planar)):
        var bad = planar[index].copy()
        bad.kind = CurveKind(99)
        refuse_planar(bad)
        bad = planar[index].copy()
        bad.points.clear()
        refuse_planar(bad)
    var too_many = planar[0].copy()
    too_many.points.append(Vector2(2, 0))
    refuse_planar(too_many)
    var one = planar[3].copy()
    one.points = [Vector2(0, 0)]
    refuse_planar(one)
    var spatial = curves3()
    for index in range(len(spatial)):
        var bad = spatial[index].copy()
        bad.kind = Curve3Kind(99)
        refuse_spatial(bad)
        bad = spatial[index].copy()
        bad.curve_type = CatmullRomType(99)
        refuse_spatial(bad)
        bad = spatial[index].copy()
        bad.points.clear()
        refuse_spatial(bad)
        if index < 3:
            bad = spatial[index].copy()
            bad.closed = True
            refuse_spatial(bad)
    var extra = spatial[0].copy()
    extra.points.append(Vector3(2, 0, 0))
    refuse_spatial(extra)
    var single = spatial[3].copy()
    single.points = [Vector3(0, 0, 0)]
    refuse_spatial(single)


def test_extra_point_parameters_remain_unbounded_and_kinds_are_checked() raises:
    var curve = helix_curve()
    assert_equal(curve.point3(-2)[2], Float64(-300))
    assert_equal(curve.point3(2)[2], Float64(300))
    with assert_raises():
        _ = curve.tangent3(1.00000001)
    curve.kind = ExtraCurveKind(99)
    with assert_raises():
        _ = curve.point3(0.5)
    with assert_raises():
        _ = curve.tangent3(0.5)
    with assert_raises():
        _ = point_at(curve, 0.5)
    with assert_raises():
        _ = tangent_at(curve, 0.5)


def test_count_arithmetic_does_not_wrap_or_allocate() raises:
    assert_equal(curve_sample_count(1), 2)
    assert_equal(curve_sample_count(Int.MAX - 1), Int.MAX)
    assert_equal(curve_count_sum(Int.MAX, 0), Int.MAX)
    assert_equal(curve_count_product(Int.MAX, 1), Int.MAX)
    assert_equal(curve_count_product(Int.MAX, 0), 0)
    assert_equal(curve_count_product(0, Int.MAX), 0)
    assert_equal(curve_count_product(Int.MAX // 2, 2), Int.MAX - 1)
    with assert_raises():
        _ = curve_sample_count(Int.MAX)
    with assert_raises():
        _ = curve_sample_count(0)
    with assert_raises():
        _ = curve_sample_count(-1)
    with assert_raises():
        _ = curve_count_sum(Int.MAX, 1)
    with assert_raises():
        _ = curve_count_sum(-1, 0)
    with assert_raises():
        _ = curve_count_sum(0, -1)
    with assert_raises():
        _ = curve_count_product(Int.MAX // 2 + 1, 2)
    with assert_raises():
        _ = curve_count_product(-1, 0)
    with assert_raises():
        _ = curve_count_product(0, -1)


def test_curve_and_path_sample_overflow_is_refused() raises:
    var planar = curves2()
    var spatial = curves3()
    for curve in planar:
        with assert_raises():
            _ = curve.sample(Int.MAX)
        with assert_raises():
            _ = curve.lengths(Int.MAX)
        with assert_raises():
            _ = curve.spaced_points(Int.MAX)
        assert_equal(len(curve.sample(1)), 2)
        assert_equal(len(curve.lengths(1)), 2)
        assert_equal(len(curve.spaced_points(1)), 2)
    for curve in spatial:
        with assert_raises():
            _ = curve.sample(Int.MAX)
        with assert_raises():
            _ = curve.lengths(Int.MAX)
        with assert_raises():
            _ = curve.spaced_points(Int.MAX)
        with assert_raises():
            _ = curve.frenet_frames(Int.MAX, False)
        assert_equal(len(curve.sample(1)), 2)
        assert_equal(len(curve.lengths(1)), 2)
        assert_equal(len(curve.spaced_points(1)), 2)
    var path = CurvePath3()
    path.add(spatial[1].copy())
    with assert_raises():
        _ = path.sample(Int.MAX)
    with assert_raises():
        _ = path.spaced_points(Int.MAX)
    with assert_raises():
        _ = path.frenet_frames(Int.MAX, False)
    assert_equal(len(path.sample(1)), 2)
    assert_equal(len(path.spaced_points(1)), 2)
    var straight = CurvePath3()
    straight.add(spatial[0].copy())
    assert_equal(len(straight.sample(Int.MAX)), 2)
    assert_equal(straight.frenet_frames(1, False).count(), 2)
    assert_equal(spatial[0].frenet_frames(1, False).count(), 2)
    with assert_raises():
        _ = resolution_of(planar[0], 0)
    with assert_raises():
        _ = resolution_of(planar[3], Int.MAX // 2)
    with assert_raises():
        _ = resolution_of(planar[4], Int.MAX // 2 + 1)
    var pen = Path(Vector2(0, 0))
    pen.line_to(Vector2(1, 0))
    assert_equal(len(pen.sample(Int.MAX)), 2)
    pen.curves.append(planar[3].copy())
    with assert_raises():
        _ = pen.sample(Int.MAX // 2)
    # A later segment's product is checked before a huge first piece.
    var later = Path(Vector2(0, 0))
    later.curves.append(planar[1].copy())
    later.curves.append(planar[3].copy())
    with assert_raises():
        _ = later.sample(Int.MAX // 2)
    # Each piece fits, but their total sample count does not. No huge
    # first-piece allocation may precede the total-count check.
    var total = Path(Vector2(0, 0))
    total.curves.append(planar[1].copy())
    total.curves.append(planar[1].copy())
    with assert_raises():
        _ = total.sample(Int.MAX // 2 + 1)
    with assert_raises():
        _ = Path().sample(1)
    var empty = CurvePath3()
    with assert_raises():
        _ = empty.sample(1)
    with assert_raises():
        _ = empty.spaced_points(1)
    with assert_raises():
        _ = empty.frenet_frames(1, False)


def test_space_sample_and_frame_counts_are_checked_before_allocation() raises:
    var curve = SpaceCurve3(line3(Vector3(0, 0, 0), Vector3(1, 0, 0)))
    with assert_raises():
        _ = lengths_of(curve, Int.MAX)
    with assert_raises():
        _ = length_of(curve, Int.MAX)
    with assert_raises():
        _ = points_of(curve, Int.MAX)
    with assert_raises():
        _ = spaced_points3(curve, Int.MAX)
    with assert_raises():
        _ = spaced_points_of(curve, Int.MAX)
    with assert_raises():
        _ = spaced_points_of(curve, 1, Int.MAX)
    with assert_raises():
        _ = point_at(curve, 0.5, Int.MAX)
    with assert_raises():
        _ = tangent_at(curve, 0.5, Int.MAX)
    with assert_raises():
        _ = frames3_of(curve, Int.MAX)
    with assert_raises():
        _ = frames_of(curve, Int.MAX)
    with assert_raises():
        _ = frames3_of(curve, 1, False, Int.MAX)
    assert_equal(len(lengths_of(curve, 1)), 2)
    assert_equal(len(points_of(curve, 1)), 2)
    assert_equal(len(spaced_points3(curve, 1, 1)), 2)
    assert_equal(len(spaced_points_of(curve, 1, 1)), 2)
    assert_equal(len(frames3_of(curve, 1, False, 1).tangents), 2)
    assert_equal(frames_of(curve, 1, False, 1).count(), 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
