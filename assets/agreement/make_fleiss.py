# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write Fleiss' kappa of many raters with statsmodels and numpy.

    mojo run -I . tools/make_fleiss.mojo
    cd assets/agreement && python3 make_fleiss.py > fleiss_expected.txt

Run it with numpy 2.5.4 and statsmodels 0.15.0. The table is the example
of Fleiss' kappa on Wikipedia: 10 subjects, each put by 14 raters in one
of 5 categories. Its kappa is 0.210. A second table is synthetic:
`tools/make_fleiss.mojo` writes 40 films, `films.txt`, each graded by 6
readers in one of 4 grades.

Each `table` line holds one subject's counts, and a `results` line follows
the subjects of each table:

- Fleiss' kappa from statsmodels' `fleiss_kappa`, and Randolph's
  free-marginal kappa from the same function.

No library gives the standard error of Fleiss, Nee and Landis (1979) or
the kappa of each category. The Mojo tests check them against their
closed form.
"""

import numpy
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
with open("films.txt") as data:
    films = numpy.array([[int(v) for v in line.split()] for line in data if line.strip()])


def line(name, values):
    print(name, " ".join(repr(float(v)) for v in values))


for table in (wikipedia, films):
    for row in table:
        line("table", row)
    line("results", [fleiss_kappa(table), fleiss_kappa(table, method="randolph")])
