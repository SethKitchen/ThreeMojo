# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The growth of an epidemic from its case counts, and its reproduction
number.

Early in an epidemic, the cases grow by a fixed fraction each day: the
count at time `t` is about `exp(a + r t)`, with `r` the growth rate.

- `growth_rate(counts, step, tolerance, max_steps)` fits `a` and `r` by
  Poisson regression of the counts on the time, by iteratively reweighted
  least squares from `mu = y + 0.5`, as statsmodels starts. It gives the
  standard errors, the Pearson dispersion and the deviance.
- `GrowthFit.doubling_time` gives `ln 2 / r`.
- `reproduction_number(rate, latent, infectious)` gives the reproduction
  number of an SEIR epidemic with that growth rate,
  `R = (1 + r L)(1 + r D)`, after Wallinga and Lipsitch (2007). A latent
  period of 0 gives the SIR model, `R = 1 + r D`.
- `incidence_image` draws the counts as bars with the fitted curve.

A dispersion above 1 means more spread than Poisson counts have, as real
counts often show. Then multiply the standard errors by its square root.
"""

from extensions.numerics.elementary import precise_exp
from extensions.clinical.survival import DAY64, Z95
from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from render.framebuffer import Color, Framebuffer
from std.math import floor, isfinite, log, sqrt
from units.quantity import Unit
from units.si import Duration64, Frequency64

# A rate per day, for 64-bit rates.
comptime PER_DAY64 = Unit[0, 0, -1, 0, 0, DType.float64](1.0 / 86400.0, "1/d")
# The most counts of one fit.
comptime MAX_COUNTS = 100000


struct GrowthFit(Copyable, Movable):
    """The exponential growth of a series of case counts."""

    var intercept: Float64
    """The log of the expected count at time 0."""
    var rate: Frequency64
    """The growth rate `r`."""
    var intercept_error: Float64
    """The standard error of the intercept."""
    var rate_error: Frequency64
    """The standard error of the growth rate."""
    var dispersion: Float64
    """Pearson's chi-square over its degrees of freedom. About 1 for
    Poisson counts."""
    var deviance: Float64
    """The Poisson deviance of the fit."""
    var steps: Int
    """The steps of the fit."""
    var converged: Bool
    """Whether the last step was below the tolerance."""

    def __init__(out self):
        """Create an empty fit."""
        self.intercept = 0.0
        self.rate = Frequency64(0, PER_DAY64)
        self.intercept_error = 0.0
        self.rate_error = Frequency64(0, PER_DAY64)
        self.dispersion = 0.0
        self.deviance = 0.0
        self.steps = 0
        self.converged = False

    def rate_interval(self) -> Tuple[Frequency64, Frequency64]:
        """Return the 95 percent interval of the growth rate.

        Returns:
            The rate `-+ 1.96 se`, by the Poisson standard error.
        """
        var r = self.rate.to(PER_DAY64)
        var half = Z95 * self.rate_error.to(PER_DAY64)
        return (
            Frequency64(r - half, PER_DAY64),
            Frequency64(r + half, PER_DAY64),
        )

    def doubling_time(self) raises -> Duration64:
        """Return the time in which the counts double.

        Returns:
            `ln 2 / r`.

        Raises:
            Error: If the counts do not grow.
        """
        var r = self.rate.to(PER_DAY64)
        if not (r > 0):
            raise Error("Counts that do not grow have no doubling time")
        return Duration64(log(2.0) / r, DAY64)

    def expected(self, time: Duration64) -> Float64:
        """Return the fitted count at a time.

        Args:
            time: The time, from the first count.

        Returns:
            `exp(a + r t)`.
        """
        return precise_exp(
            self.intercept + self.rate.to(PER_DAY64) * time.to(DAY64)
        )


def _require_series(counts: List[Int], step: Duration64) raises -> Float64:
    """Return the step in days, or refuse a series out of range."""
    if len(counts) < 3 or len(counts) > MAX_COUNTS:
        raise Error("A growth fit needs 3 to 100000 counts")
    var total = 0
    for c in counts:  # pragma: no branch
        if c < 0:
            raise Error("A case count must be 0 or more")
        total += c
    if total == 0:
        raise Error("A growth fit needs one case or more")
    var days = step.to(DAY64)
    if not (days > 0) or not isfinite(days):
        raise Error("The step between counts must be positive and finite")
    return days


def growth_rate(
    counts: List[Int], step: Duration64, tolerance: Float64, max_steps: Int
) raises -> GrowthFit:
    """Fit the exponential growth of a series of case counts.

    Args:
        counts: The cases in each interval, in order. 3 or more, at least
            one case in all.
        step: The time between two counts, such as a day.
        tolerance: The largest change of a coefficient at the last step.
            Between 0 and 1.
        max_steps: The most steps, from 1 to 1000.

    Returns:
        The intercept and the growth rate with their standard errors, the
        dispersion and the deviance.

    Raises:
        Error: If the counts, the step, the tolerance or the steps are out
            of range.
    """
    var h = _require_series(counts, step)
    if not (tolerance > 0 and tolerance < 1):
        raise Error("The tolerance of a growth fit must be between 0 and 1")
    if max_steps < 1 or max_steps > 1000:
        raise Error("A growth fit takes from 1 to 1000 steps")
    var n = len(counts)
    var mu = List[Float64]()
    for c in counts:  # pragma: no branch
        mu.append(Float64(c) + 0.5)
    var out = GrowthFit()
    var a = 0.0
    var r = 0.0
    while out.steps < max_steps:
        # Weighted least squares of the working response on (1, t).
        var s00 = 0.0
        var s01 = 0.0
        var s11 = 0.0
        var b0 = 0.0
        var b1 = 0.0
        for i in range(n):  # pragma: no branch
            var t = Float64(i) * h
            var w = mu[i]
            var z = log(mu[i]) + (Float64(counts[i]) - mu[i]) / mu[i]
            s00 += w
            s01 += w * t
            s11 += w * t * t
            b0 += w * z
            b1 += w * t * z
        var det = s00 * s11 - s01 * s01
        var next_a = (s11 * b0 - s01 * b1) / det
        var next_r = (s00 * b1 - s01 * b0) / det
        var change = max(abs(next_a - a), abs(next_r - r))
        a = next_a
        r = next_r
        out.steps += 1
        for i in range(n):  # pragma: no branch
            mu[i] = precise_exp(a + r * Float64(i) * h)
        if out.steps > 1 and change < tolerance:
            out.converged = True
            break
    # The information at the last fit.
    var s00 = 0.0
    var s01 = 0.0
    var s11 = 0.0
    var pearson = 0.0
    var deviance = 0.0
    for i in range(n):  # pragma: no branch
        var t = Float64(i) * h
        var y = Float64(counts[i])
        s00 += mu[i]
        s01 += mu[i] * t
        s11 += mu[i] * t * t
        pearson += (y - mu[i]) * (y - mu[i]) / mu[i]
        deviance -= y - mu[i]
        if counts[i] > 0:
            deviance += y * log(y / mu[i])
    var det = s00 * s11 - s01 * s01
    out.intercept = a
    out.rate = Frequency64(r, PER_DAY64)
    out.intercept_error = sqrt(s11 / det)
    out.rate_error = Frequency64(sqrt(s00 / det), PER_DAY64)
    out.dispersion = pearson / Float64(n - 2)
    out.deviance = 2.0 * deviance
    return out^


def reproduction_number(
    rate: Frequency64, latent: Duration64, infectious: Duration64
) raises -> Float64:
    """Return the reproduction number that a growth rate implies.

    Args:
        rate: The growth rate of the cases.
        latent: The mean latent period. 0 for an SIR epidemic.
        infectious: The mean infectious period. Positive.

    Returns:
        `(1 + r L)(1 + r D)`, for exponential latent and infectious
        stages.

    Raises:
        Error: If a period is out of range, or the rate is so negative
            that a factor is not positive.
    """
    var r = rate.to(PER_DAY64)
    var l = latent.to(DAY64)
    var d = infectious.to(DAY64)
    if not isfinite(r):
        raise Error("A growth rate must be finite")
    if not (l >= 0) or not isfinite(l) or not (d > 0) or not isfinite(d):
        raise Error(
            "The latent period must be 0 or more and the infectious"
            " period positive, both finite"
        )
    var first = 1.0 + r * l
    var second = 1.0 + r * d
    if not (first > 0 and second > 0):
        raise Error("A growth rate this negative has no reproduction number")
    return first * second


def incidence_image(
    counts: List[Int],
    step: Duration64,
    fit: GrowthFit,
    width: Int,
    height: Int,
) raises -> Framebuffer:
    """Draw case counts as bars, with the fitted growth as a curve.

    Each count is a light blue bar of an equal width, from left to right.
    The red curve is the fitted count at the middle of each bar. The
    counts run from 0 at the bottom edge to 1.1 times the largest count
    or fitted count at the top edge.

    Args:
        counts: The cases in each interval.
        step: The time between two counts.
        fit: The growth of the counts, from `growth_rate`.
        width: The width of the image, from 64 to 4096 pixels.
        height: The height of the image, from 64 to 4096 pixels.

    Returns:
        A white image with a dark frame.

    Raises:
        Error: If the counts or the step are out of range, or a size is.
    """
    var h = _require_series(counts, step)
    if width < 64 or width > 4096 or height < 64 or height > 4096:
        raise Error("An incidence plot is from 64 to 4096 pixels a side")
    var n = len(counts)
    var top = 0.0
    for i in range(n):  # pragma: no branch
        top = max(top, Float64(counts[i]))
        top = max(top, fit.expected(Duration64(Float64(i) * h, DAY64)))
    top *= 1.1
    var image = Framebuffer(width, height, Color(255, 255, 255))
    var bottom = Float64(height - 1)
    var bar = Rgba(0.55, 0.7, 0.9, 1)
    var previous_x = -1
    var previous_y = -1
    for i in range(n):  # pragma: no branch
        var left = Int(floor(Float64(i) / Float64(n) * Float64(width)))
        var right = Int(floor(Float64(i + 1) / Float64(n) * Float64(width))) - 2
        var y = Int(floor((1.0 - Float64(counts[i]) / top) * bottom + 0.5))
        for x in range(left + 1, max(left + 2, right)):  # pragma: no branch
            draw_line(image, x, y, x, height - 1, bar)
        var middle = (left + right + 1) // 2
        var curve_y = Int(
            floor(
                (1.0 - fit.expected(Duration64(Float64(i) * h, DAY64)) / top)
                * bottom
                + 0.5
            )
        )
        if previous_x >= 0:
            draw_line(
                image,
                previous_x,
                previous_y,
                middle,
                curve_y,
                Rgba(0.85, 0.2, 0.2, 1),
            )
        previous_x = middle
        previous_y = curve_y
    var dark = Rgba(0.24, 0.24, 0.26, 1)
    draw_line(image, 0, 0, width - 1, 0, dark)
    draw_line(image, 0, height - 1, width - 1, height - 1, dark)
    draw_line(image, 0, 0, 0, height - 1, dark)
    draw_line(image, width - 1, 0, width - 1, height - 1, dark)
    return image^
