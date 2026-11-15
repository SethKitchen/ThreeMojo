# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Searches along one variable: bisection and golden-section search.

- `bisect[below](low, high, steps)` finds where a test changes, between
  two ends. `below(x)` must hold from `low` up to the change, and fail
  from the change up to `high`. Each step halves the bracket, so 60
  steps reach the last place of a bracket of order 1.
- `golden_minimum[cost](low, high, steps)` finds the least of a cost
  with one minimum between two ends. Each step keeps 0.618 of the
  bracket and evaluates the cost once. Negate a cost to find its
  largest value.

Each gives the middle of the last bracket. The test and the cost run in
order, so one can carry its state from each call to the next, as a fit
that starts from the last fit does.
"""

comptime GOLDEN = 0.6180339887498949
"""`(sqrt 5 - 1) / 2`, the share of the bracket that a golden-section
step keeps."""


def bisect[
    below: def(Float64) raises capturing[_] -> Bool
](low: Float64, high: Float64, steps: Int) raises -> Float64:
    """Return where a test changes, by bisection.

    Parameters:
        below: True for a point below the change.

    Args:
        low: The low end. The test holds there.
        high: The high end. The test fails there.
        steps: The number of halvings, 0 or more.

    Returns:
        The middle of the last bracket.

    Raises:
        Error: If the test raises.
    """
    var lo = low
    var hi = high
    for _ in range(steps):
        var middle = 0.5 * (lo + hi)
        if below(middle):
            lo = middle
        else:
            hi = middle
    return 0.5 * (lo + hi)


def golden_minimum[
    cost: def(Float64) raises capturing[_] -> Float64
](low: Float64, high: Float64, steps: Int) raises -> Float64:
    """Return the least of a cost with one minimum, by golden section.

    Parameters:
        cost: The cost of a point.

    Args:
        low: The low end.
        high: The high end.
        steps: The number of steps, 0 or more. The cost runs `steps + 2`
            times: at the two inner points, then once at each step.

    Returns:
        The middle of the last bracket.

    Raises:
        Error: If the cost raises.
    """
    var lo = low
    var hi = high
    var c = hi - GOLDEN * (hi - lo)
    var d = lo + GOLDEN * (hi - lo)
    var fc = cost(c)
    var fd = cost(d)
    for _ in range(steps):
        if fc < fd:
            hi = d
            d = c
            fd = fc
            c = hi - GOLDEN * (hi - lo)
            fc = cost(c)
        else:
            lo = c
            c = d
            fc = fd
            d = lo + GOLDEN * (hi - lo)
            fd = cost(d)
    return 0.5 * (lo + hi)
