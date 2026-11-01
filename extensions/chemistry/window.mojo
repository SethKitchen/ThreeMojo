# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Operating windows: where in a temperature range constraints hold.

`met_intervals` samples one constraint over a range at a fixed pressure
and finds each change by bisection. `intersect` keeps the temperatures in
two lists of intervals. `window_of` intersects the intervals of a list of
constraints. All three accept any type that implements `Constraint`, so a
constraint defined outside this package works with them:

    var window = window_of(step.requirements, low, high, pressure)
    window = intersect(window, met_intervals(my_constraint, low, high,
                                             pressure))

A change narrower than the sampling, a 400th of the range, can be missed.
"""

from extensions.chemistry.requirement import Constraint, kelvin_text
from std.math import isfinite
from units.si import Pressure64
from units.temperature import Temperature64

# The samples of a constraint over a search range.
comptime SAMPLES = 400
# Bisection steps for a window edge: far below a microkelvin.
comptime _BISECTIONS = 60


@fieldwise_init
struct Interval(ImplicitlyCopyable):
    """A range of temperature, low end first."""

    var low: Temperature64
    var high: Temperature64


def interval_text(interval: Interval) raises -> String:
    """Return a range in kelvin and degrees Celsius.

    Args:
        interval: The range.

    Returns:
        Text such as "987.0 K (713.9 degC) to 1358.2 K (1085.0 degC)".

    Raises:
        Error: Never. The digit count is a constant.
    """
    return kelvin_text(interval.low) + " to " + kelvin_text(interval.high)


def _require_search(
    low: Temperature64, high: Temperature64, pressure: Pressure64
) raises:
    """Refuse a search range or a pressure that is not physical."""
    if not (isfinite(pressure.value) and pressure.value > 0):
        raise Error("A pressure must be finite and positive")
    if not (low.is_valid() and high.is_valid() and low.kelvin < high.kelvin):
        raise Error("A search range must be physical and increase")


def _edge[
    C: Constraint
](
    constraint: C,
    low: Float64,
    high: Float64,
    low_holds: Bool,
    pressure: Pressure64,
) raises -> Float64:
    """Return where a constraint changes between two temperatures."""
    var lo = low
    var hi = high
    for _ in range(_BISECTIONS):  # pragma: no branch
        var mid = 0.5 * (lo + hi)
        if constraint.holds(Temperature64(mid), pressure) == low_holds:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def met_intervals[
    C: Constraint
](
    constraint: C,
    low: Temperature64,
    high: Temperature64,
    pressure: Pressure64,
) raises -> List[Interval]:
    """Return where in a range a constraint holds.

    Parameters:
        C: The constraint's type.

    Args:
        constraint: The constraint.
        low: The low end of the range.
        high: The high end of the range.
        pressure: The pressure.

    Returns:
        The intervals, coldest first.

    Raises:
        Error: If the range or the pressure is not physical, or the
            constraint cannot be evaluated.
    """
    _require_search(low, high, pressure)
    var out = List[Interval]()
    var a = low.kelvin
    var b = high.kelvin
    var previous = a
    var was_met = constraint.holds(low, pressure)
    var start = a
    for i in range(1, SAMPLES + 1):  # pragma: no branch
        var t = a + (b - a) * Float64(i) / Float64(SAMPLES)
        var met = constraint.holds(Temperature64(t), pressure)
        if met != was_met:
            var edge = _edge(constraint, previous, t, was_met, pressure)
            if met:
                start = edge
            else:
                out.append(Interval(Temperature64(start), Temperature64(edge)))
            was_met = met
        previous = t
    if was_met:
        out.append(Interval(Temperature64(start), high))
    return out^


def intersect(a: List[Interval], b: List[Interval]) -> List[Interval]:
    """Return the temperatures in both of two lists of intervals.

    Args:
        a: Intervals, coldest first, that do not overlap.
        b: Intervals, coldest first, that do not overlap.

    Returns:
        The intervals of temperature in both lists, coldest first.
    """
    var out = List[Interval]()
    var i = 0
    var j = 0
    while i < len(a) and j < len(b):
        var lo = max(a[i].low.kelvin, b[j].low.kelvin)
        var hi = min(a[i].high.kelvin, b[j].high.kelvin)
        if lo < hi:
            out.append(Interval(Temperature64(lo), Temperature64(hi)))
        if a[i].high.kelvin < b[j].high.kelvin:
            i += 1
        else:
            j += 1
    return out^


def window_of[
    C: Constraint
](
    constraints: List[C],
    low: Temperature64,
    high: Temperature64,
    pressure: Pressure64,
) raises -> List[Interval]:
    """Return where in a range every constraint of a list holds.

    Parameters:
        C: The constraints' type.

    Args:
        constraints: The constraints. With none, the whole range holds.
        low: The low end of the range.
        high: The high end of the range.
        pressure: The pressure.

    Returns:
        The intervals, coldest first. An empty list means no temperature
        in the range meets every constraint.

    Raises:
        Error: If the range or the pressure is not physical, or a
            constraint cannot be evaluated.
    """
    _require_search(low, high, pressure)
    var window = List[Interval]()
    window.append(Interval(low, high))
    for c in constraints:
        window = intersect(window, met_intervals(c, low, high, pressure))
    return window^
