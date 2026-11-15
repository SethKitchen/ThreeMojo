# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Competing risks: the cumulative incidence of one cause of failure when
another cause can come first.

A patient who dies of another cause can no longer relapse. The
Kaplan-Meier curve of relapse, with the deaths censored, takes them as if
they could still relapse. So `1 - S` overstates the risk of relapse. The
Aalen-Johansen estimate does not:

    F(t) = sum over the event times t_i <= t of S(t_(i-1)) d_i / n_i

`S` is the Kaplan-Meier survival from every cause, `d_i` counts the events
of the cause of interest at `t_i`, and `n_i` the patients at risk.

- `cumulative_incidence(times, events, competing)` gives F at each time of
  an event of either cause, with the delta-method variance of Collett, as
  lifelines gives it, and intervals on the log(-log) scale.
- `incidence_image` draws curves of F as rising steps.

With no competing event, F is `1 - S` of `survival.kaplan_meier`, and its
variance is Greenwood's.
"""

from extensions.numerics.elementary import precise_exp
from extensions.clinical.survival import require_group
from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from render.framebuffer import Color, Framebuffer
from std.math import floor, isfinite, log, sqrt
from units.si import Duration64, SECOND
from extensions.numerics.distributions import Z95
from extensions.numerics.order import ascending_order


struct CumulativeIncidence(Copyable, Movable):
    """The cumulative incidence of one cause after each time of an event of
    any cause."""

    var times: List[Duration64]
    """Each time at which one event or more of any cause happened, rising."""
    var incidence: List[Float64]
    """The cumulative incidence of the cause just after each time."""
    var variance: List[Float64]
    """The variance of the incidence at each time."""
    var at_risk: List[Int]
    """The patients at risk just before each time."""
    var events: List[Int]
    """The events of the cause of interest at each time."""
    var competing: List[Int]
    """The competing events at each time."""
    var patients: Int
    """The patients of the group."""

    def __init__(out self, patients: Int):
        """Create a curve with no event yet.

        Args:
            patients: The patients of the group.
        """
        self.times = List[Duration64]()
        self.incidence = List[Float64]()
        self.variance = List[Float64]()
        self.at_risk = List[Int]()
        self.events = List[Int]()
        self.competing = List[Int]()
        self.patients = patients

    def at(self, time: Duration64) -> Float64:
        """Return the cumulative incidence at a time.

        Args:
            time: The time.

        Returns:
            0 before the first event, and the incidence after the last
            event at or before the time from then on.
        """
        var t = time.to(SECOND)
        var out = 0.0
        for i in range(len(self.times)):
            if self.times[i].to(SECOND) > t:
                break
            out = self.incidence[i]
        return out

    def interval(self, index: Int) raises -> Tuple[Float64, Float64]:
        """Return the 95 percent interval of the incidence at a time.

        The interval is symmetric for `log(-log F)`, with the standard error
        `sqrt(var) / (F |log F|)`, so it stays between 0 and 1.

        Args:
            index: The time, from 0, in `times`.

        Returns:
            The low and the high end. Both are 0 while the incidence is 0,
            and 1 once it is 1.

        Raises:
            Error: If the index names no time.
        """
        if index < 0 or index >= len(self.times):
            raise Error("A cumulative incidence has no time of that index")
        var f = self.incidence[index]
        if not (f > 0):
            return (0.0, 0.0)
        if not (f < 1):
            return (1.0, 1.0)
        var lnf = log(f)
        var c = Z95 * sqrt(self.variance[index]) / (f * abs(lnf))
        return (
            precise_exp(lnf * precise_exp(c)),
            precise_exp(lnf * precise_exp(-c)),
        )


def cumulative_incidence(
    times: List[Duration64], events: List[Bool], competing: List[Bool]
) raises -> CumulativeIncidence:
    """Return the Aalen-Johansen cumulative incidence of a cause.

    Events of both causes at one time count at once. lifelines jitters such
    ties apart at random instead.

    Args:
        times: The time of each patient, to the first event or to the
            censoring.
        events: Whether each patient had the event of interest first.
        competing: Whether each patient had a competing event first.

    Returns:
        The incidence and its variance at each time of an event of either
        cause.

    Raises:
        Error: If there is no patient, the lists differ in length, a time is
            negative or not finite, or a patient has both events.
    """
    require_group(times, events)
    var n = len(times)
    if len(competing) != n:
        raise Error("A competing risk needs one competing event per patient")
    var seconds = List[Float64]()
    for i in range(n):  # pragma: no branch
        if events[i] and competing[i]:
            raise Error("A patient has one first event at most")
        seconds.append(times[i].to(SECOND))
    var order = ascending_order(seconds)
    var out = CumulativeIncidence(n)
    # The survival from every cause just before each time.
    var before = List[Float64]()
    var risk = n
    var s = 1.0
    var f = 0.0
    var at = 0
    while at < n:
        var t = times[order[at]].to(SECOND)
        var d = 0
        var other = 0
        var censored = 0
        while at < n and times[order[at]].to(SECOND) == t:
            if events[order[at]]:
                d += 1
            elif competing[order[at]]:
                other += 1
            else:
                censored += 1
            at += 1
        if d + other > 0:
            f += s * Float64(d) / Float64(risk)
            out.times.append(Duration64(t, SECOND))
            out.incidence.append(f)
            out.at_risk.append(risk)
            out.events.append(d)
            out.competing.append(other)
            before.append(s)
            s *= 1.0 - Float64(d + other) / Float64(risk)
        risk -= d + other + censored
    # The delta-method variance of each incidence, summed over the times up
    # to it.
    for m in range(len(out.times)):  # pragma: no branch
        var total = 0.0
        for i in range(m + 1):  # pragma: no branch
            var gap = out.incidence[m] - out.incidence[i]
            var size = Float64(out.at_risk[i])
            var failed = Float64(out.events[i] + out.competing[i])
            var own = Float64(out.events[i])
            # When every patient at risk fails, the gap is 0 from then on.
            if failed < size:
                total += gap * gap * failed / (size * (size - failed))
            total += (
                before[i]
                * before[i]
                * own
                * (size - own)
                / (size * size * size)
            )
            total -= 2.0 * gap * before[i] * own / (size * size)
        out.variance.append(total)
    return out^


def incidence_image(
    curves: List[CumulativeIncidence],
    colors: List[Rgba],
    top: Duration64,
    grid: Duration64,
    ceiling: Float64,
    width: Int,
    height: Int,
) raises -> Framebuffer:
    """Plot cumulative incidences as rising steps.

    The time runs from 0 at the left edge to `top` at the right edge. The
    incidence runs from 0 at the bottom edge to `ceiling` at the top edge.
    Light gray lines mark each `grid` of time and each tenth of the height.

    Args:
        curves: The curves, one or more.
        colors: The color of each curve.
        top: The time at the right edge. Positive and finite.
        grid: The time between two gray lines. Positive and finite, with
            no more than 100 lines to `top`.
        ceiling: The incidence at the top edge, above 0 and at most 1.
        width: The width of the image, from 64 to 4096 pixels.
        height: The height of the image, from 64 to 4096 pixels.

    Returns:
        A white image with a dark frame.

    Raises:
        Error: If there is no curve, the colors are not one for each
            curve, or a time, the ceiling or a size is out of range.
    """
    if len(curves) == 0 or len(colors) != len(curves):
        raise Error("An incidence plot needs one color for each of its curves")
    if width < 64 or width > 4096 or height < 64 or height > 4096:
        raise Error("An incidence plot is from 64 to 4096 pixels on each side")
    var t = top.to(SECOND)
    var g = grid.to(SECOND)
    if not (t > 0) or not isfinite(t):
        raise Error("The top time of an incidence plot must be positive")
    if not (g > 0) or not isfinite(g) or t / g > 100.0:
        raise Error(
            "An incidence plot has a positive grid of at most 100 lines"
        )
    if not (ceiling > 0 and ceiling <= 1):
        raise Error("The ceiling of an incidence plot is above 0 and at most 1")
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
        var x0 = 0
        var y0 = height - 1
        for i in range(len(curve.times)):
            var x = Int(
                floor(min(curve.times[i].to(SECOND) / t, 2.0) * right + 0.5)
            )
            var rise = min(curve.incidence[i] / ceiling, 2.0)
            var y = Int(floor((1.0 - rise) * bottom + 0.5))
            # Along at the old incidence, then up at the time.
            draw_line(image, x0, y0, x, y0, colors[c])
            draw_line(image, x, y0, x, y, colors[c])
            x0 = x
            y0 = y
        draw_line(image, x0, y0, width - 1, y0, colors[c])
    return image^
