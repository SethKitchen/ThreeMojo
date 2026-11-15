# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Adjusted p values for many tests, as statsmodels' `multipletests`
gives them.

With many tests, some find an effect by chance. An adjusted p value
corrects for the count of tests: a test rejects at a level when its
adjusted p value is at or below the level.

- `bonferroni` and `holm` control the chance of any false finding. Holm's
  steps reject at least what Bonferroni's rejects.
- `benjamini_hochberg` controls the expected share of false findings among
  the findings, for independent tests. `benjamini_yekutieli` controls it
  for any dependence.

Each function returns the adjusted p values in the order of the p values.
"""

from math.sort_utils import stable_sort


def _require_values(p: List[Float64]) raises:
    """Refuse no p value, or one outside [0, 1]."""
    if len(p) == 0:
        raise Error("An adjustment needs one p value or more")
    for v in p:  # pragma: no branch
        if not (v >= 0 and v <= 1):
            raise Error("A p value must be from 0 to 1")


def _order(p: List[Float64]) -> List[Int]:
    """Return the indices of the p values, from the least."""
    var order = List[Int]()
    for i in range(len(p)):  # pragma: no branch
        order.append(i)

    def before(a: Int, b: Int) capturing -> Bool:
        return p[a] < p[b]

    stable_sort[before](order)
    return order^


def bonferroni(p: List[Float64]) raises -> List[Float64]:
    """Return Bonferroni's adjusted p values, `min(1, m p)`.

    Args:
        p: The p values, each from 0 to 1.

    Returns:
        The adjusted p values.

    Raises:
        Error: If there is no p value, or one is out of range.
    """
    _require_values(p)
    var m = Float64(len(p))
    var out = List[Float64]()
    for v in p:  # pragma: no branch
        out.append(min(1.0, v * m))
    return out^


def holm(p: List[Float64]) raises -> List[Float64]:
    """Return Holm's step-down adjusted p values.

    The k-th least p value is multiplied by `m - k + 1`, and each adjusted
    value is at least the one before it.

    Args:
        p: The p values, each from 0 to 1.

    Returns:
        The adjusted p values.

    Raises:
        Error: If there is no p value, or one is out of range.
    """
    _require_values(p)
    var order = _order(p)
    var m = len(p)
    var out = List[Float64](length=m, fill=0.0)
    var running = 0.0
    for k in range(m):  # pragma: no branch
        running = max(running, p[order[k]] * Float64(m - k))
        out[order[k]] = min(1.0, running)
    return out^


def _step_up(p: List[Float64], scale: Float64) raises -> List[Float64]:
    """Divide the k-th least p value by `(k / m) / scale`, then take the
    least from the top down."""
    _require_values(p)
    var order = _order(p)
    var m = len(p)
    var out = List[Float64](length=m, fill=0.0)
    var running = 1.0
    var k = m - 1
    while k >= 0:
        var factor = Float64(k + 1) / Float64(m) / scale
        running = min(running, p[order[k]] / factor)
        out[order[k]] = running
        k -= 1
    return out^


def benjamini_hochberg(p: List[Float64]) raises -> List[Float64]:
    """Return the false discovery rate adjusted p values of Benjamini and
    Hochberg.

    The k-th least p value is multiplied by `m / k`, and each adjusted
    value is at most the one after it.

    Args:
        p: The p values, each from 0 to 1.

    Returns:
        The adjusted p values.

    Raises:
        Error: If there is no p value, or one is out of range.
    """
    return _step_up(p, 1.0)


def benjamini_yekutieli(p: List[Float64]) raises -> List[Float64]:
    """Return the false discovery rate adjusted p values of Benjamini and
    Yekutieli.

    These are those of Benjamini and Hochberg, times `sum(1 / k)` for k
    from 1 to m.

    Args:
        p: The p values, each from 0 to 1.

    Returns:
        The adjusted p values.

    Raises:
        Error: If there is no p value, or one is out of range.
    """
    _require_values(p)
    var harmonic = 0.0
    for k in range(1, len(p) + 1):  # pragma: no branch
        harmonic += 1.0 / Float64(k)
    return _step_up(p, harmonic)
