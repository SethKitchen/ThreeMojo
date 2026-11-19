# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write agreement results by pingouin and scipy, two Python libraries.

    mojo run -I . tools/make_agreement.mojo
    cd assets/agreement && python3 make_agreement.py

Run it with pandas, scipy 1.18.1 and pingouin 0.7.0.
`tools/make_agreement.mojo` writes 40 synthetic tumors, `readers.txt`,
one to a line: the volume in milliliters by reader A and by reader B, to
0.1 mL. This script writes `agreement_expected.txt`:

- `icc_shrout_fleiss` with the six intraclass correlations of the ratings
  of Shrout and Fleiss (1979), table 2, by pingouin: for each of ICC(1,1),
  ICC(A,1), ICC(C,1), ICC(1,k), ICC(A,k) and ICC(C,k), the ICC, F, the
  two degrees of freedom, the p value, and the low and high end of the 95
  percent interval. pingouin rounds the ends to two decimals.
- `icc_readers` with the same values for the two readers.
- `t` with t, the degrees of freedom, the upper tail of scipy and the
  0.975 quantile, for several cases.
- `f` with x, the two degrees of freedom, the upper tail of scipy and the
  0.975 quantile, for several cases.

No library gives the Bland-Altman limits and their intervals. The Mojo
tests check them against their closed form.
"""

import pandas as pd
import pingouin
from scipy import stats

SHROUT_FLEISS = [
    [9, 2, 5, 8],
    [6, 1, 3, 2],
    [8, 4, 6, 8],
    [7, 1, 2, 6],
    [10, 5, 6, 9],
    [6, 2, 4, 7],
]


def icc_line(name, ratings):
    rows = []
    for i, row in enumerate(ratings):
        for j, value in enumerate(row):
            rows.append((i, j, float(value)))
    frame = pd.DataFrame(rows, columns=["target", "rater", "rating"])
    table = pingouin.intraclass_corr(frame, "target", "rater", "rating")
    values = []
    for r in range(6):
        low, high = table["CI95"][r]
        values += [
            table["ICC"][r],
            table["F"][r],
            table["df1"][r],
            table["df2"][r],
            table["pval"][r],
            low,
            high,
        ]
    return name + " " + " ".join(repr(float(v)) for v in values)


with open("readers.txt") as data:
    readers = [[float(v) for v in line.split()] for line in data if line.strip()]

lines = [
    icc_line("icc_shrout_fleiss", SHROUT_FLEISS),
    icc_line("icc_readers", readers),
]
values = []
for tv, df in [(2.0, 5.0), (0.5, 39.0), (-1.3, 3.0), (4.2, 120.0), (1.1, 7.5)]:
    values += [tv, df, stats.t.sf(tv, df), stats.t.ppf(0.975, df)]
lines.append("t " + " ".join(repr(float(v)) for v in values))
values = []
for x, d1, d2 in [
    (2.5, 5.0, 18.0),
    (0.4, 3.0, 2.0),
    (11.0, 1.0, 39.0),
    (1.3, 39.0, 39.0),
    (3.0, 4.6, 5.0),
    (0.9, 120.0, 7.0),
]:
    values += [x, d1, d2, stats.f.sf(x, d1, d2), stats.f.ppf(0.975, d1, d2)]
lines.append("f " + " ".join(repr(float(v)) for v in values))
with open("agreement_expected.txt", "w") as out:
    out.write("\n".join(lines) + "\n")
