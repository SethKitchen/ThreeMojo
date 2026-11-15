# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Negative binomial regression of event rates, for counts that spread more
than Poisson counts.

Events such as asthma attacks or falls cluster in some patients. Then the
counts of a stratum spread more than a Poisson model allows, and the
standard errors of the Poisson model are too small. The negative binomial
model (NB2) takes the variance of a count as `mu + alpha mu^2`. With alpha
0, it is the Poisson model of `rates`.

`negative_binomial_regression(events, exposure, covariates)` fits the log
of the expected count, `log(T) + b0 + x . b`, and alpha by maximum
likelihood:

1. For each alpha, iteratively reweighted least squares gives the
   coefficients, with the weights `mu / (1 + alpha mu)`.
2. A golden-section search finds the alpha of the largest profile
   likelihood, on a log scale from 1e-8 to 1e4.
3. Three Newton steps on the coefficients and `log(alpha)` together polish
   the maximum. The standard errors come from the inverse of the observed
   information there, as statsmodels gives them.

The log-likelihood takes `lgamma(y + r) - lgamma(r)` and its derivatives,
with `r = 1 / alpha`, as finite sums over the count, so it needs no
digamma function.
"""

from extensions.numerics.elementary import precise_exp
from extensions.clinical.rates import RateModel, poisson_regression
from extensions.numerics.dense import (
    DenseMatrix,
    cholesky_inverse,
    cholesky_solve,
)
from std.math import lgamma, log, log1p, sqrt
from units.si import YEAR64, Duration64
from extensions.numerics.distributions import chi_square_p_value

# The ends of the search of log(alpha), and its steps.
comptime _LEAST_LOG_ALPHA = -18.420680743952367
comptime _MOST_LOG_ALPHA = 9.210340371976184
comptime _GOLDEN = 0.6180339887498949
comptime _SEARCH_STEPS = 90
comptime _POLISH_STEPS = 3


struct NegativeBinomialModel(Copyable, Movable):
    """A fitted negative binomial (NB2) model of event rates."""

    var rates: RateModel
    """The coefficients and their standard errors, with the rate ratios,
    intervals, tests and rates of `RateModel`. Its `deviance` is the
    negative binomial deviance, and its `dispersion` is Pearson's
    chi-square over its degrees of freedom."""
    var alpha: Float64
    """The dispersion: the variance of a count is `mu + alpha mu^2`."""
    var alpha_error: Float64
    """The standard error of alpha."""
    var log_likelihood: Float64
    """The log-likelihood of the model."""
    var poisson_log_likelihood: Float64
    """The log-likelihood of the Poisson model of the same strata."""

    def __init__(out self, var rates: RateModel):
        """Create a model.

        Args:
            rates: The coefficients and their errors.
        """
        self.rates = rates^
        self.alpha = 0.0
        self.alpha_error = 0.0
        self.log_likelihood = 0.0
        self.poisson_log_likelihood = 0.0

    def likelihood_ratio(self) -> Float64:
        """Return the likelihood ratio statistic against the Poisson model.

        Returns:
            `2 (l - l_poisson)`, 0 or more.
        """
        return max(
            2.0 * (self.log_likelihood - self.poisson_log_likelihood), 0.0
        )

    def p_value(self) raises -> Float64:
        """Return the p value of the test that alpha is 0.

        Alpha 0 is on the edge of its range, so the p value is half the
        tail of chi-square with 1 degree of freedom.

        Returns:
            The chance of a statistic this large when the counts are
            Poisson counts.

        Raises:
            Error: If the statistic is not a number.
        """
        return chi_square_p_value(self.likelihood_ratio(), 1) / 2.0


struct _Data(Movable):
    """The counts, the log person-times and the rows with a 1 first."""

    var y: List[Float64]
    var offset: List[Float64]
    var rows: List[List[Float64]]

    def __init__(
        out self,
        events: List[Int],
        exposure: List[Duration64],
        covariates: List[List[Float64]],
    ):
        self.y = List[Float64]()
        self.offset = List[Float64]()
        self.rows = List[List[Float64]]()
        for i in range(len(events)):  # pragma: no branch
            self.y.append(Float64(events[i]))
            self.offset.append(log(exposure[i].to(YEAR64)))
            var row = List[Float64]()
            row.append(1.0)
            for v in covariates[i]:  # pragma: no branch
                row.append(v)
            self.rows.append(row^)

    def means(self, beta: List[Float64]) -> List[Float64]:
        """Return the expected count of each stratum."""
        var out = List[Float64]()
        for i in range(len(self.y)):  # pragma: no branch
            var eta = self.offset[i]
            for a in range(len(beta)):  # pragma: no branch
                eta += self.rows[i][a] * beta[a]
            out.append(precise_exp(eta))
        return out^


def _log_likelihood(data: _Data, mu: List[Float64], r: Float64) -> Float64:
    """Return the NB2 log-likelihood with `r = 1 / alpha`."""
    var total = 0.0
    for i in range(len(data.y)):  # pragma: no branch
        var y = data.y[i]
        for j in range(Int(y)):
            total += log(r + Float64(j))
        total += -lgamma(y + 1.0) - r * log1p(mu[i] / r)
        total += y * (log(mu[i]) - log(r + mu[i]))
    return total


def _fit_beta(
    data: _Data, alpha: Float64, var beta: List[Float64]
) raises -> List[Float64]:
    """Return the coefficients of the largest likelihood at one alpha."""
    var p = len(beta)
    for _ in range(100):  # pragma: no branch
        var mu = data.means(beta)
        var gram = DenseMatrix(p, p)
        var right = List[Float64](length=p, fill=0.0)
        for i in range(len(data.y)):  # pragma: no branch
            var w = mu[i] / (1.0 + alpha * mu[i])
            var z = log(mu[i]) - data.offset[i] + (data.y[i] - mu[i]) / mu[i]
            for a in range(p):  # pragma: no branch
                right[a] += w * data.rows[i][a] * z
                for b in range(a + 1):  # pragma: no branch
                    gram.add(a, b, w * data.rows[i][a] * data.rows[i][b])
        var next = cholesky_solve(gram, right)
        var change = 0.0
        for a in range(p):  # pragma: no branch
            change = max(change, abs(next[a] - beta[a]))
        beta = next^
        if change < 1e-13:
            break
    return beta^


def _profile(
    data: _Data, log_alpha: Float64, mut beta: List[Float64]
) raises -> Float64:
    """Fit the coefficients at one alpha, keep them in `beta` for the next
    start, and return the log-likelihood."""
    beta = _fit_beta(data, precise_exp(log_alpha), beta.copy())
    return _log_likelihood(data, data.means(beta), precise_exp(-log_alpha))


def _information(
    data: _Data, beta: List[Float64], log_alpha: Float64
) raises -> Tuple[DenseMatrix, List[Float64]]:
    """Return minus the Hessian of the log-likelihood in the coefficients and
    log(alpha), lower triangle filled, and the gradient."""
    var p = len(beta)
    var m = p + 1
    var r = precise_exp(-log_alpha)
    var mu = data.means(beta)
    var minus = DenseMatrix(m, m)
    var gradient = List[Float64](length=m, fill=0.0)
    var first = 0.0
    var second = 0.0
    for i in range(len(data.y)):  # pragma: no branch
        var y = data.y[i]
        var u = mu[i]
        var s1 = 0.0
        var s2 = 0.0
        for j in range(Int(y)):
            var q = 1.0 / (r + Float64(j))
            s1 += q
            s2 += q * q
        var rm = r + u
        first += s1 + log(r) - log(rm) + (u - y) / rm
        second += -s2 + 1.0 / r - 1.0 / rm - (u - y) / (rm * rm)
        var weight = u * (r + y) * r / (rm * rm)
        var cross = (y - u) * u * r / (rm * rm)
        for a in range(p):  # pragma: no branch
            var xa = data.rows[i][a]
            gradient[a] += xa * (y - u) * r / rm
            minus.add(p, a, xa * cross)
            for b in range(a + 1):  # pragma: no branch
                minus.add(a, b, weight * xa * data.rows[i][b])
    gradient[p] = -r * first
    minus.set(p, p, -(r * r * second + r * first))
    return (minus^, gradient^)


def negative_binomial_regression(
    events: List[Int],
    exposure: List[Duration64],
    covariates: List[List[Float64]],
) raises -> NegativeBinomialModel:
    """Fit a negative binomial (NB2) model of event rates over person-time.

    Args:
        events: The events of each stratum.
        exposure: The person-time of each stratum.
        covariates: One row for each stratum, of one value for each
            covariate.

    Returns:
        The model, with the coefficients and their errors in `rates`, alpha
        and its error, and the log-likelihoods of the model and of the
        Poisson model.

    Raises:
        Error: If the strata are not valid, as for `poisson_regression`, the
            counts spread no more than Poisson counts, or the information is
            not positive definite at the maximum.
    """
    var poisson = poisson_regression(events, exposure, covariates, 1e-12, 1000)
    var data = _Data(events, exposure, covariates)
    var p = len(poisson.coefficients)
    var poisson_mu = data.means(poisson.coefficients)
    var poisson_ll = 0.0
    for i in range(len(data.y)):  # pragma: no branch
        var y = data.y[i]
        poisson_ll += y * log(poisson_mu[i]) - poisson_mu[i] - lgamma(y + 1.0)
    # The golden-section search of log(alpha), each start from the last fit.
    var beta = poisson.coefficients.copy()
    var low = _LEAST_LOG_ALPHA
    var high = _MOST_LOG_ALPHA
    var c = high - _GOLDEN * (high - low)
    var d = low + _GOLDEN * (high - low)
    var fc = _profile(data, c, beta)
    var fd = _profile(data, d, beta)
    for _ in range(_SEARCH_STEPS):  # pragma: no branch
        if fc > fd:
            high = d
            d = c
            fd = fc
            c = high - _GOLDEN * (high - low)
            fc = _profile(data, c, beta)
        else:
            low = c
            c = d
            fc = fd
            d = low + _GOLDEN * (high - low)
            fd = _profile(data, d, beta)
    var log_alpha = (low + high) / 2.0
    if log_alpha < _LEAST_LOG_ALPHA + 1.0:
        raise Error(
            "The counts spread no more than Poisson counts: use the Poisson"
            " model"
        )
    beta = _fit_beta(data, precise_exp(log_alpha), beta.copy())
    # Newton steps on the coefficients and log(alpha) together.
    for _ in range(_POLISH_STEPS):  # pragma: no branch
        var step = _information(data, beta, log_alpha)
        var change = cholesky_solve(step[0], step[1])
        for a in range(p):  # pragma: no branch
            beta[a] += change[a]
        log_alpha += change[p]
    var last = _information(data, beta, log_alpha)
    var covariance = cholesky_inverse(last[0])
    var rates = RateModel(p)
    for a in range(p):  # pragma: no branch
        rates.coefficients[a] = beta[a]
        rates.standard_errors[a] = sqrt(covariance.get(a, a))
    rates.steps = _SEARCH_STEPS + _POLISH_STEPS
    rates.converged = True
    var alpha = precise_exp(log_alpha)
    var mu = data.means(beta)
    var r = 1.0 / alpha
    var deviance = 0.0
    var pearson = 0.0
    for i in range(len(data.y)):  # pragma: no branch
        var y = data.y[i]
        if y > 0:
            deviance += y * log(y / mu[i])
        deviance -= (y + r) * log((y + r) / (mu[i] + r))
        pearson += (y - mu[i]) * (y - mu[i]) / (mu[i] + alpha * mu[i] * mu[i])
    rates.deviance = 2.0 * deviance
    rates.dispersion = pearson / Float64(len(data.y) - p)
    var out = NegativeBinomialModel(rates^)
    out.alpha = alpha
    out.alpha_error = alpha * sqrt(covariance.get(p, p))
    out.log_likelihood = _log_likelihood(data, mu, r)
    out.poisson_log_likelihood = poisson_ll
    return out^
