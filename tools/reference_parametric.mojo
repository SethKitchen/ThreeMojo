# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent exponential and Weibull fits of censored times, at about 32
digits; no ThreeMojo library imports.

    mojo run -I . tools/make_parametric.mojo
    mojo run -I . tools/reference_parametric.mojo
    cd assets/parametric && python3 make_parametric.py

reads the groups of `assets/parametric/parametric_data.txt` and writes
`assets/parametric/parametric_expected.txt`. The script then writes the
fits of lifelines and the p values of scipy. The arithmetic is
double-double, from `tools/_double_double.mojo`, and each time is read
as its exact decimal.

For each group, the file holds:

- `exponential`: the scale `sum t / d`, its error `scale / sqrt(d)` and
  the log-likelihood;
- `weibull`: the scale and the shape, their errors and covariance from
  the inverse of the information, and the log-likelihood. The shape is the
  root of the profile score `d / rho + sum ln t - d B / A`, with
  `A = sum t^rho` and `B = sum t^rho ln t`, by Newton steps;
- `test`: the likelihood ratio statistic of the Weibull model against the
  exponential;
- `median` and `quantile`: the time at a survival of 0.5 and of 0.2, with
  the ends of its 95 percent interval on the log scale;
- `at`: at each probe time, the survival, its error, the ends of its 95
  percent interval on the log of the cumulative hazard, and the hazard.

