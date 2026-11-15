# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write Simon's two-stage designs by an exhaustive search with scipy, and
posterior probabilities of a response rate.

    python3 make_phase2.py > phase2_expected.txt

Run it with numpy 2.5.4 and scipy 1.18.1. A design treats n1 patients,
stops when r1 or fewer respond, else treats n - n1 more, and rejects the
null response rate p0 when more than r of all n respond. For each n from
1 to the most, each n1 below n and each r1, the search takes the least r
whose type I error is at most alpha, and keeps the design when its power
at p1 is at least 1 - beta.

- The optimal design has the least expected size under p0, and the
  minimax design the least n, then the least expected size. The search
  runs to n = 60, and a tie keeps the first design, in the order of n,
  n1 and r1.
- Each `design` line holds p0, p1, alpha, beta, then r1, n1, r, n, the
  chance of an early stop under p0, the expected size under p0, the type
  I error and the power, for the optimal and then the minimax design.
- Each `posterior` line holds the prior a and b, the responses, the
  patients, p0, and the posterior probability that the rate is above p0,
  from scipy's `beta.sf`.
"""

import numpy
import scipy.stats

MOST = 60


def errors(r1, n1, r, n, p):
    """Return the chance of rejecting at p, and of stopping early."""
    x1 = numpy.arange(r1 + 1, n1 + 1)
    first = scipy.stats.binom.pmf(x1, n1, p)
    second = scipy.stats.binom.sf(r - x1, n - n1, p)
    return float(numpy.sum(first * second)), float(scipy.stats.binom.cdf(r1, n1, p))


def search(p0, p1, alpha, beta):
    best = None
    minimax = None
    for n in range(2, MOST + 1):
        for n1 in range(1, n):
            for r1 in range(0, n1):
                # The least r with a type I error of at most alpha.
                found = None
                for r in range(r1, n):
                    if errors(r1, n1, r, n, p0)[0] <= alpha:
                        found = r
                        break
                if found is None:
                    continue
                power = errors(r1, n1, found, n, p1)[0]
                if power < 1 - beta:
                    continue
                size, stop = errors(r1, n1, found, n, p0)
                expected = n1 + (1 - stop) * (n - n1)
                design = (expected, n, r1, n1, found, stop, size, power)
                if best is None or design[0] < best[0]:
                    best = design
                if minimax is None or (n, expected) < (minimax[1], minimax[0]):
                    minimax = design
    return best, minimax


def words(values):
    return " ".join(repr(float(v)) for v in values)


for p0, p1, alpha, beta in ((0.1, 0.3, 0.05, 0.2), (0.2, 0.4, 0.05, 0.2), (0.05, 0.25, 0.1, 0.1)):
    best, minimax = search(p0, p1, alpha, beta)
    row = [p0, p1, alpha, beta]
    for d in (best, minimax):
        expected, n, r1, n1, r, stop, size, power = d
        row += [r1, n1, r, n, stop, expected, size, power]
    print("design", words(row))

for a, b, x, n, p0 in ((1, 1, 7, 20, 0.2), (0.5, 0.5, 3, 25, 0.1), (2, 8, 12, 30, 0.3), (1, 1, 0, 10, 0.05)):
    print("posterior", words([a, b, x, n, p0, scipy.stats.beta.sf(p0, a + x, b + n - x)]))
