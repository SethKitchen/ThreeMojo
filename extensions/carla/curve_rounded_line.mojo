# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Optional stored-axis proof for a constant rotated LINE evaluator.

A singleton rounded coordinate enclosure is a proof over the entire supplied
parameter domain. It is not a heading tolerance or an endpoint-only test.
Unknown support leaves the ordinary curve certificate in use.
"""

from extensions.carla.curve_rounded_arc import (
    _RoundedBox,
    _rounded_constant,
    _rounded_madd,
    _rounded_operand,
)
from extensions.carla.curve_trig import _curve_cos, _curve_sin
from extensions.carla.geometry import LINE
from extensions.carla.road import Road
from extensions.carla.road_info import info_index


@fieldwise_init
struct _RoundedLineAxis(ImplicitlyCopyable):
    var axis: Int
    var slope: Float64


@always_inline
def _select_rounded_line_axis(
    x: _RoundedBox, y: _RoundedBox, cosine: Float64, sine: Float64
) -> Optional[_RoundedLineAxis]:
    """Select an axis from checked conservative boxes and fixed directions.

    Private preconditions: x and y are known whole-domain enclosures; both
    direction components are finite supported operands. The caller proves
    monotonicity in the indicated direction. The boxes need not be tight.
    A zero component is allowed, including two zero components. No heading
    or trigonometric identity is part of this standalone selection contract.
    The y direction uses the lane evaluator's negative-sine convention.
    """
    # Keep horizontal priority when both checked axes are eligible.
    if y.low == y.high and cosine != 0.0:
        return _RoundedLineAxis(0, cosine)
    if x.low == x.high and sine != 0.0:
        return _RoundedLineAxis(1, -sine)
    return None


def _rounded_line_axis_context(
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
    return _select_rounded_line_axis(x, y, cosine.low, sine.low)