The errors are those of the delta method, as in lifelines.
"""

from tools._double_double import (
    DD,
    dd,
    dd_exp,
    dd_inverse,
    dd_log,
    dd_normal_quantile,
    dd_parse,
    dd_pow,
    dd_sqrt,
)
from tools._python_float import python_repr

comptime DATA = "assets/parametric/parametric_data.txt"
comptime EXPECTED = "assets/parametric/parametric_expected.txt"


def probes(name: String) raises -> List[String]:
    """Return the probe times of a group, as decimal text.

    Args:
        name: The group: `drug`, `placebo`, `rising` or `falling`.

    Returns:
        Four times, in the unit of the group.

    Raises:
        Error: If the group is not one of the four.
    """
    if name == "drug":
        return ["5", "10", "20", "40"]
    if name == "placebo":
        return ["1", "5", "10", "20"]
    if name == "rising":
        return ["0.5", "5", "10", "30"]
    if name == "falling":
        return ["0.1", "2", "10", "40"]
    raise Error("The parametric reference has no group " + name)


struct _Weibull(Movable):
    """A Weibull fit: the scale, the shape, the inverse of the information
    in (scale, shape), and the log-likelihood."""

    var scale: DD
    var shape: DD
    var variance: List[List[DD]]
    var log_likelihood: DD

    def __init__(
        out self,
        scale: DD,
        shape: DD,
        var variance: List[List[DD]],
        log_likelihood: DD,
    ):
        self.scale = scale
        self.shape = shape
        self.variance = variance^
        self.log_likelihood = log_likelihood


def _weibull(times: List[DD], events: List[Bool]) raises -> _Weibull:
    """Fit a Weibull model by Newton steps on the profile score of the
    shape."""
    var d = 0.0
    var logs = dd(0.0)
    var ln = List[DD]()
    for i in range(len(times)):
        ln.append(dd_log(times[i]))
        if events[i]:
            d += 1.0
            logs = logs + ln[i]
    var rho = dd(1.0)
    for _ in range(100):
        var a = dd(0.0)
        var b = dd(0.0)
        var c = dd(0.0)
        for i in range(len(times)):
            var power = dd_exp(rho * ln[i])
            a = a + power
            b = b + power * ln[i]
            c = c + power * ln[i] * ln[i]
        var score = d / rho + logs - b * d / a
        var slope = -(d / (rho * rho)) - (c / a - (b / a) * (b / a)) * d
        var step = score / slope
        var next = rho - step
        while next.hi <= 0.0:
            step = step * 0.5
            next = rho - step
        rho = next
        if abs(step.hi) <= 1e-31 * abs(rho.hi):
            break
    var total = dd(0.0)
    for i in range(len(times)):
        total = total + dd_exp(rho * ln[i])
    var scale = dd_pow(total / d, 1.0 / rho)
    var weighted = dd(0.0)
    var squared = dd(0.0)
    var weights = dd(0.0)
    var event_logs = dd(0.0)
    for i in range(len(times)):
        var z = ln[i] - dd_log(scale)
        var w = dd_exp(rho * z)
        weights = weights + w
        weighted = weighted + w * z
        squared = squared + w * z * z
        if events[i]:
            event_logs = event_logs + z
    var cross = -(rho * weighted) / scale
    var information: List[List[DD]] = [
        [rho * rho * d / (scale * scale), cross],
        [cross, d / (rho * rho) + squared],
    ]
    var ll = (
        dd_log(rho) * d - dd_log(scale) * d + (rho - 1.0) * event_logs - weights
    )
    return _Weibull(scale, rho, dd_inverse(information), ll)


def _form(v: List[List[DD]], g0: DD, g1: DD) -> DD:
    """Return `g^T V g` of a gradient in (scale, shape)."""
    return g0 * g0 * v[0][0] + g0 * g1 * v[0][1] * 2.0 + g1 * g1 * v[1][1]


def _words(values: List[DD]) raises -> String:
    """Return the doubles nearest the values, as Python prints them."""
    var out = String()
    for i in range(len(values)):
        if i > 0:
            out += " "
        out += python_repr(values[i].to_float())
    return out


def _quantile(fit: _Weibull, p: String, z: DD) raises -> List[DD]:
    """Return the time at a survival of p and the ends of its interval."""
    var q = dd_log(1.0 / dd_parse(p))
    var t = fit.scale * dd_pow(q, 1.0 / fit.shape)
    var se = dd_sqrt(
        _form(
            fit.variance,
            1.0 / fit.scale,
            -dd_log(q) / (fit.shape * fit.shape),
        )
    )
    return [t, t * dd_exp(-(z * se)), t * dd_exp(z * se)]


def _at(fit: _Weibull, t: DD, z: DD) raises -> List[DD]:
    """Return the survival at t, its error, its interval and the hazard."""
    var rho = fit.shape
    var scale = fit.scale
    var ln = dd_log(t / scale)
    var h = dd_exp(rho * ln)
    var s = dd_exp(-h)
    var se_s = dd_sqrt(_form(fit.variance, s * rho * h / scale, -(s * h * ln)))
    var se_l = dd_sqrt(_form(fit.variance, -(rho / scale), ln))
    var lower = dd_exp(-(h * dd_exp(z * se_l)))
    var upper = dd_exp(-(h * dd_exp(-(z * se_l))))
    var hazard = rho / scale * dd_exp((rho - 1.0) * ln)
    return [t, s, se_s, lower, upper, hazard]


def reference(data: String) raises -> String:
    """Return the expected file for the groups of a data file.

    Args:
        data: The text of `parametric_data.txt`: one group to a line, its
            name, its unit and its times, with `+` after a censored one.

    Returns:
        The text of `parametric_expected.txt`.

    Raises:
        Error: If a line has no times, a time is not a decimal, or a group
            has no event or is not one of the four.
    """
    var z = dd_normal_quantile(dd_parse("0.975"))
    var out = String()
    for line in data.splitlines():
        var words = String(line).split(" ")
        if len(words) < 3:
            raise Error("A parametric group needs a name, a unit and times")
        var name = String(words[0])
        var times = List[DD]()
        var events = List[Bool]()
        var total = dd(0.0)
        var d = 0.0
        for at in range(2, len(words)):
            var word = String(words[at])
            var censored = word.endswith("+")
            var time = dd_parse(String(word.removesuffix("+")))
            times.append(time)
            events.append(not censored)
            total = total + time
            if not censored:
                d += 1.0
        if d == 0.0:
            raise Error("A parametric group needs an event")
        var scale = total / d
        var exponential: List[DD] = [
            scale,
            scale / dd_sqrt(dd(d)),
            -(dd_log(scale) * d) - total / scale,
        ]
        var fit = _weibull(times, events)
        var weibull: List[DD] = [
            fit.scale,
            fit.shape,
            dd_sqrt(fit.variance[0][0]),
            dd_sqrt(fit.variance[1][1]),
            fit.variance[0][1],
            fit.log_likelihood,
        ]
        var statistic: List[DD] = [(fit.log_likelihood - exponential[2]) * 2.0]
        out += name + " exponential " + _words(exponential) + "\n"
        out += name + " weibull " + _words(weibull) + "\n"
        out += name + " test " + _words(statistic) + "\n"
        out += name + " median " + _words(_quantile(fit, "0.5", z)) + "\n"
        out += name + " quantile " + _words(_quantile(fit, "0.2", z)) + "\n"
        for probe in probes(name):
            out += name + " at " + _words(_at(fit, dd_parse(probe), z)) + "\n"
    return out^


def main() raises:
    var text = reference(open(DATA, "r").read())
    with open(EXPECTED, "w") as out:
        out.write(text)
