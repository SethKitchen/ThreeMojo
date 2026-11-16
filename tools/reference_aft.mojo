# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent Weibull accelerated failure time fits, at about 32 digits;
no ThreeMojo library imports.

    mojo run -I . tools/make_aft.mojo
    mojo run -I . tools/reference_aft.mojo
    cd assets/aft && python3 make_aft.py

reads the groups of `assets/aft/aft_cohort.txt` and writes
`assets/aft/aft_expected.txt`. The script then writes the fits of lifelines
and the p values of scipy. The arithmetic is double-double, from
`tools/_double_double.mojo`.

The model is `log T = b . x + W / rho`, with x the covariates after a 1
for the intercept. Newton steps solve the score equations in `(g, rho)`,
with `g = -rho b`, where the log-likelihood is concave. They start from
the exponential fit, and a step that lowers the log-likelihood is halved.
The variance of `(b, ln rho)` is `J (-H)^-1 J^T`, with H the Hessian in
`(g, rho)` and J the Jacobian of the change of variables.

For each group, the file holds:

- `coefficients`: the intercept, the covariates, then `ln rho`;
- `errors`: their standard errors;
- `fit`: rho, the log-likelihood in the unit of the group, and the
  likelihood ratio statistic against the model without covariates;
- `median`: for the first, middle and last patient, the covariates, the
  median time, the median of all times, and the survival there.
