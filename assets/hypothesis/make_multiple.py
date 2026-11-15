# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write adjusted p values by statsmodels, a Python library.

    python3 make_multiple.py > multiple_expected.txt

Run it with statsmodels 0.15.0. The output has these lines:

- `p` with 12 p values of tests of biomarkers, in no order, with a tie.
- `bonferroni`, `holm`, `fdr_bh` and `fdr_by` with the adjusted p values
  of `multipletests` by each method, in the order of the p values.
"""

from statsmodels.stats.multitest import multipletests

P = [0.0008, 0.041, 0.31, 0.012, 0.0049, 0.27, 0.012, 0.66, 0.035, 0.0002, 0.09, 0.98]


def show(name, values):
    print(name + " " + " ".join(repr(float(v)) for v in values))


show("p", P)
for method in ["bonferroni", "holm", "fdr_bh", "fdr_by"]:
    show(method, multipletests(P, alpha=0.05, method=method)[1])
