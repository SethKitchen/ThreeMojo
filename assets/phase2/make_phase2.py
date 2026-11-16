# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write Simon's two-stage designs of his table of 1989, the binomial
probabilities they need from scipy, and posterior probabilities of a
response rate.

    python3 make_phase2.py > phase2_expected.txt

Run it with numpy 2.5.4 and scipy 1.18.1. A design treats n1 patients,
stops when r1 or fewer respond, else treats n - n1 more, and rejects the
null response rate p0 when more than r of all n respond.

- Each `design` line holds p0, p1, alpha, beta, then r1, n1, r and n of
  the optimal and then the minimax design, from Tables 1 and 2 of Simon,
  "Optimal two-stage designs for phase II clinical trials", Controlled
  Clinical Trials, 1989.
- Each `binomial` line holds a count m and a chance p, then scipy's
  `binom.pmf(k, m, p)` and `binom.sf(k, m, p)` for k from 0 to m. There is
  one for each stage of each design, at p0 and at p1.
- Each `posterior` line holds the prior a and b, the responses, the
  patients, p0, and the posterior probability that the rate is above p0,
  from scipy's `beta.sf`.

The test builds the type I error, the power, the chance of an early stop
and the expected size of each design from the `binomial` lines.
"""

import numpy
import scipy.stats

# p0, p1, alpha, beta, then (r1, n1, r, n) of the optimal and the minimax
# design, as Simon (1989) gives them.
DESIGNS = [
    (0.1, 0.3, 0.05, 0.2, (1, 10, 5, 29), (1, 15, 5, 25)),
    (0.2, 0.4, 0.05, 0.2, (3, 13, 12, 43), (4, 18, 10, 33)),
    (0.05, 0.25, 0.1, 0.1, (0, 9, 2, 24), (0, 13, 2, 20)),
]


def words(values):
    return " ".join(repr(float(v)) for v in values)


needed = []
for p0, p1, alpha, beta, optimal, minimax in DESIGNS:
    print("design", words([p0, p1, alpha, beta, *optimal, *minimax]))
    for _, n1, _, n in (optimal, minimax):
        for p in (p0, p1):
            for m in (n1, n - n1):
                if (m, p) not in needed:
                    needed.append((m, p))
for m, p in needed:
    k = numpy.arange(m + 1)
    pmf = scipy.stats.binom.pmf(k, m, p)
    sf = scipy.stats.binom.sf(k, m, p)
    print("binomial", words([m, p, *pmf, *sf]))

for a, b, x, n, p0 in ((1, 1, 7, 20, 0.2), (0.5, 0.5, 3, 25, 0.1), (2, 8, 12, 30, 0.3), (1, 1, 0, 10, 0.05)):
    print("posterior", words([a, b, x, n, p0, scipy.stats.beta.sf(p0, a + x, b + n - x)]))
