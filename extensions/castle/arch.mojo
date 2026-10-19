# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The limit analysis of a masonry arch, and of the bridge of a castle.

Heyman's safe theorem (1966) states that an arch stands if one line of
thrust, in equilibrium with the loads, lies wholly inside the masonry. The
masonry takes no tension, it does not crush, and the joints do not slide.
This module looks for such a line.

The half arch is cut by radial joints into voussoirs. Each voussoir carries
its own weight, the fill above it, and the load on the deck. The crown
carries a horizontal thrust H at a height m / H. Moments about the two edge
points of each joint give two bounds on m, linear in H:

    y_in H - A_in <= m <= y_ex H - A_ex

where A is the moment of the loads between the crown and the joint, about
the edge point. For a given H the bounds make an interval of m. The
interval is open for the thrusts between a least and a greatest thrust. The
geometric factor of safety is the ring thickness over the least thickness
that still holds a line of thrust, with the loads unchanged. A semicircular
arch under its own weight has a least thickness of 0.1075 of the mean
radius, which the tests reproduce.
"""

from extensions.castle.masonry import Masonry
from extensions.castle.plan import Bridge
from extensions.geotech.quantities import UnitWeight64
from math.finite import require_positive_finite
from std.math import asin, cos, inf, pi, sin, sqrt
from units.si import Force64, Length64, Pressure64


@fieldwise_init
struct ArchResult(ImplicitlyCopyable):
    """What the limit analysis of an arch finds."""

    # Whether a line of thrust fits inside the ring.
    var safe: Bool
    # The least and the greatest horizontal thrust of a line that fits.
    var thrust_min: Force64
    var thrust_max: Force64
    # The vertical reaction at one springing.
    var vertical: Force64
    # The thickness over the least thickness that holds a line of thrust.
    var geometric_factor: Float64
    # The least thickness, with the loads unchanged.
    var minimum_thickness: Length64


struct _Joints(Movable):
    """The joints of a half arch and the loads that have built up to them."""

    var sine: List[Float64]
    var cosine: List[Float64]
    # The weight on the half arch from the crown to each joint.
    var weight: List[Float64]
    # The moment of that weight about the vertical through the crown.
    var moment: List[Float64]
    # The height of the center of the arch above the springing line.
    var center: Float64

    def __init__(out self, center: Float64):
        self.sine = List[Float64]()
        self.cosine = List[Float64]()
        self.weight = List[Float64]()
        self.moment = List[Float64]()
        self.center = center


def _disc(radius: Float64, x: Float64) -> Float64:
    """Return the height of a circle above its center at a distance x."""
    return sqrt(max(radius * radius - x * x, 0.0))


def _segment(
    r_in: Float64,
    r_ex: Float64,
    top: Float64,
    center: Float64,
    a0: Float64,
    a1: Float64,
    ring_weight: Float64,
    fill_weight: Float64,
    surcharge: Float64,
    width: Float64,
) -> Tuple[Float64, Float64]:
    """Return the weight of one voussoir with its fill and load, and the
    moment of that weight about the vertical through the crown.

    The angles a0 and a1 are the two joints, measured from the crown.
    """
    var delta = a1 - a0
    var mid = (a0 + a1) / 2.0
    var area = 0.5 * (r_ex * r_ex - r_in * r_in) * delta
    var w_ring = ring_weight * width * area
    var half = delta / 2.0
    var centroid = (
        (2.0 / 3.0)
        * (r_ex * r_ex * r_ex - r_in * r_in * r_in)
        / (r_ex * r_ex - r_in * r_in)
        * sin(half)
        / half
    )
    var x_ring = centroid * sin(mid)
    var x0 = r_ex * sin(a0)
    var x1 = r_ex * sin(a1)
    var reach = top - center
    # The integral of sqrt(R^2 - x^2) is (x sqrt(R^2 - x^2) + R^2 asin(x/R))/2.
    var g0 = 0.5 * (x0 * _disc(r_ex, x0) + r_ex * r_ex * asin(x0 / r_ex))
    var g1 = 0.5 * (x1 * _disc(r_ex, x1) + r_ex * r_ex * asin(x1 / r_ex))
    var column = reach * (x1 - x0) - (g1 - g0)
    var first = (
        reach * (x1 * x1 - x0 * x0) / 2.0
        + (
            _disc(r_ex, x1) * (r_ex * r_ex - x1 * x1)
            - _disc(r_ex, x0) * (r_ex * r_ex - x0 * x0)
        )
        / 3.0
    )
    var w_fill = fill_weight * width * column
    var m_fill = fill_weight * width * first
    var w_load = surcharge * width * (x1 - x0)
    var m_load = w_load * (x0 + x1) / 2.0
    return (
        w_ring + w_fill + w_load,
        w_ring * x_ring + m_fill + m_load,
    )


def _interval(
    joints: _Joints, r_in: Float64, r_ex: Float64, thrust: Float64
) -> Float64:
    """Return the room for the crown moment at a thrust: the upper bound
    less the lower bound. A negative value means no line of thrust fits."""
    var low = -inf[DType.float64]()
    var high = inf[DType.float64]()
    # The crown joint is always there, so the loop always runs.
    for k in range(len(joints.sine)):  # pragma: no branch
        var x_in = r_in * joints.sine[k]
        var y_in = joints.center + r_in * joints.cosine[k]
        var x_ex = r_ex * joints.sine[k]
        var y_ex = joints.center + r_ex * joints.cosine[k]
        var a_in = joints.moment[k] - joints.weight[k] * x_in
        var a_ex = joints.moment[k] - joints.weight[k] * x_ex
        low = max(low, y_in * thrust - a_in)
        high = min(high, y_ex * thrust - a_ex)
    return high - low


def _widest(
    joints: _Joints, r_in: Float64, r_ex: Float64, limit: Float64
) -> Float64:
    """Return the thrust with the most room, by golden-section search."""
    var ratio = (sqrt(5.0) - 1.0) / 2.0
    var a = 0.0
    var b = limit
    for _ in range(120):
        var c = b - ratio * (b - a)
        var d = a + ratio * (b - a)
        if _interval(joints, r_in, r_ex, c) < _interval(joints, r_in, r_ex, d):
            a = c
        else:
            b = d
    return (a + b) / 2.0


def _bounds(
    joints: _Joints, r_in: Float64, r_ex: Float64, limit: Float64
) -> Tuple[Bool, Float64, Float64]:
    """Return whether a line of thrust fits, and the least and the greatest
    thrust of one that does."""
    var best = _widest(joints, r_in, r_ex, limit)
    var tolerance = 1e-9 * (1.0 + joints.weight[len(joints.weight) - 1] * r_ex)
    if _interval(joints, r_in, r_ex, best) < -tolerance:
        return (False, 0.0, 0.0)
    var low = 0.0
    var high = best
    for _ in range(80):
        var middle = (low + high) / 2.0
        if _interval(joints, r_in, r_ex, middle) >= 0.0:
            high = middle
        else:
            low = middle
    var least = high
    low = best
    high = limit
    if _interval(joints, r_in, r_ex, high) < 0.0:
        for _ in range(80):
            var middle = (low + high) / 2.0
            if _interval(joints, r_in, r_ex, middle) >= 0.0:
                low = middle
            else:
                high = middle
    return (True, least, low)


def analyze_arch(
    span: Length64,
    rise: Length64,
    ring: Length64,
    width: Length64,
    masonry: Masonry,
    fill_weight: UnitWeight64,
    fill_depth: Length64,
    surcharge: Pressure64,
    voussoirs: Int,
) raises -> ArchResult:
    """Find the line of thrust of a symmetric circular arch.

    The arch is a segment of a circle. Its intrados springs from a level
    line, `span` apart, and rises `rise` at the crown. The loads are the
    ring, the fill from the extrados up to a deck `fill_depth` above the
    crown, and a uniform `surcharge` on the deck. The fill carries no load
    sideways and does not stiffen the arch.

    Args:
        span: The clear span at the springing line.
        rise: The rise of the intrados at the crown. It must not exceed
            half the span.
        ring: The thickness of the ring, measured along a radius.
        width: The width of the arch along its axis.
        masonry: The masonry of the ring.
        fill_weight: The unit weight of the fill above the ring. Zero with
            a zero load leaves a bare ring that carries only itself.
        fill_depth: The depth of fill above the extrados at the crown.
        surcharge: The load on the deck, per area. Zero or more.
        voussoirs: The number of voussoirs in the half arch, at least 2.

    Returns:
        Whether a line of thrust fits, the least and greatest thrust, the
        reaction, the geometric factor and the least thickness.

    Raises:
        Error: If a size or the masonry is not valid, the rise is more than
            half the span, the fill weight, the fill depth or the load is
            negative, or there are fewer than two voussoirs.
    """
    masonry.check()
    require_positive_finite(span.value, "An arch span must be positive")
    require_positive_finite(rise.value, "An arch rise must be positive")
    require_positive_finite(ring.value, "An arch ring must be positive")
    require_positive_finite(width.value, "An arch width must be positive")
    if not (fill_weight.value >= 0.0 and fill_weight.value < 1.0e12):
        raise Error("A fill weight must be zero or more")
    if not (fill_depth.value >= 0.0 and fill_depth.value < 1.0e9):
        raise Error("A fill depth must be zero or more")
    if not (surcharge.value >= 0.0 and surcharge.value < 1.0e12):
        raise Error("A surcharge must be zero or more")
    if voussoirs < 2:
        raise Error("An arch needs at least two voussoirs in its half")
    if not rise.value * 2.0 <= span.value:
        raise Error("An arch cannot rise more than half its span")
    var half_span = span.value / 2.0
    var f = rise.value
    var r_in = (half_span * half_span + f * f) / (2.0 * f)
    var t = ring.value
    var r_ex = r_in + t
    var center = f - r_in
    var springing = pi / 2.0
    if f < half_span:
        springing = asin(half_span / r_in)
    var joints = _Joints(center)
    var top = f + t + fill_depth.value
    var gamma = masonry.unit_weight().value
    var weight = 0.0
    var moment = 0.0
    joints.sine.append(0.0)
    joints.cosine.append(1.0)
    joints.weight.append(0.0)
    joints.moment.append(0.0)
    # There are two voussoirs at least, so the loop always runs.
    for j in range(1, voussoirs + 1):  # pragma: no branch
        var a0 = springing * Float64(j - 1) / Float64(voussoirs)
        var a1 = springing * Float64(j) / Float64(voussoirs)
        var load = _segment(
            r_in,
            r_ex,
            top,
            center,
            a0,
            a1,
            gamma,
            fill_weight.value,
            surcharge.value,
            width.value,
        )
        weight += load[0]
        moment += load[1]
        joints.sine.append(sin(a1))
        joints.cosine.append(cos(a1))
        joints.weight.append(weight)
        joints.moment.append(moment)
    var limit = 100.0 * weight
    var mid = r_in + t / 2.0
    var found = _bounds(joints, r_in, r_ex, limit)
    # Find the least envelope that still holds a line of thrust.
    var low = 0.0
    var high = 50.0 * t
    if high > 1.99 * mid:
        high = 1.99 * mid
    for _ in range(60):
        var middle = (low + high) / 2.0
        if _bounds(joints, mid - middle / 2.0, mid + middle / 2.0, limit)[0]:
            high = middle
        else:
            low = middle
    var least = high
    return ArchResult(
        found[0],
        Force64(found[1]),
        Force64(found[2]),
        Force64(weight),
        t / least,
        Length64(least),
    )


def analyze_bridge(
    bridge: Bridge,
    masonry: Masonry,
    fill_weight: UnitWeight64,
    surcharge: Pressure64,
    voussoirs: Int,
) raises -> ArchResult:
    """Find the line of thrust of one arch of a bridge.

    Every arch of a `Bridge` is the same, and the load is the same on all
    of them, so one arch stands for the row. The thrusts of two arches
    that meet at a pier cancel, and an end arch pushes on an abutment.

    Args:
        bridge: The bridge.
        masonry: The masonry of the arch ring.
        fill_weight: The unit weight of the fill above the ring.
        surcharge: The load on the deck, per area.
        voussoirs: The number of voussoirs in the half arch.

    Returns:
        The result for one arch.

    Raises:
        Error: If the bridge or an input is not valid.
    """
    bridge.check()
    return analyze_arch(
        bridge.span,
        bridge.rise,
        bridge.ring,
        bridge.width,
        masonry,
        fill_weight,
        bridge.fill,
        surcharge,
        voussoirs,
    )
