# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write Fleiss' kappa of many raters with statsmodels and numpy.

    python3 make_fleiss.py > fleiss_expected.txt

Run it with numpy 2.5.4, scipy 1.18.1 and statsmodels 0.15.0. The table is
the example of Fleiss' kappa on Wikipedia: 10 subjects, each put by 14
raters in one of 5 categories. Its kappa is 0.210. A second table is
synthetic: 40 films, each graded by 6 readers in one of 4 grades.

Each `table` line holds one subject's counts, and a `results` line follows
the subjects of each table:

- Fleiss' kappa from statsmodels' `fleiss_kappa`, and Randolph's
  free-marginal kappa from the same function.
- The standard error under no agreement beyond chance of Fleiss, Nee and
  Landis (1979), z, and the two-sided p value from scipy, as R's
  `irr::kappam.fleiss` gives them.
- The kappa of each category, by Fleiss (1971).
"""

import numpy
import scipy.stats
from statsmodels.stats.inter_rater import fleiss_kappa

wikipedia = numpy.array(
    [
        [0, 0, 0, 0, 14],
        [0, 2, 6, 4, 2],
        [0, 0, 3, 5, 6],
        [0, 3, 9, 2, 0],
        [2, 2, 8, 1, 1],
        [7, 7, 0, 0, 0],
        [3, 2, 6, 3, 0],
        [2, 5, 3, 2, 2],
        [6, 5, 2, 1, 0],
        [0, 2, 2, 3, 7],
    ]
)
generator = numpy.random.default_rng(20261115)
films = []
for _ in range(40):
    grade = generator.integers(0, 4)
    shares = numpy.full(4, 0.08)
    shares[grade] = 0.6
    if grade > 0:
        shares[grade - 1] += 0.08
    shares /= shares.sum()
    films.append(generator.multinomial(6, shares))
films = numpy.array(films)


def line(name, values):
    print(name, " ".join(repr(float(v)) for v in values))


for table in (wikipedia, films):
    for row in table:
        line("table", row)
    subjects, _ = table.shape
    raters = table.sum(axis=1)[0]
    p = table.sum(axis=0) / (subjects * raters)
    q = 1.0 - p
    pq = numpy.sum(p * q)
    error = (
        numpy.sqrt(2.0)
        / (pq * numpy.sqrt(subjects * raters * (raters - 1.0)))
        * numpy.sqrt(pq * pq - numpy.sum(p * q * (q - p)))
    )
    kappa = fleiss_kappa(table)
    z = kappa / error
    each = 1.0 - numpy.sum(table * (raters - table), axis=0) / (
        subjects * raters * (raters - 1.0) * p * q
    )
    line(
        "results",
        [kappa, fleiss_kappa(table, method="randolph"), error, z, 2.0 * scipy.stats.norm.sf(abs(z))]
        + list(each),
    )