"""

from tools._double_double import (
    DD,
    dd,
    dd_exp,
    dd_inverse,
    dd_log,
    dd_solve,
    dd_sqrt,
)
from tools._python_float import python_repr

comptime DATA = "assets/aft/aft_cohort.txt"
comptime EXPECTED = "assets/aft/aft_expected.txt"


def groups() -> List[String]:
    """Return the names of the groups, in the order of the file.

    Returns:
        `trial`, `cohort`, `spread` and `tiny`.
    """
    return ["trial", "cohort", "spread", "tiny"]


struct Fit(Movable):
    """A Weibull AFT fit at double-double precision."""

    var coefficients: List[DD]
    """The intercept and the coefficients: b."""
    var shape: DD
    """The shape: rho."""
    var variance: List[List[DD]]
    """The covariance of `(b, ln rho)`."""
    var log_likelihood: DD
    """The log-likelihood, in the unit of the times."""

    def __init__(
        out self,
        var coefficients: List[DD],
        shape: DD,
        var variance: List[List[DD]],
        log_likelihood: DD,
    ):
        """Hold a fit.

        Args:
            coefficients: The intercept and the coefficients.
            shape: The shape.
            variance: The covariance of `(b, ln rho)`.
            log_likelihood: The log-likelihood.
        """
        self.coefficients = coefficients^
        self.shape = shape
        self.variance = variance^
        self.log_likelihood = log_likelihood


def _linear(rows: List[List[Float64]], i: Int, g: List[DD]) -> DD:
    """Return `x_i . g`, with the 1 of the intercept first."""
    var total = g[0]
    for j in range(len(rows[i])):
        total = total + g[j + 1] * rows[i][j]
    return total


def _log_likelihood(
    ln: List[DD],
    events: List[Bool],
    rows: List[List[Float64]],
    g: List[DD],
    r: DD,
) raises -> DD:
    """Return the log-likelihood at `(g, rho)`."""
    var total = dd(0.0)
    var log_r = dd_log(r)
    for i in range(len(ln)):
        var linear = _linear(rows, i, g)
        if events[i]:
            total = total + log_r + (r - 1.0) * ln[i] + linear
        total = total - dd_exp(r * ln[i] + linear)
    return total


def _hessian(
    ln: List[DD],
    rows: List[List[Float64]],
    g: List[DD],
    r: DD,
    d: Float64,
) raises -> List[List[DD]]:
    """Return the Hessian of the log-likelihood in `(g, rho)`."""
    var k = len(g)
    var h = List[List[DD]]()
    for _ in range(k + 1):
        h.append(List[DD](length=k + 1, fill=dd(0.0)))
    h[k][k] = -(d / (r * r))
    for i in range(len(ln)):
        var w = dd_exp(r * ln[i] + _linear(rows, i, g))
        var x = List[Float64]()
        x.append(1.0)
        for value in rows[i]:
            x.append(value)
        for a in range(k):
            for c in range(k):
                h[a][c] = h[a][c] - w * (x[a] * x[c])
            h[a][k] = h[a][k] - w * ln[i] * x[a]
        h[k][k] = h[k][k] - w * ln[i] * ln[i]
    for a in range(k):
        h[k][a] = h[a][k]
    return h^


def fit(
    times: List[Float64],
    events: List[Bool],
    rows: List[List[Float64]],
) raises -> Fit:
    """Fit a Weibull AFT model by Newton steps in `(g, rho)`.

    Args:
        times: The times, each above 0.
        events: True for an event, False for a censored time.
        rows: The covariates of each patient, without the 1 of the
            intercept. Each row has the same length.

    Returns:
        The fit.

    Raises:
        Error: If there is no event, or the steps do not converge in 200.
    """
    var ln = List[DD]()
    var d = 0.0
    var total = dd(0.0)
    for i in range(len(times)):
        ln.append(dd_log(dd(times[i])))
        total = total + times[i]
        if events[i]:
            d += 1.0
    if d == 0.0:
        raise Error("An AFT reference needs an event")
    var k = 1 + (len(rows[0]) if len(rows) > 0 else 0)
    var g = List[DD](length=k, fill=dd(0.0))
    g[0] = -dd_log(total / d)
    var r = dd(1.0)
    var ll = _log_likelihood(ln, events, rows, g, r)
    var converged = False
    for _ in range(200):
        var score = List[DD](length=k + 1, fill=dd(0.0))
        score[k] = d / r
        for i in range(len(ln)):
            var linear = _linear(rows, i, g)
            var w = dd_exp(r * ln[i] + linear)
            var residual = -w
            if events[i]:
                residual = residual + 1.0
                score[k] = score[k] + ln[i]
            score[k] = score[k] - w * ln[i]
            score[0] = score[0] + residual
            for j in range(len(rows[i])):
                score[j + 1] = score[j + 1] + residual * rows[i][j]
        var negative = List[DD]()
        for value in score:
            negative.append(-value)
        var step = dd_solve(_hessian(ln, rows, g, r, d), negative^)
        var size = 1.0
        while True:
            var trial_g = List[DD]()
            for j in range(k):
                trial_g.append(g[j] + step[j] * size)
            var trial_r = r + step[k] * size
            if trial_r.hi > 0.0:
                var trial_ll = _log_likelihood(
                    ln, events, rows, trial_g, trial_r
                )
                if not (trial_ll < ll) or size < 1e-20:
                    g = trial_g^
                    r = trial_r
                    ll = trial_ll
                    break
            size *= 0.5
        var largest = 0.0
        for j in range(k + 1):
            largest = max(largest, abs(step[j].hi) * size)
        if largest <= 1e-30:
            converged = True
            break
    if not converged:
        raise Error("An AFT reference did not converge in 200 steps")
    var h = _hessian(ln, rows, g, r, d)
    var negative_h = List[List[DD]]()
    for row in h:
        var out = List[DD]()
        for value in row:
            out.append(-value)
        negative_h.append(out^)
    var inverse = dd_inverse(negative_h)
    # From (g, rho) to (b, ln rho): b = -g / rho.
    var jacobian = List[List[DD]]()
    for _ in range(k + 1):
        jacobian.append(List[DD](length=k + 1, fill=dd(0.0)))
    for a in range(k):
        jacobian[a][a] = -(1.0 / r)
        jacobian[a][k] = g[a] / (r * r)
    jacobian[k][k] = 1.0 / r
    var variance = List[List[DD]]()
    for a in range(k + 1):
        var row = List[DD]()
        for c in range(k + 1):
            var value = dd(0.0)
            for p in range(k + 1):
                for q in range(k + 1):
                    value = (
                        value + jacobian[a][p] * inverse[p][q] * jacobian[c][q]
                    )
            row.append(value)
        variance.append(row^)
    var b = List[DD]()
    for j in range(k):
        b.append(-(g[j] / r))
    return Fit(b^, r, variance^, ll)


def _words(values: List[DD]) raises -> String:
    """Return the doubles nearest the values, as Python prints them."""
    var out = String()
    for i in range(len(values)):
        if i > 0:
            out += " "
        out += python_repr(values[i].to_float())
    return out


def _median(values: List[Float64]) -> Float64:
    """Return the median of doubles, as numpy rounds it."""
    var sorted = values.copy()
    for i in range(1, len(sorted)):
        var j = i
        while j > 0 and sorted[j - 1] > sorted[j]:
            var held = sorted[j]
            sorted[j] = sorted[j - 1]
            sorted[j - 1] = held
            j -= 1
    var n = len(sorted)
    if n % 2 == 1:
        return sorted[n // 2]
    return (sorted[n // 2 - 1] + sorted[n // 2]) / 2.0


def reference(data: String) raises -> String:
    """Return the expected file for the groups of a cohort file.

    Args:
        data: The text of `aft_cohort.txt`: one patient to a line, the
            group, the time, 1 for an event or 0, and the covariates.

    Returns:
        The text of `aft_expected.txt`.

    Raises:
        Error: If a line is short, a group has no patient or no event, or
            a fit does not converge.
    """
    var out = String()
    for name in groups():
        var times = List[Float64]()
        var events = List[Bool]()
        var rows = List[List[Float64]]()
        for line in data.splitlines():
            var words = String(line).split(" ")
            if len(words) < 3:
                raise Error("An AFT patient needs a group, a time and an event")
            if String(words[0]) != name:
                continue
            times.append(atof(String(words[1])))
            events.append(atof(String(words[2])) == 1.0)
            var row = List[Float64]()
            for at in range(3, len(words)):
                row.append(atof(String(words[at])))
            rows.append(row^)
        if len(times) == 0:
            raise Error("An AFT reference has no patient in group " + name)
        var full = fit(times, events, rows)
        var empty = List[List[Float64]]()
        for _ in range(len(times)):
            empty.append(List[Float64]())
        var plain = fit(times, events, empty)
        var k = len(full.coefficients)
        var coefficients = full.coefficients.copy()
        coefficients.append(dd_log(full.shape))
        var errors = List[DD]()
        for a in range(k + 1):
            errors.append(dd_sqrt(full.variance[a][a]))
        var line: List[DD] = [
            full.shape,
            full.log_likelihood,
            (full.log_likelihood - plain.log_likelihood) * 2.0,
        ]
        out += name + " coefficients " + _words(coefficients) + "\n"
        out += name + " errors " + _words(errors) + "\n"
        out += name + " fit " + _words(line) + "\n"
        var at = _median(times)
        var n = len(rows)
        for index in [0, n // 2, n - 1]:
            ref row = rows[index]
            var linear = full.coefficients[0]
            var values = List[DD]()
            for j in range(len(row)):
                linear = linear + full.coefficients[j + 1] * row[j]
                values.append(dd(row[j]))
            var scale = dd_exp(linear)
            var median = scale * dd_exp(dd_log(dd_log(dd(2.0))) / full.shape)
            var survival = dd_exp(
                -dd_exp(full.shape * (dd_log(dd(at)) - linear))
            )
            values.append(median)
            values.append(dd(at))
            values.append(survival)
            out += name + " median " + _words(values) + "\n"
    return out^


def main() raises:
    var text = reference(open(DATA, "r").read())
    with open(EXPECTED, "w") as out:
        out.write(text)
