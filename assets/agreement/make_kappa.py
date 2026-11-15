# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write Cohen's kappa by statsmodels, a Python library.

    python3 make_kappa.py > kappa_expected.txt

Run it with statsmodels 0.15.0. Each line is a table and a kind of kappa:
the name, the count of categories k, the k x k counts by rows (rater A
across the rows, rater B down the columns), then kappa, its standard
error, its standard error under no agreement beyond chance, and the low
and high ends of its 95 percent interval, by `cohens_kappa`.

The tables are synthetic: two readers who grade 120 chest films as
normal, benign, suspicious or malignant, and two who call 60 smears
positive or negative.
"""

import numpy as np
from statsmodels.stats.inter_rater import cohens_kappa

FILMS = [[40, 6, 1, 0], [5, 25, 4, 1], [1, 3, 17, 3], [0, 1, 2, 11]]
SMEARS = [[22, 4], [6, 28]]

for name, table, wt in [
    ("simple", FILMS, None),
    ("linear", FILMS, "linear"),
    ("quadratic", FILMS, "quadratic"),
    ("simple", SMEARS, None),
]:
    if wt is None:
        r = cohens_kappa(table)
    else:
        r = cohens_kappa(table, wt=wt, weights=np.arange(len(table)))
    values = [len(table)] + list(np.ravel(table)) + [
        r.kappa, r.std_kappa, r.std_kappa0, r.kappa_low, r.kappa_upp
    ]
    print(name + " " + " ".join(repr(float(v)) for v in values))
