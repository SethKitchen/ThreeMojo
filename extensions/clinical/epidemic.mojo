# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compartment models of an epidemic: SIR and SEIR.

A population falls into fractions: susceptible S, exposed E (infected, not
yet infectious), infectious I, and removed R (recovered or immune). The
SEIR model is

    dS/dt = -b S I,  dE/dt = b S I - s E,  dI/dt = s E - g I,  dR/dt = g I,

with `g` one over the infectious period, `s` one over the latent period,
and `b = R0 g`. The SIR model has no E: an infection is infectious at once.

- `seir` and `sir` integrate an epidemic by the classical Runge-Kutta
  method, in equal steps, and record each step.
- `EpidemicCurve.peak` gives the time and the size of the largest
  infectious fraction.
- `final_susceptible` gives the fraction never infected, from the final
  size relation `ln(S0 / S) = R0 (1 - p - S)` with `p` the immune
  fraction at the start.
- `herd_immunity` gives the immune fraction that stops growth,
  `1 - 1 / R0`.
- `epidemic_image` plots the infectious fraction of several epidemics.

The periods are durations. The models mix the population evenly, with no
age, place, birth or death.
"""

from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from render.framebuffer import Color, Framebuffer
from std.math import exp, floor, isfinite, log
from units.si import DAY64, Duration64

# The most steps of one epidemic.
comptime MAX_STEPS = 1000000


struct EpidemicCurve(Copyable, Movable):
    """The fractions of a population at each step of an epidemic."""

    var times: List[Duration64]
    """The time of each record, from 0."""
    var susceptible: List[Float64]
    """The susceptible fraction S."""
    var exposed: List[Float64]
    """The exposed fraction E. 0 in an SIR epidemic."""
    var infectious: List[Float64]
    """The infectious fraction I."""
    var removed: List[Float64]
    """The removed fraction R."""

    def __init__(out self):
        """Create an empty curve."""
        self.times = List[Duration64]()
        self.susceptible = List[Float64]()
        self.exposed = List[Float64]()
        self.infectious = List[Float64]()
        self.removed = List[Float64]()

    def peak(self) raises -> Tuple[Duration64, Float64]:
        """Return the largest infectious fraction and its time.

        Returns:
            The time of the first record with the largest infectious
            fraction, and that fraction.

        Raises:
            Error: If the curve has no record.
        """
        if len(self.times) == 0:
            raise Error("An epidemic with no record has no peak")
        var best = 0
        for k in range(1, len(self.infectious)):
            if self.infectious[k] > self.infectious[best]:
                best = k
        return (self.times[best], self.infectious[best])


def _require_start(r0: Float64, infected: Float64, immune: Float64) raises:
    """Refuse an R0 or a start out of range."""
    if not (r0 > 0) or not isfinite(r0):
        raise Error("R0 must be positive and finite")
    if not (infected > 0 and infected <= 1):
        raise Error("The infected fraction at the start must be in (0, 1]")
    if not (immune >= 0 and immune + infected <= 1):
        raise Error("The immune and infected fractions must sum to 1 or less")


def _require_period(period: Duration64) raises -> Float64:
    """Return a period in days, or refuse one that is not positive and
    finite."""
    var days = period.to(DAY64)
    if not (days > 0) or not isfinite(days):
        raise Error("A period of an epidemic must be positive and finite")
    return days


def _rates(
    s: Float64,
    e: Float64,
    i: Float64,
    b: Float64,
    sigma: Float64,
    g: Float64,
) -> Tuple[Float64, Float64, Float64, Float64]:
    """Return dS, dE, dI and dR per day. A sigma of 0 means no latent
    stage."""
    var infection = b * s * i
    var recovery = g * i
    if sigma == 0:
        return (-infection, 0.0, infection - recovery, recovery)
    var onset = sigma * e
    return (-infection, infection - onset, onset - recovery, recovery)


def _integrate(
    r0: Float64,
    sigma: Float64,
    g: Float64,
    infected: Float64,
    immune: Float64,
    step: Duration64,
    end: Duration64,
) raises -> EpidemicCurve:
    """Integrate by the classical Runge-Kutta method, in equal steps that
    divide the end time."""
    var h_days = _require_period(step)
    var end_days = _require_period(end)
    var ratio = end_days / h_days
    if not (ratio <= Float64(MAX_STEPS)):
        raise Error("An epidemic takes at most 1000000 steps")
    var n = max(1, Int(floor(ratio + 0.5)))
    var h = end_days / Float64(n)
    var b = r0 * g
    var s = 1.0 - infected - immune
    var e = 0.0
    var i = infected
    var r = immune
    var out = EpidemicCurve()
    for k in range(n + 1):  # pragma: no branch
        out.times.append(Duration64(Float64(k) * h, DAY64))
        out.susceptible.append(s)
        out.exposed.append(e)
        out.infectious.append(i)
        out.removed.append(r)
        if k == n:
            break
        var k1 = _rates(s, e, i, b, sigma, g)
        var k2 = _rates(
            s + 0.5 * h * k1[0],
            e + 0.5 * h * k1[1],
            i + 0.5 * h * k1[2],
            b,
            sigma,
            g,
        )
        var k3 = _rates(
            s + 0.5 * h * k2[0],
            e + 0.5 * h * k2[1],
            i + 0.5 * h * k2[2],
            b,
            sigma,
            g,
        )
        var k4 = _rates(
            s + h * k3[0], e + h * k3[1], i + h * k3[2], b, sigma, g
        )
        s += h / 6.0 * (k1[0] + 2.0 * k2[0] + 2.0 * k3[0] + k4[0])
        e += h / 6.0 * (k1[1] + 2.0 * k2[1] + 2.0 * k3[1] + k4[1])
        i += h / 6.0 * (k1[2] + 2.0 * k2[2] + 2.0 * k3[2] + k4[2])
        r += h / 6.0 * (k1[3] + 2.0 * k2[3] + 2.0 * k3[3] + k4[3])
    return out^


def seir(
    r0: Float64,
    latent: Duration64,
    infectious: Duration64,
    infected: Float64,
    immune: Float64,
    step: Duration64,
    end: Duration64,
) raises -> EpidemicCurve:
    """Integrate an SEIR epidemic.

    Args:
        r0: The basic reproduction number: the infections that one case
            causes in a population with no immunity. Positive.
        latent: The mean latent period, from infection to infectiousness.
        infectious: The mean infectious period.
        infected: The infectious fraction at the start, in (0, 1].
        immune: The immune fraction at the start, such as the vaccinated.
        step: The time step. It is adjusted so that equal steps reach the
            end.
        end: The end time.

    Returns:
        The fractions at each step, from 0 to the end.

    Raises:
        Error: If R0, a fraction, a period or a time is out of range, or
            there would be more than 1000000 steps.
    """
    _require_start(r0, infected, immune)
    var sigma = 1.0 / _require_period(latent)
    var g = 1.0 / _require_period(infectious)
    return _integrate(r0, sigma, g, infected, immune, step, end)


def sir(
    r0: Float64,
    infectious: Duration64,
    infected: Float64,
    immune: Float64,
    step: Duration64,
    end: Duration64,
) raises -> EpidemicCurve:
    """Integrate an SIR epidemic.

    Args:
        r0: The basic reproduction number. Positive.
        infectious: The mean infectious period.
        infected: The infectious fraction at the start, in (0, 1].
        immune: The immune fraction at the start.
        step: The time step. It is adjusted so that equal steps reach the
            end.
        end: The end time.

    Returns:
        The fractions at each step, with no exposed fraction.

    Raises:
        Error: If R0, a fraction, a period or a time is out of range, or
            there would be more than 1000000 steps.
    """
    _require_start(r0, infected, immune)
    var g = 1.0 / _require_period(infectious)
    return _integrate(r0, 0.0, g, infected, immune, step, end)


def final_susceptible(
    r0: Float64, infected: Float64, immune: Float64
) raises -> Float64:
    """Return the fraction of a population never infected.

    The fraction S solves `ln(S0 / S) = R0 (1 - p - S)`, with `S0 = 1 - p -
    i0`. The left side less the right is convex in S, positive near 0 and
    negative at S0, so Newton steps from `S0 exp(-R0 (1 - p))` rise to the
    one root.

    Args:
        r0: The basic reproduction number. Positive.
        infected: The infected fraction at the start, in (0, 1].
        immune: The immune fraction at the start.

    Returns:
        The susceptible fraction when the epidemic is over.

    Raises:
        Error: If R0 or a fraction is out of range.
    """
    _require_start(r0, infected, immune)
    var s0 = 1.0 - immune - infected
    if s0 == 0:
        return 0.0
    var reach = 1.0 - immune
    var s = s0 * exp(-r0 * reach)
    for _ in range(100):  # pragma: no branch
        var gap = log(s0 / s) - r0 * (reach - s)
        var next = s - gap / (r0 - 1.0 / s)
        if not (next > s * (1.0 + 1e-16)):
            break
        s = next
    return s


def herd_immunity(r0: Float64) raises -> Float64:
    """Return the immune fraction above which an epidemic cannot grow.

    Args:
        r0: The basic reproduction number. Positive and finite.

    Returns:
        `1 - 1 / R0`, or 0 when R0 is 1 or less.

    Raises:
        Error: If R0 is not positive and finite.
    """
    if not (r0 > 0) or not isfinite(r0):
        raise Error("R0 must be positive and finite")
    return max(0.0, 1.0 - 1.0 / r0)


def epidemic_image(
    curves: List[EpidemicCurve],
    colors: List[Rgba],
    end: Duration64,
    grid: Duration64,
    top: Float64,
    width: Int,
    height: Int,
) raises -> Framebuffer:
    """Plot the infectious fraction of several epidemics.

    The time runs from 0 at the left edge to `end` at the right edge. The
    fraction runs from 0 at the bottom edge to `top` at the top edge. Light
    gray lines mark each `grid` of time and each tenth of `top`.

    Args:
        curves: The epidemics, one or more.
        colors: The color of each epidemic.
        end: The time at the right edge. Positive and finite.
        grid: The time between two gray lines. Positive and finite, with no
            more than 100 lines to `end`.
        top: The fraction at the top edge, in (0, 1].
        width: The width of the image, from 64 to 4096 pixels.
        height: The height of the image, from 64 to 4096 pixels.

    Returns:
        A white image with a dark frame.

    Raises:
        Error: If there is no curve, the colors are not one for each
            curve, or a time, the top or a size is out of range.
    """
    if len(curves) == 0 or len(colors) != len(curves):
        raise Error("An epidemic plot needs one color for each of its curves")
    if width < 64 or width > 4096 or height < 64 or height > 4096:
        raise Error("An epidemic plot is from 64 to 4096 pixels on each side")
    var t = _require_period(end)
    var g = _require_period(grid)
    if t / g > 100.0:
        raise Error("An epidemic plot has at most 100 lines of time")
    if not (top > 0 and top <= 1):
        raise Error("The top of an epidemic plot must be in (0, 1]")
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
        for k in range(1, len(curve.times)):
            draw_line(
                image,
                Int(floor(curve.times[k - 1].to(DAY64) / t * right + 0.5)),
                Int(
                    floor((1.0 - curve.infectious[k - 1] / top) * bottom + 0.5)
                ),
                Int(floor(curve.times[k].to(DAY64) / t * right + 0.5)),
                Int(floor((1.0 - curve.infectious[k] / top) * bottom + 0.5)),
                colors[c],
            )
    return image^
