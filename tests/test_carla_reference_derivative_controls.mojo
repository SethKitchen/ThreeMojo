# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Direct controls for the retained reference-geometry derivative contract.

The canonical lane evaluator has a separate implementation. These controls
exercise the original record helper directly, using analytic line/arc/spiral
derivatives and explicit, physically consistent stored interpolation tables.
"""

from extensions.carla.geometry import (
    LINE,
    PARAM_POLY3,
    POLY3,
    RoadGeometry,
    RoadGeometryKind,
    _Sample,
    with_arc,
    with_spiral,
)
from std.math import cos, inf, nan, sin, sqrt
from std.testing import TestSuite, assert_almost_equal, assert_raises


def _line() raises -> RoadGeometry:
    return RoadGeometry(LINE, 0.0, 2.0, -3.0, 0.3, 2.0)


def _check(
    actual: Tuple[Float64, Float64, Float64],
    dx: Float64,
    dy: Float64,
    turn: Float64,
    tolerance: Float64 = 1e-12,
) raises:
    assert_almost_equal(actual[0], dx, atol=tolerance, rtol=0)
    assert_almost_equal(actual[1], dy, atol=tolerance, rtol=0)
    assert_almost_equal(actual[2], turn, atol=tolerance, rtol=0)


def _straight_samples(
    kind: RoadGeometryKind, count: Int = 2
) raises -> RoadGeometry:
    # v=2u, with chord-length station spacing and its exact stored tangent.
    var span = Float64(0.3) * sqrt(Float64(5))
    var g = RoadGeometry(kind, 0.0, 0.0, 0.0, 0.0, span * Float64(count - 1))
    for i in range(count):
        var u = Float64(i) * 0.3
        g.samples.append(_Sample(u, 2.0 * u, Float64(i) * span, 1.0, 2.0))
    return g^


def test_reference_line_endpoints_and_clamped_derivative() raises:
    var g = _line()
    for s in [0.0, 0.5, 2.0]:
        _check(g._derivative_at(s), cos(Float64(0.3)), sin(Float64(0.3)), 0)
    for s in [-1.0, 3.0]:
        _check(g._derivative_at(s), 0, 0, 0, 0)


def test_reference_derivative_rejects_invalid_kind() raises:
    var g = _line()
    g.kind = RoadGeometryKind(5)
    with assert_raises(contains="kind"):
        _ = g._derivative_at(0.5)


def test_reference_derivative_rejects_nonfinite_distance_or_heading() raises:
    for value in [nan[DType.float64](), inf[DType.float64]()]:
        var g = _line()
        with assert_raises(contains="distance and heading"):
            _ = g._derivative_at(value)
        g.heading = value
        with assert_raises(contains="distance and heading"):
            _ = g._derivative_at(0.5)


def test_reference_derivative_rejects_nonpositive_or_nonfinite_length() raises:
    for length in [0.0, -1.0, inf[DType.float64](), nan[DType.float64]()]:
        var g = _line()
        g.length = length
        with assert_raises(contains="finite positive length"):
            _ = g._derivative_at(0.5)


def test_reference_arc_matches_circle_tangent_and_curvature() raises:
    for curvature in [-0.4, 0.4]:
        var g = with_arc(_line(), curvature)
        for s in [0.0, 0.75, 2.0]:
            var angle = Float64(0.3) + s * curvature
            _check(g._derivative_at(s), cos(angle), sin(angle), curvature)


def test_reference_derivative_rejects_each_nonfinite_curvature() raises:
    for axis in [0, 1]:
        var g = with_arc(_line(), 0.4)
        if axis == 0:
            g.curvature_start = nan[DType.float64]()
        else:
            g.curvature_end = nan[DType.float64]()
        with assert_raises(contains="finite curvature"):
            _ = g._derivative_at(0.5)
    var g = with_arc(_line(), 0.4)
    g.curvature_start = 0
    with assert_raises(contains="nonzero curvature"):
        _ = g._derivative_at(0.5)


def test_reference_spiral_derivative_matches_instantaneous_heading() raises:
    # On these short smooth spans the five-point quadrature derivative has
    # negligible truncation error relative to this 1e-12 absolute control.
    for end_curvature in [0.1, 0.3]:
        var g = with_spiral(_line(), 0.1, end_curvature)
        for s in [0.0, 0.25, 0.75]:
            var rate = (end_curvature - Float64(0.1)) / 2.0
            var angle = Float64(0.3) + 0.1 * s + 0.5 * rate * s * s
            _check(g._derivative_at(s), cos(angle), sin(angle), 0.1 + rate * s)


def test_reference_spiral_rejects_finite_and_overflowing_work_counts() raises:
    for curvature in [1e20, 1e308]:
        var g = with_spiral(_line(), curvature, curvature)
        with assert_raises(contains="work is not representable"):
            _ = g._derivative_at(2.0)


def test_reference_sampled_chords_and_rotated_world_derivatives() raises:
    for kind in [POLY3, PARAM_POLY3]:
        var g = _straight_samples(kind, 4)
        var span = Float64(0.3) * sqrt(Float64(5))
        for s in [0.0, 0.1 * span, 1.0 * span, 2.5 * span, 3.0 * span]:
            _check(
                g._derivative_at(s),
                1.0 / sqrt(Float64(5)),
                2.0 / sqrt(Float64(5)),
                0,
            )
        g.heading = 1.5707963267948966
        _check(
            g._derivative_at(0.5 * span),
            -2.0 / sqrt(Float64(5)),
            1.0 / sqrt(Float64(5)),
            0,
        )


def test_reference_poly3_frame_turn_is_separate_from_chord_direction() raises:
    # v=u^2 at u=0 and u=.3: the chord slope is .3, while the stored
    # tangent interpolates from 0 to 0.6. d(atan(t))/ds=t'/(1+t^2).
    var span = sqrt(Float64(0.3) ** 2 + Float64(0.09) ** 2)
    var g = RoadGeometry(POLY3, 0.0, 0.0, 0.0, 0.0, span)
    g.samples.append(_Sample(0, 0, 0, 1, 0))
    g.samples.append(_Sample(0.3, 0.09, span, 1, 0.6))
    _check(
        g._derivative_at(span * 0.5),
        0.3 / span,
        0.09 / span,
        0.6 / (span * 1.09),
    )


def test_reference_parametric_frame_turn_uses_both_tangent_components() raises:
    # u(p)=2p, v(p)=p^2 at p=0 and p=.3. The derivative of atan2(v',u')
    # along the stored interval is (u'v''-v'u'')/(u'^2+v'^2).
    var span = sqrt(Float64(0.6) ** 2 + Float64(0.09) ** 2)
    var g = RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, span)
    g.samples.append(_Sample(0, 0, 0, 2, 0))
    g.samples.append(_Sample(0.6, 0.09, span, 2, 0.6))
    _check(
        g._derivative_at(span * 0.5),
        0.6 / span,
        0.09 / span,
        1.2 / (span * 4.09),
    )


def test_reference_sampled_derivative_rejects_missing_samples() raises:
    var g = _straight_samples(POLY3)
    g.samples.clear()
    with assert_raises(contains="two samples"):
        _ = g._derivative_at(0.0)
    g.samples.append(_Sample(0, 0, 0, 1, 0))
    with assert_raises(contains="two samples"):
        _ = g._derivative_at(0.0)


def test_reference_sampled_derivative_rejects_each_invalid_span() raises:
    for span in [0.0, -1.0, inf[DType.float64](), nan[DType.float64]()]:
        var g = _straight_samples(POLY3)
        g.samples[1].s = span
        with assert_raises(contains="finite positive length"):
            _ = g._derivative_at(0.0)


def test_reference_parametric_derivative_rejects_absent_heading() raises:
    for tangent in [0.0, inf[DType.float64]()]:
        var g = _straight_samples(PARAM_POLY3)
        for i in range(2):
            g.samples[i].tu = tangent
            g.samples[i].tv = 0
        with assert_raises(contains="no heading"):
            _ = g._derivative_at(g.length * 0.5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
