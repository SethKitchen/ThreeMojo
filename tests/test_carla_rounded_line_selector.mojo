# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Standalone conservative-box selector contract and context equivalence."""

from extensions.carla.curve_rounded_arc import (
    _RoundedBox,
    _rounded_constant,
    _rounded_madd,
    _rounded_operand,
)
from extensions.carla.curve_rounded_line import (
    _RoundedLineAxis,
    _rounded_line_axis_context,
    _select_rounded_line_axis,
)
from extensions.carla.curve_trig import _curve_cos, _curve_sin
from extensions.carla.geometry import LINE
from extensions.carla.road import Road
from extensions.carla.road_info import info_index
from std.testing import TestSuite, assert_equal, assert_true, assert_false
from tests.test_carla_rounded_line_axis import _rotated


def _reference_rounded_line_axis_context(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64
) raises -> Optional[_RoundedLineAxis]:
    road._check_lane(section, lane)
    if len(road.info.geometries) != 1:
        return None
    ref record = road.info.geometries[0]
    if record.geometry.kind != LINE:
        return None
    if (
        not _RoundedBox.bounds(low, high).known
        or low < 0.0
        or high > road.length
    ):
        return None
    # One record active at low also covers high: the domain is ordered.
    if info_index(road.info.geometries, low) != 0:
        return None
    var offset_at = info_index(road.info.lane_offsets, low)
    var elevation_at = info_index(road.info.elevations, low)
    if (
        offset_at < 0
        or elevation_at < 0
        or info_index(road.info.lane_offsets, high) != offset_at
        or info_index(road.info.elevations, high) != elevation_at
    ):
        return None
    var lane_offset = _rounded_constant(
        road.info.lane_offsets[offset_at].polynomial
    )
    var elevation = _rounded_constant(
        road.info.elevations[elevation_at].polynomial
    )
    if not lane_offset.known or not elevation.known:
        return None
    ref lanes = road.sections[section].lanes
    var id = lanes[lane].id
    var offset = _RoundedBox.point(0.0)
    if id.value != 0:
        var negative = id.value < 0
        var sign = _RoundedBox.point(1.0 if negative else -1.0)
        for position in range(len(lanes)):
            var i = len(lanes) - 1 - position if negative else position
            if negative:
                if lanes[i].id.value >= 0:
                    continue
            elif lanes[i].id.value < 1:
                continue
            ref widths = lanes[i].info.widths
            var width_at = info_index(widths, low)
            if width_at < 0 or info_index(widths, high) != width_at:
                return None
            var width = _rounded_constant(widths[width_at].polynomial)
            if not width.known:
                return None
            var contribution = sign * width
            if lanes[i].id == id:
                contribution = contribution * _RoundedBox.point(0.5)
            offset = offset + contribution
            if not offset.known:
                return None
            if lanes[i].id == id:
                break
    offset = offset - lane_offset
    # Known point operands preserve a singleton through rounded add/multiply.
    if not offset.known:
        return None
    var start = _RoundedBox.point(record.s)
    var d = _RoundedBox.bounds(low, high) - start
    var length = record.geometry.length
    if not d.known or not _rounded_operand(length) or length < 0.0:
        return None
    d = _RoundedBox.bounds(
        min(max(d.low, 0.0), length), min(max(d.high, 0.0), length)
    )
    # A monotone clamp preserves supported endpoints and their common lobe.
    # These are the canonical no-inline scalar trig graph's stored outputs.
    # Never substitute ideal sine/cosine or snap a near-axis heading.
    var cosine = _RoundedBox.point(_curve_cos(record.geometry.heading))
    var sine = _RoundedBox.point(_curve_sin(record.geometry.heading))
    var x = _rounded_madd(d, cosine, _RoundedBox.point(record.geometry.x))
    var y = _rounded_madd(d, sine, _RoundedBox.point(record.geometry.y))
    x = _rounded_madd(offset, sine, x)
    y = -_rounded_madd(-offset, cosine, y)
    # The checked constant elevation is a singleton by construction.
    if not (x.known and y.known):
        return None
    # Subtraction, clamp, constant multiply, rounded addition/FMA, and final
    # sign reversal compose monotonically. Each permitted contraction graph
    # has the indicated direction. The other two stored coordinates must be
    # singleton boxes under every permitted graph over this original domain.
    if y.low == y.high and cosine.low != 0.0:
        return _RoundedLineAxis(0, cosine.low)
    if x.low == x.high and sine.low != 0.0:
        return _RoundedLineAxis(1, -sine.low)
    return None


def test_selector_preserves_horizontal_priority_and_signed_slopes() raises:
    var one = _RoundedBox.point(1.0)
    for cosine in [Float64(-1.0), 1.0]:
        for sine in [Float64(-1.0), 0.0, 1.0]:
            var selected = _select_rounded_line_axis(one, one, cosine, sine)
            assert_true(Bool(selected))
            assert_equal(selected.value().axis, 0)
            assert_equal(selected.value().slope, cosine)


def test_selector_zero_first_direction_selects_vertical() raises:
    var one = _RoundedBox.point(1.0)
    for zero in [Float64(0.0), -0.0]:
        for sine in [Float64(-1.0), 1.0]:
            var selected = _select_rounded_line_axis(one, one, zero, sine)
            assert_true(Bool(selected))
            assert_equal(selected.value().axis, 1)
            assert_equal(selected.value().slope, -sine)


def test_selector_conservative_transverse_width_and_stationary_refusal() raises:
    var one = _RoundedBox.point(1.0)
    var broad = _RoundedBox.bounds(1.0, 2.0)
    # A conservative enclosure may be wider than a constant coordinate.
    # These inputs satisfy the selector contract without asserting a heading.
    for zero in [Float64(0.0), -0.0]:
        assert_false(Bool(_select_rounded_line_axis(one, one, zero, zero)))
        assert_false(Bool(_select_rounded_line_axis(one, broad, 1.0, zero)))
    assert_false(Bool(_select_rounded_line_axis(broad, broad, 1.0, 1.0)))
    var vertical = _select_rounded_line_axis(one, broad, 0.0, 1.0)
    assert_true(Bool(vertical))
    assert_equal(vertical.value().axis, 1)
    assert_equal(vertical.value().slope, -1.0)
    var horizontal = _select_rounded_line_axis(broad, one, -1.0, 0.0)
    assert_true(Bool(horizontal))
    assert_equal(horizontal.value().axis, 0)
    assert_equal(horizontal.value().slope, -1.0)


def test_context_matches_exact_predecessor_without_heading_gate() raises:
    for heading in [
        Float64(0.0),
        -0.0,
        0.7,
        1.5707963267948966,
        -1.5707963267948966,
        3.141592653589793,
        1048577.0,
        1e100,
    ]:
        for translation in [Float64(80.0), 1e20]:
            var road = _rotated(heading)
            road.info.geometries[0].geometry.x = translation
            for high in [Float64(0.25), 29.75]:
                var actual = _rounded_line_axis_context(road, 0, 0, 0.25, high)
                var expected = _reference_rounded_line_axis_context(
                    road, 0, 0, 0.25, high
                )
                assert_equal(Bool(actual), Bool(expected))
                if actual:
                    assert_equal(actual.value().axis, expected.value().axis)
                    assert_equal(actual.value().slope, expected.value().slope)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
