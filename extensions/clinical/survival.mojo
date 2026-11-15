# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The survival of groups of patients: Kaplan-Meier curves.

Clinical research follows patients from a start, such as a diagnosis or a
treatment, to an event, such as a relapse or a death. A patient who leaves
the study before the event is censored at the time last seen.

- `kaplan_meier(times, events)` gives the survival curve. At each time of
  an event, the survival falls by `1 - d / n`, with `d` the events then
  and `n` the patients still at risk. A patient censored at a time is at
  risk at that time.
- `SurvivalCurve.interval(i)` is the 95 percent interval of the
  exponential Greenwood formula, which keeps it between 0 and 1:
  `S^exp(+-1.96 sqrt(v))`, with `v` the sum of `d / (n (n - d))` over
  `(ln S)^2`.
- `SurvivalCurve.median()` is the first time of an event at which the
  survival is a half or less.
- `logrank` compares the survival of groups.
- `survival_image` plots the curves as steps, with a tick at each
  censored time.
"""

from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from render.framebuffer import Color, Framebuffer
from std.math import exp, floor, inf, isfinite, log, sqrt
from units.quantity import Unit
from units.si import Duration64, SECOND
from extensions.numerics.distributions import Z95
from extensions.numerics.order import ascending_order


struct SurvivalCurve(Copyable, Movable):
    """A Kaplan-Meier curve: the survival after each time of an event."""

    var times: List[Duration64]
    """Each time at which one event or more happened, rising."""
    var survival: List[Float64]
    """The survival just after each time."""
    var at_risk: List[Int]
    """The patients at risk just before each time."""
    var events: List[Int]
    """The events at each time."""
    var greenwood: List[Float64]
    """The sum of `d / (n (n - d))` up to each time. Infinite once no
    patient is left."""
    var censored: List[Duration64]
    """The time of each censored patient, rising."""
    var patients: Int
    """The patients of the group."""

    def __init__(out self, patients: Int):
        """Create a curve with no event yet.

        Args:
            patients: The patients of the group.
        """
        self.times = List[Duration64]()
        self.survival = List[Float64]()
        self.at_risk = List[Int]()
        self.events = List[Int]()
        self.greenwood = List[Float64]()
        self.censored = List[Duration64]()
        self.patients = patients

    def at(self, time: Duration64) -> Float64:
        """Return the survival at a time.

        Args:
            time: The time.

        Returns:
            1 before the first event, and the survival after the last
            event at or before the time from then on.
        """
        var t = time.to(SECOND)
        var out = 1.0
        for i in range(len(self.times)):
            if self.times[i].to(SECOND) > t:
                break
            out = self.survival[i]
        return out

    def median(self) -> Tuple[Bool, Duration64]:
        """Return the median survival time.

        Returns:
            Whether the survival falls to a half, and the first time of an
            event at which it is a half or less.
        """
        for i in range(len(self.times)):
            if self.survival[i] <= 0.5:
                return (True, self.times[i])
        return (False, Duration64(0, SECOND))

    def interval(self, index: Int) raises -> Tuple[Float64, Float64]:
        """Return the 95 percent interval of the survival at a time.

        Args:
            index: The time, from 0, in `times`.

        Returns:
            The low and the high end, by the exponential Greenwood
            formula. Both are 0 once no patient is left.

        Raises:
            Error: If the index names no time.
        """
        if index < 0 or index >= len(self.times):
            raise Error("A survival curve has no time of that index")
        var s = self.survival[index]
        if not (s > 0):
            return (0.0, 0.0)
        var lns = log(s)
        var c = Z95 * sqrt(self.greenwood[index]) / abs(lns)
        return (exp(lns * exp(c)), exp(lns * exp(-c)))


def require_group(times: List[Duration64], events: List[Bool]) raises:
    """Refuse a group with no patient, lists of two lengths, or a time
    that is negative or not finite.

    Args:
        times: The time of each patient.
        events: Whether each patient had the event.

    Raises:
        Error: If the group is not valid.
    """
    if len(times) == 0 or len(times) != len(events):
        raise Error("A group needs one patient or more, each with an event")
    for t in times:  # pragma: no branch
        var s = t.to(SECOND)
        if not (s >= 0) or not isfinite(s):
            raise Error("A survival time must be 0 or more, and finite")


def kaplan_meier(
    times: List[Duration64], events: List[Bool]
) raises -> SurvivalCurve:
    """Return the Kaplan-Meier curve of a group.

    Args:
        times: The time of each patient, to the event or to the censoring.
        events: Whether each patient had the event, or was censored.

    Returns:
        The curve.

    Raises:
        Error: If there is no patient, the lists differ in length, or a
            time is negative or not finite.
    """
    require_group(times, events)
    var seconds = List[Float64]()
    for t in times:  # pragma: no branch
        seconds.append(t.to(SECOND))
    var order = ascending_order(seconds)
    var out = SurvivalCurve(len(times))
    var risk = len(times)
    var s = 1.0
    var sum = 0.0
    var at = 0
    while at < len(order):
        var t = times[order[at]].to(SECOND)
        var d = 0
        var c = 0
        while at < len(order) and times[order[at]].to(SECOND) == t:
            if events[order[at]]:
                d += 1
            else:
                c += 1
                out.censored.append(times[order[at]])
            at += 1
        if d > 0:
            s *= 1.0 - Float64(d) / Float64(risk)
            if d < risk:
                sum += Float64(d) / (Float64(risk) * Float64(risk - d))
            else:
                sum = inf[DType.float64]()
            out.times.append(Duration64(t, SECOND))
            out.survival.append(s)
            out.at_risk.append(risk)
            out.events.append(d)
            out.greenwood.append(sum)
        risk -= d + c
    return out^


def survival_image(
    curves: List[SurvivalCurve],
    colors: List[Rgba],
    top: Duration64,
    grid: Duration64,
    width: Int,
    height: Int,
) raises -> Framebuffer:
    """Plot Kaplan-Meier curves as steps, with a tick at each censoring.

    The time runs from 0 at the left edge to `top` at the right edge. The
    survival runs from 0 at the bottom edge to 1 at the top edge. Light
    gray lines mark each `grid` of time and each tenth of survival.

    Args:
        curves: The curves, one or more.
        colors: The color of each curve.
        top: The time at the right edge. Positive and finite.
        grid: The time between two gray lines. Positive and finite, with
            no more than 100 lines to `top`.
        width: The width of the image, from 64 to 4096 pixels.
        height: The height of the image, from 64 to 4096 pixels.

    Returns:
        A white image with a dark frame.

    Raises:
        Error: If there is no curve, the colors are not one for each
            curve, or a time or a size is out of range.
    """
    if len(curves) == 0 or len(colors) != len(curves):
        raise Error("A survival plot needs one color for each of its curves")
    if width < 64 or width > 4096 or height < 64 or height > 4096:
        raise Error("A survival plot is from 64 to 4096 pixels on each side")
    var t = top.to(SECOND)
    var g = grid.to(SECOND)
    if not (t > 0) or not isfinite(t):
        raise Error("The top time of a survival plot must be positive")
    if not (g > 0) or not isfinite(g) or t / g > 100.0:
        raise Error("A survival plot has a positive grid of at most 100 lines")
    var image = Framebuffer(width, height, Color(255, 255, 255))
    var light = Rgba(0.84, 0.84, 0.86, 1)
    var right = Float64(width - 1)
    var bottom = Float64(height - 1)
    for n in range(1, Int(floor(t / g + 1e-9)) + 1):
        var x = Int(floor(Float64(n) * g / t * right + 0.5))
        draw_line(image, x, 0, x, height - 1, light)
    for n in range(1, 10):  # pragma: no branch
        var y = Int(floor(Float64(n) / 10.0 * bottom + 0.5))
        draw_line(image, 0, y, width - 1, y, light)
    var dark = Rgba(0.24, 0.24, 0.26, 1)
    draw_line(image, 0, 0, width - 1, 0, dark)
    draw_line(image, 0, height - 1, width - 1, height - 1, dark)
    draw_line(image, 0, 0, 0, height - 1, dark)
    draw_line(image, width - 1, 0, width - 1, height - 1, dark)
    for c in range(len(curves)):  # pragma: no branch
        ref curve = curves[c]
        var color = colors[c]
        var x0 = 0
        var y0 = 0
        for i in range(len(curve.times)):
            var x = Int(floor(curve.times[i].to(SECOND) / t * right + 0.5))
            var y = Int(floor((1.0 - curve.survival[i]) * bottom + 0.5))
            # Along at the old survival, then down at the time.
            draw_line(image, x0, y0, x, y0, color)
            draw_line(image, x, y0, x, y, color)
            x0 = x
            y0 = y
        draw_line(image, x0, y0, width - 1, y0, color)
        for time in curve.censored:
            var x = Int(floor(time.to(SECOND) / t * right + 0.5))
            var y = Int(floor((1.0 - curve.at(time)) * bottom + 0.5))
            draw_line(image, x, y - 4, x, y + 4, color)
    return image^
