# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Single-arm phase II designs: Simon's two stages, and the posterior of a
response rate.

A phase II trial of a new drug asks whether its response rate is above a
rate p0 of no interest, and near a rate p1 of interest. Simon (1989) gives
two stages: treat n1 patients, and stop for futility when r1 or fewer
respond. Else treat n - n1 more, and reject p0 when more than r of all n
respond.

- `simon_optimal(p0, p1, alpha, beta, most)` searches every design with
  n up to `most` for the least expected size under p0, with a type I
  error of at most alpha and a power of at least 1 - beta.
- `simon_minimax(p0, p1, alpha, beta, most)` searches for the least n,
  then the least expected size.
- `simon_errors(design, p)` gives the chance that a design rejects p0, and
  that it stops early, when the true rate is p.
- `posterior_above(a, b, responses, patients, p0)` gives the posterior
  probability that the rate is above p0, from a beta prior.

For each n, n1 and r1, the search takes the least r whose type I error is
at most alpha, by bisection: the error falls as r rises. A tie keeps the
first design, in the order of n, n1 and r1.
"""

from extensions.clinical.distributions import beta_tails, precise_exp
from std.math import isfinite, lgamma, log

comptime MAX_SIMON_SIZE = 100
"""The largest n of a design search."""


struct SimonDesign(Copyable, Movable):
    """A two-stage design of Simon."""

    var r1: Int
    """The most responses in the first stage that stop the trial."""
    var n1: Int
    """The patients of the first stage."""
    var r: Int
    """The most responses of all the patients that do not reject p0."""
    var n: Int
    """The patients of both stages."""
    var early_stop: Float64
    """The chance of a stop after the first stage under p0."""
    var expected: Float64
    """The expected patients under p0."""
    var alpha: Float64
    """The type I error: the chance of rejecting p0 under p0."""
    var power: Float64
    """The power: the chance of rejecting p0 under p1."""

    def __init__(
        out self,
        r1: Int,
        n1: Int,
        r: Int,
        n: Int,
        early_stop: Float64,
        alpha: Float64,
        power: Float64,
    ):
        """Create a design.

        Args:
            r1: The stopping bound of the first stage.
            n1: The patients of the first stage.
            r: The final bound.
            n: The patients of both stages.
            early_stop: The chance of an early stop under p0.
            alpha: The type I error.
            power: The power.
        """
        self.r1 = r1
        self.n1 = n1
        self.r = r
        self.n = n
        self.early_stop = early_stop
        self.expected = Float64(n1) + (1.0 - early_stop) * Float64(n - n1)
        self.alpha = alpha
        self.power = power


struct _Binomial(Movable):
    """The probabilities of each count of each size, up to a most, at one
    rate."""

    var pmf: List[List[Float64]]
    """`pmf[m][x]`: the chance of x of m."""
    var above: List[List[Float64]]
    """`above[m][k]`: the chance of more than k of m, for k from 0 to m."""

    def __init__(out self, most: Int, p: Float64):
        """Tabulate the binomial distribution.

        Args:
            most: The largest size.
            p: The rate, above 0 and below 1.
        """
        self.pmf = List[List[Float64]]()
        self.above = List[List[Float64]]()
        var lp = log(p)
        var lq = log(1.0 - p)
        for m in range(most + 1):  # pragma: no branch
            var row = List[Float64]()
            for x in range(m + 1):  # pragma: no branch
                row.append(
                    precise_exp(
                        lgamma(Float64(m + 1))
                        - lgamma(Float64(x + 1))
                        - lgamma(Float64(m - x + 1))
                        + Float64(x) * lp
                        + Float64(m - x) * lq
                    )
                )
            var tail = List[Float64](length=m + 1, fill=0.0)
            var sum = 0.0
            for k in range(m - 1, -1, -1):
                sum += row[k + 1]
                tail[k] = sum
            self.pmf.append(row^)
            self.above.append(tail^)

    def more_than(self, m: Int, k: Int) -> Float64:
        """Return the chance of more than k of m."""
        if k < 0:
            return 1.0
        if k >= m:
            return 0.0
        return self.above[m][k]

    def reject(self, r1: Int, n1: Int, r: Int, n: Int) -> Float64:
        """Return the chance of more than r1 of n1, and more than r of n."""
        var total = 0.0
        # r1 is below n1, so the loop runs.
        for x1 in range(r1 + 1, n1 + 1):  # pragma: no branch
            total += self.pmf[n1][x1] * self.more_than(n - n1, r - x1)
        return total

    def stop(self, r1: Int, n1: Int) -> Float64:
        """Return the chance of r1 or fewer of n1."""
        return 1.0 - self.more_than(n1, r1)


def _require_rates(p0: Float64, p1: Float64) raises:
    """Refuse rates that are not between 0 and 1, with p1 above p0."""
    # p0 below p1 below 1 holds p0 below 1.
    if not (p0 > 0 and p1 > p0 and p1 < 1):
        raise Error("A phase II design needs 0 < p0 < p1 < 1")


def _search(
    p0: Float64,
    p1: Float64,
    alpha: Float64,
    beta: Float64,
    most: Int,
    minimax: Bool,
) raises -> SimonDesign:
    """Search the designs up to `most` patients for the optimal design, or
    the minimax design."""
    _require_rates(p0, p1)
    if not (alpha > 0 and alpha < 0.5) or not (beta > 0 and beta < 0.5):
        raise Error("A phase II design needs alpha and beta from 0 to 0.5")
    if most < 2 or most > MAX_SIMON_SIZE:
        raise Error("A Simon design search runs to from 2 to 100 patients")
    var null = _Binomial(most, p0)
    var alternative = _Binomial(most, p1)
    var found = False
    var best = SimonDesign(0, 0, 0, 0, 0.0, 0.0, 0.0)
    for n in range(2, most + 1):  # pragma: no branch
        # The first n with a design is the least, so the minimax search
        # ends there.
        if minimax and found:
            break
        for n1 in range(1, n):  # pragma: no branch
            for r1 in range(n1):  # pragma: no branch
                # The least r with an error of at most alpha, if any: the
                # error falls as r rises.
                var low = r1
                var high = n - 1
                while low < high:
                    var middle = (low + high) // 2
                    if null.reject(r1, n1, middle, n) <= alpha:
                        high = middle
                    else:
                        low = middle + 1
                var r = low
                var size = null.reject(r1, n1, r, n)
                if size > alpha:
                    continue
                var power = alternative.reject(r1, n1, r, n)
                if power < 1.0 - beta:
                    continue
                var design = SimonDesign(
                    r1, n1, r, n, null.stop(r1, n1), size, power
                )
                if not found or design.expected < best.expected:
                    best = design^
                    found = True
    if not found:
        raise Error("No Simon design of at most that many patients holds")
    return best^


def simon_optimal(
    p0: Float64, p1: Float64, alpha: Float64, beta: Float64, most: Int
) raises -> SimonDesign:
    """Return Simon's optimal two-stage design.

    Args:
        p0: The response rate of no interest, above 0 and below p1.
        p1: The response rate of interest, below 1.
        alpha: The most type I error, above 0 and below 0.5.
        beta: The most type II error, above 0 and below 0.5.
        most: The most patients to search, from 2 to 100.

    Returns:
        The design with the least expected size under p0.

    Raises:
        Error: If a rate, an error or the most is out of range, or no
            design of at most `most` patients holds.
    """
    return _search(p0, p1, alpha, beta, most, False)


def simon_minimax(
    p0: Float64, p1: Float64, alpha: Float64, beta: Float64, most: Int
) raises -> SimonDesign:
    """Return Simon's minimax two-stage design.

    Args:
        p0: The response rate of no interest, above 0 and below p1.
        p1: The response rate of interest, below 1.
        alpha: The most type I error, above 0 and below 0.5.
        beta: The most type II error, above 0 and below 0.5.
        most: The most patients to search, from 2 to 100.

    Returns:
        The design with the least n, then the least expected size.

    Raises:
        Error: If a rate, an error or the most is out of range, or no
            design of at most `most` patients holds.
    """
    return _search(p0, p1, alpha, beta, most, True)


def simon_errors(
    design: SimonDesign, p: Float64
) raises -> Tuple[Float64, Float64]:
    """Return the chances of a design at a response rate.

    Args:
        design: The design.
        p: The true response rate, above 0 and below 1.

    Returns:
        The chance that the design rejects p0, and the chance that it stops
        after the first stage.

    Raises:
        Error: If the rate is out of range, or the design is not
            `0 <= r1 < n1 < n` with `r1 <= r < n` and n at most 100.
    """
    if not (p > 0 and p < 1):
        raise Error("A response rate is above 0 and below 1")
    if not (
        design.r1 >= 0
        and design.r1 < design.n1
        and design.n1 < design.n
        and design.r >= design.r1
        and design.r < design.n
        and design.n <= MAX_SIMON_SIZE
    ):
        raise Error("A Simon design needs 0 <= r1 < n1 < n and r1 <= r < n")
    var table = _Binomial(design.n, p)
    return (
        table.reject(design.r1, design.n1, design.r, design.n),
        table.stop(design.r1, design.n1),
    )


def posterior_above(
    a: Float64, b: Float64, responses: Int, patients: Int, p0: Float64
) raises -> Float64:
    """Return the posterior probability that a response rate is above p0.

    Args:
        a: The first shape of the beta prior, above 0, such as 1.
        b: The second shape of the beta prior, above 0, such as 1.
        responses: The responses, from 0 to the patients.
        patients: The patients, 1 or more.
        p0: The rate, above 0 and below 1.

    Returns:
        `P(p > p0)` under the beta posterior of shapes
        `a + responses` and `b + patients - responses`.

    Raises:
        Error: If a shape is not positive and finite, the counts are out of
            range, or p0 is not between 0 and 1.
    """
    if not (a > 0 and b > 0) or not isfinite(a) or not isfinite(b):
        raise Error("A beta prior needs positive, finite shapes")
    if patients < 1 or responses < 0 or responses > patients:
        raise Error("The responses are from 0 to the patients, 1 or more")
    if not (p0 > 0 and p0 < 1):
        raise Error("A response rate is above 0 and below 1")
    return beta_tails(
        p0,
        a + Float64(responses),
        b + Float64(patients - responses),
    )[1]
