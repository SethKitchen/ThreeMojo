# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Parametric survival: exponential and Weibull models of censored times.

A Weibull model has the survival `S(t) = exp(-(t / lambda)^rho)`, with the
scale lambda and the shape rho. The hazard rises with time when rho is
above 1, stays the same when rho is 1, and falls when rho is below 1. The
exponential model is the Weibull model with rho held at 1.

- `fit_exponential(times, events)` gives the scale `sum t / d` of the
  times t and the d events, with the standard error `lambda / sqrt(d)`.
- `fit_weibull(times, events)` gives the maximum likelihood scale and
  shape. The shape is the root of its profile score, which falls as the
  shape rises, so a bisection finds it to the last place. The variances
  are the inverse of the observed information.
- `constant_hazard_test(times, events)` tests a shape of 1 by the
  likelihood ratio of the two models.
- `draw_fit(image, fit, color, top)` draws the survival of a model as a
  dashed line on a plot from `survival_image`.

A model gives the survival, the cumulative hazard and the hazard at any
time, and the time at any survival, such as the median. A fit extends
past the last time that a group has, but the model alone holds it there.
"""

from extensions.numerics.elementary import LN2, precise_exp, precise_power
from extensions.clinical.survival import require_group
from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from render.framebuffer import Framebuffer
from std.math import floor, isfinite, log, sqrt
from units.quantity import Unit
from units.si import PER_SECOND, SECOND, Duration64, DurationUnit64, Frequency64
from extensions.numerics.distributions import Z95, chi_square_p_value
from extensions.numerics.search import bisect


# The bisections of the Weibull shape, and the dash of a drawn model.
comptime _BISECTIONS = 120
comptime _DASH = 6


struct ParametricFit(Copyable, Movable):
    """An exponential or a Weibull model fitted to censored times."""

    var scale: Duration64
    """The scale lambda: the time at which `1 - 1/e`, or 63 percent, of a
    group has had the event."""
    var shape: Float64
    """The shape rho. 1 for an exponential model."""
    var scale_error: Duration64
    """The standard error of the scale."""
    var shape_error: Float64
    """The standard error of the shape. 0 for an exponential model."""
    var covariance: Duration64
    """The covariance of the scale and the shape. 0 for an exponential
    model."""
    var events: Int
    """The events of the group."""
    var parameters: Int
    """The parameters of the model: 1 for an exponential model and 2 for a
    Weibull model."""
    var log_likelihood_in_seconds: Float64
    """The log-likelihood, with the times in seconds."""

    def __init__(
        out self,
        scale: Duration64,
        shape: Float64,
        scale_error: Duration64,
        shape_error: Float64,
        covariance: Duration64,
        events: Int,
        parameters: Int,
        log_likelihood_in_seconds: Float64,
    ):
        """Create a fit.

        Args:
            scale: The scale.
            shape: The shape.
            scale_error: The standard error of the scale.
            shape_error: The standard error of the shape.
            covariance: The covariance of the scale and the shape.
            events: The events of the group.
            parameters: The parameters of the model, 1 or 2.
            log_likelihood_in_seconds: The log-likelihood, with the times
                in seconds.
        """
        self.scale = scale
        self.shape = shape
        self.scale_error = scale_error
        self.shape_error = shape_error
        self.covariance = covariance
        self.events = events
        self.parameters = parameters
        self.log_likelihood_in_seconds = log_likelihood_in_seconds

    def _ratio(self, time: Duration64) raises -> Float64:
        """Return the time over the scale, refusing a time below 0 or not
        finite."""
        var t = time.to(SECOND)
        if not (t >= 0) or not isfinite(t):
            raise Error("The time of a survival model must be 0 or more")
        return t / self.scale.to(SECOND)

    def cumulative_hazard(self, time: Duration64) raises -> Float64:
        """Return the cumulative hazard at a time.

        Args:
            time: The time, 0 or more and finite.

        Returns:
            `(t / lambda)^rho`.

        Raises:
            Error: If the time is below 0 or not finite.
        """
        return precise_power(self._ratio(time), self.shape)

    def survival(self, time: Duration64) raises -> Float64:
        """Return the survival at a time.

        Args:
            time: The time, 0 or more and finite.

        Returns:
            `exp(-(t / lambda)^rho)`.

        Raises:
            Error: If the time is below 0 or not finite.
        """
        return precise_exp(-self.cumulative_hazard(time))

    def hazard(self, time: Duration64) raises -> Frequency64:
        """Return the hazard at a time: the events for each unit of time of
        those still free of the event.

        Args:
            time: The time, 0 or more and finite.

        Returns:
            `rho / lambda (t / lambda)^(rho - 1)`. At a time of 0, infinite
            for a shape below 1 and 0 for a shape above 1.

        Raises:
            Error: If the time is below 0 or not finite.
        """
        var x = self._ratio(time)
        var rate = (
            self.shape
            / self.scale.to(SECOND)
            * precise_power(x, self.shape - 1.0)
        )
        return Frequency64(rate, PER_SECOND)

    def survival_error(self, time: Duration64) raises -> Float64:
        """Return the standard error of the survival at a time, by the delta
        method, as lifelines gives it.

        Args:
            time: The time, 0 or more and finite.

        Returns:
            The square root of `g^T V g`, with g the gradient of the
            survival in the scale and the shape, and V their covariance.
            `S -+ 1.96` of it can fall outside 0 and 1;
            `survival_interval` cannot.

        Raises:
            Error: If the time is below 0 or not finite.
        """
        var x = self._ratio(time)
        var h = precise_power(x, self.shape)
        if h == 0:
            return 0.0
        var s = precise_exp(-h)
        var lam = self.scale.to(SECOND)
        var a = s * self.shape * h / lam
        var b = -s * h * log(x)
        return sqrt(self._quadratic(a, b))

    def _quadratic(self, a: Float64, b: Float64) -> Float64:
        """Return `g^T V g` for the gradient `(a, b)` in the scale in
        seconds and the shape."""
        var e = self.scale_error.to(SECOND)
        return (
            a * a * e * e
            + 2.0 * a * b * self.covariance.to(SECOND)
            + b * b * self.shape_error * self.shape_error
        )

    def survival_interval(
        self, time: Duration64
    ) raises -> Tuple[Float64, Float64]:
        """Return the 95 percent interval of the survival at a time.

        Args:
            time: The time, 0 or more and finite.

        Returns:
            The low and the high end, by the delta method on the log of the
            cumulative hazard. Both are in 0 to 1. Both are 1 at a time of
            0.

        Raises:
            Error: If the time is below 0 or not finite.
        """
        var x = self._ratio(time)
        var h = precise_power(x, self.shape)
        if h == 0:
            return (1.0, 1.0)
        var lam = self.scale.to(SECOND)
        var se = sqrt(self._quadratic(-self.shape / lam, log(x)))
        return (
            precise_exp(-h * precise_exp(Z95 * se)),
            precise_exp(-h * precise_exp(-Z95 * se)),
        )

    def quantile(self, survival: Float64) raises -> Duration64:
        """Return the time at which the survival falls to a value.

        Args:
            survival: The survival, above 0 and below 1. 0.5 gives the
                median.

        Returns:
            `lambda (-ln S)^(1 / rho)`.

        Raises:
            Error: If the survival is not above 0 and below 1.
        """
        var q = _quantile_log(survival)
        return Duration64(
            self.scale.to(SECOND) * precise_power(q, 1.0 / self.shape), SECOND
        )

    def median(self) -> Duration64:
        """Return the median time to the event.

        Returns:
            `lambda (ln 2)^(1 / rho)`.
        """
        return Duration64(
            self.scale.to(SECOND) * precise_power(LN2, 1.0 / self.shape), SECOND
        )

    def quantile_interval(
        self, survival: Float64
    ) raises -> Tuple[Duration64, Duration64]:
        """Return the 95 percent interval of the time at a survival.

        Args:
            survival: The survival, above 0 and below 1.

        Returns:
            The low and the high end, by the delta method on the log of the
            time.

        Raises:
            Error: If the survival is not above 0 and below 1.
        """
        var q = _quantile_log(survival)
        var t = self.quantile(survival).to(SECOND)
        var lam = self.scale.to(SECOND)
        var se = sqrt(
            self._quadratic(1.0 / lam, -log(q) / (self.shape * self.shape))
        )
        return (
            Duration64(t * precise_exp(-Z95 * se), SECOND),
            Duration64(t * precise_exp(Z95 * se), SECOND),
        )

    def log_likelihood(self, unit: DurationUnit64) -> Float64:
        """Return the log-likelihood, with the times in a unit.

        The densities of the events change with the unit of time, so the
        log-likelihood does too. A difference of two log-likelihoods of one
        group does not.

        Args:
            unit: The unit of time.

        Returns:
            The log-likelihood, as lifelines gives it for times in the
            unit.
        """
        var seconds = Duration64(1.0, unit).to(SECOND)
        return self.log_likelihood_in_seconds + Float64(self.events) * log(
            seconds
        )

    def aic(self, unit: DurationUnit64) -> Float64:
        """Return Akaike's information criterion, with the times in a unit.

        Args:
            unit: The unit of time.

        Returns:
            `2 k - 2 ln L` for the k parameters. The lower of two models of
            one group fits better.
        """
        return 2.0 * Float64(self.parameters) - 2.0 * self.log_likelihood(unit)


def _quantile_log(survival: Float64) raises -> Float64:
    """Return `-ln S`, refusing a survival not above 0 and below 1."""
    if not (survival > 0) or not (survival < 1):
        raise Error("A survival quantile needs a survival above 0, below 1")
    return -log(survival)


struct _Group(Movable):
    """The times of a group over the largest time, and its events."""

    var u: List[Float64]
    """Each positive time over the largest time."""
    var logs: List[Float64]
    """The log of each `u`."""
    var event: List[Bool]
    """Whether each patient of `u` had the event."""
    var top: Float64
    """The largest time, in seconds."""
    var events: Int
    """The events."""

    def __init__(out self, times: List[Duration64], events: List[Bool]) raises:
        """Check and keep a group. A patient censored at 0 adds nothing.

        Args:
            times: The time of each patient.
            events: Whether each patient had the event.

        Raises:
            Error: If the group is not valid, has no event, or has an event
                at 0.
        """
        self.u = List[Float64]()
        self.logs = List[Float64]()
        self.event = List[Bool]()
        self.top = 0.0
        self.events = 0
        require_group(times, events)
        for i in range(len(times)):  # pragma: no branch
            var t = times[i].to(SECOND)
            if events[i] and t == 0:
                raise Error("A parametric fit needs each event after 0")
            if events[i]:
                self.events += 1
            self.top = max(self.top, t)
        if self.events == 0:
            raise Error("A parametric fit needs one event or more")
        for i in range(len(times)):  # pragma: no branch
            var t = times[i].to(SECOND)
            if t > 0:
                self.u.append(t / self.top)
                self.logs.append(log(t / self.top))
                self.event.append(events[i])

    def score(self, rho: Float64) -> Float64:
        """Return the profile score of the Weibull shape, with the times in
        units of the largest time."""
        var a = 0.0
        var b = 0.0
        var c = 0.0
        for i in range(len(self.u)):  # pragma: no branch
            var w = precise_exp(rho * self.logs[i])
            a += w
            b += w * self.logs[i]
            if self.event[i]:
                c += self.logs[i]
        var d = Float64(self.events)
        return d / rho + c - d * b / a


def fit_exponential(
    times: List[Duration64], events: List[Bool]
) raises -> ParametricFit:
    """Fit an exponential model to censored times.

    Args:
        times: The time of each patient, to the event or to the censoring.
        events: Whether each patient had the event.

    Returns:
        The scale `sum t / d`, the mean time to the event, with the
        standard error `lambda / sqrt(d)`, and a shape of 1.

    Raises:
        Error: If there is no patient, the lists differ in length, a time
            is below 0 or not finite, there is no event, or an event is at
            0.
    """
    var group = _Group(times, events)
    var total = 0.0
    for u in group.u:  # pragma: no branch
        total += u
    var d = Float64(group.events)
    var mu = total / d
    var lam = mu * group.top
    var ll = -d * log(mu) - d - d * log(group.top)
    return ParametricFit(
        Duration64(lam, SECOND),
        1.0,
        Duration64(lam / sqrt(d), SECOND),
        0.0,
        Duration64(0.0, SECOND),
        group.events,
        1,
        ll,
    )


def fit_weibull(
    times: List[Duration64], events: List[Bool]
) raises -> ParametricFit:
    """Fit a Weibull model to censored times by maximum likelihood.

    Args:
        times: The time of each patient, to the event or to the censoring.
        events: Whether each patient had the event.

    Returns:
        The scale and the shape, their standard errors and covariance from
        the inverse of the observed information, and the log-likelihood.

    Raises:
        Error: If there is no patient, the lists differ in length, a time
            is below 0 or not finite, there is no event, an event is at 0,
            or no event is before the largest time. The shape has no
            finite estimate then.
    """
    var group = _Group(times, events)
    var early = False
    for i in range(len(group.u)):  # pragma: no branch
        if group.event[i] and group.u[i] < 1:
            early = True
    if not early:
        raise Error("A Weibull fit needs an event before the largest time")
    var low = 1.0
    var high = 1.0
    while group.score(high) > 0:
        low = high
        high *= 2.0
    while not (group.score(low) > 0):
        high = low
        low /= 2.0

    def rising(shape: Float64) raises capturing -> Bool:
        return group.score(shape) > 0

    var rho = bisect[rising](low, high, _BISECTIONS)
    var d = Float64(group.events)
    var sum = 0.0
    var event_logs = 0.0
    for i in range(len(group.u)):  # pragma: no branch
        sum += precise_exp(rho * group.logs[i])
        if group.event[i]:
            event_logs += group.logs[i]
    var ln_mu = log(sum / d) / rho
    var mu = precise_exp(ln_mu)
    # The observed information in the scale over the largest time and the
    # shape, with the sum of the w = (u / mu)^rho at d.
    var wl = 0.0
    var wll = 0.0
    for i in range(len(group.u)):  # pragma: no branch
        var l = group.logs[i] - ln_mu
        var w = precise_exp(rho * l)
        wl += w * l
        wll += w * l * l
    var i11 = rho * rho * d / (mu * mu)
    var i12 = -rho * wl / mu
    var i22 = d / (rho * rho) + wll
    var det = i11 * i22 - i12 * i12
    var top = group.top
    var ll = (
        d * log(rho)
        - d * rho * ln_mu
        + (rho - 1.0) * event_logs
        - d
        - d * log(top)
    )
    return ParametricFit(
        Duration64(mu * top, SECOND),
        rho,
        Duration64(sqrt(i22 / det) * top, SECOND),
        sqrt(i11 / det),
        Duration64(-i12 / det * top, SECOND),
        group.events,
        2,
        ll,
    )


def constant_hazard_test(
    times: List[Duration64], events: List[Bool]
) raises -> Tuple[Float64, Float64]:
    """Test whether a group has a constant hazard: a Weibull shape of 1.

    Args:
        times: The time of each patient, to the event or to the censoring.
        events: Whether each patient had the event.

    Returns:
        The likelihood ratio statistic, twice the log-likelihood of the
        Weibull fit less that of the exponential fit, and its p value on
        one degree of freedom.

    Raises:
        Error: If the group cannot have a Weibull fit.
    """
    var weibull = fit_weibull(times, events)
    var exponential = fit_exponential(times, events)
    var statistic = max(
        2.0
        * (
            weibull.log_likelihood_in_seconds
            - exponential.log_likelihood_in_seconds
        ),
        0.0,
    )
    return (statistic, chi_square_p_value(statistic, 1))


def draw_fit(
    mut image: Framebuffer, fit: ParametricFit, color: Rgba, top: Duration64
) raises:
    """Draw the survival of a model as a dashed line on a survival plot.

    The time runs from 0 at the left edge to `top` at the right edge, and
    the survival from 0 at the bottom edge to 1 at the top edge, as in
    `survival_image`.

    Args:
        image: The plot.
        fit: The model.
        color: The color of the line.
        top: The time at the right edge. Positive and finite.

    Raises:
        Error: If the top time is not positive and finite.
    """
    var t = top.to(SECOND)
    if not (t > 0) or not isfinite(t):
        raise Error("The top time of a survival plot must be positive")
    var right = Float64(image.width - 1)
    var bottom = Float64(image.height - 1)
    var y0 = 0
    for x in range(1, image.width):  # pragma: no branch
        var s = fit.survival(Duration64(Float64(x) / right * t, SECOND))
        var y = Int(floor((1.0 - s) * bottom + 0.5))
        if (x // _DASH) % 2 == 0:
            draw_line(image, x - 1, y0, x, y, color)
        y0 = y
