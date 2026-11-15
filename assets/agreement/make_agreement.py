# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write agreement results by pingouin and scipy, two Python libraries.

    python3 make_agreement.py

Run it with numpy, scipy 1.17 and pingouin 0.7.0. It writes two files:

- `readers.txt` holds 40 synthetic tumors, one to a line: the volume in
  milliliters by reader A and by reader B, to 0.1 mL.
- `agreement_expected.txt` holds the results.

The expected file has these lines:

- `icc_shrout_fleiss` with the six intraclass correlations of the ratings
  of Shrout and Fleiss (1979), table 2, by pingouin: for each of ICC(1,1),
  ICC(A,1), ICC(C,1), ICC(1,k), ICC(A,k) and ICC(C,k), the ICC, F, the
  two degrees of freedom, the p value, and the low and high end of the 95
  percent interval. pingouin rounds its intervals to two decimals, so the
  ends come from its formulas with scipy, unrounded.
- `icc_readers` with the same values for the two readers.
- `bland_altman` with the count, the bias (A less B), the standard
  deviation of the differences, the lower and upper limits of agreement,
  and the 95 percent intervals of the bias, the lower limit and the upper
  limit, by the t distribution.
- `t` with t, the degrees of freedom, the upper tail of scipy and the
  0.975 quantile, for several cases.
- `f` with x, the two degrees of freedom, the upper tail of scipy and the
  0.975 quantile, for several cases.
"""

import numpy as np
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


def intervals(ratings):
    """The unrounded 95 percent intervals of pingouin 0.7.0's formulas."""
    x = np.asarray(ratings, dtype=float)
    n, k = x.shape
    grand = x.mean()
    ssb = k * ((x.mean(axis=1) - grand) ** 2).sum()
    ssj = n * ((x.mean(axis=0) - grand) ** 2).sum()
    sse = ((x - grand) ** 2).sum() - ssb - ssj
    msb = ssb / (n - 1)
    msj = ssj / (k - 1)
    mse = sse / ((n - 1) * (k - 1))
    msw = (ssj + sse) / (n * (k - 1))
    icc2 = (msb - mse) / (msb + (k - 1) * mse + k * (msj - mse) / n)
    f1k = msb / msw
    f3k = msb / mse
    df1 = n - 1
    df1kd = n * (k - 1)
    df2kd = (n - 1) * (k - 1)
    f1l = f1k / stats.f.ppf(0.975, df1, df1kd)
    f1u = f1k * stats.f.ppf(0.975, df1kd, df1)
    f3l = f3k / stats.f.ppf(0.975, df1, df2kd)
    f3u = f3k * stats.f.ppf(0.975, df2kd, df1)
    fj = msj / mse
    vn = df2kd * (k * icc2 * fj + n * (1 + (k - 1) * icc2) - k * icc2) ** 2
    vd = df1 * k**2 * icc2**2 * fj**2 + (n * (1 + (k - 1) * icc2) - k * icc2) ** 2
    v = vn / vd
    f2u = stats.f.ppf(0.975, n - 1, v)
    f2l = stats.f.ppf(0.975, v, n - 1)
    l2 = n * (msb - f2u * mse) / (f2u * (k * msj + (k * n - k - n) * mse) + n * msb)
    u2 = n * (f2l * msb - mse) / (k * msj + (k * n - k - n) * mse + n * f2l * msb)
    return [
        ((f1l - 1) / (f1l + k - 1), (f1u - 1) / (f1u + k - 1)),
        (l2, u2),
        ((f3l - 1) / (f3l + k - 1), (f3u - 1) / (f3u + k - 1)),
        (1 - 1 / f1l, 1 - 1 / f1u),
        (l2 * k / (1 + l2 * (k - 1)), u2 * k / (1 + u2 * (k - 1))),
        (1 - 1 / f3l, 1 - 1 / f3u),
    ]


def icc_line(name, ratings):
    rows = []
    for i, row in enumerate(ratings):
        for j, value in enumerate(row):
            rows.append((i, j, float(value)))
    frame = pd.DataFrame(rows, columns=["target", "rater", "rating"])
    table = pingouin.intraclass_corr(frame, "target", "rater", "rating")
    ends = intervals(ratings)
    values = []
    for r in range(6):
        low, high = ends[r]
        # The unrounded ends must round to pingouin's own.
        assert np.allclose(np.round([low, high], 2), table["CI95"][r])
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


rng = np.random.default_rng(20261115)
n = 40
truth = rng.lognormal(np.log(20.0), 0.6, n)
a = np.round(truth + rng.normal(0.0, 1.0, n), 1)
b = np.round(truth * 1.03 + 0.5 + rng.normal(0.0, 1.2, n), 1)
with open("readers.txt", "w") as out:
    for i in range(n):
        out.write("%.1f %.1f\n" % (a[i], b[i]))

lines = [
    icc_line("icc_shrout_fleiss", SHROUT_FLEISS),
    icc_line("icc_readers", np.column_stack([a, b])),
]
d = a - b
bias = d.mean()
sd = d.std(ddof=1)
t = stats.t.ppf(0.975, n - 1)
se_bias = sd / np.sqrt(n)
se_limit = np.sqrt(3.0 * sd**2 / n)
lower = bias - 1.96 * sd
upper = bias + 1.96 * sd
values = [
    n,
    bias,
    sd,
    lower,
    upper,
    bias - t * se_bias,
    bias + t * se_bias,
    lower - t * se_limit,
    lower + t * se_limit,
    upper - t * se_limit,
    upper + t * se_limit,
]
lines.append("bland_altman " + " ".join(repr(float(v)) for v in values))
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
