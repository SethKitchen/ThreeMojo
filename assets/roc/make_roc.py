# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write two synthetic markers and their ROC analysis by scikit-learn and
MLstatkit, two Python libraries.

    mojo run -I . tools/make_roc.mojo
    cd assets/roc && python3 make_roc.py

Run it with numpy, scikit-learn 1.9.1 and MLstatkit 0.1.91.
`tools/make_roc.mojo` writes 150 synthetic patients, `markers.txt`, one
to a line: 1 for a diseased patient or 0 for a healthy one, then the
values of marker A and of marker B. Marker A has one decimal, so many of
its values tie. This script reads them and writes `roc_expected.txt`.

The expected file has these lines:

- `curve_a` with the point count of the ROC curve of marker A from
  scikit-learn's `roc_curve`, without dropped points, then for each point
  the threshold, the false positive rate and the sensitivity. The first
  threshold is infinity.
- `auc` with the AUC of marker A and of marker B from `roc_auc_score`.
- `delong` with MLstatkit's DeLong test of B against A: z, the p value,
  the 95 percent interval of the AUC of A and of B, and the variance of the
  difference.
- `youden` with the threshold, the sensitivity and the specificity of the
  first largest Youden index of marker A, by numpy on the curve.
"""

import numpy as np
from MLstatkit import Delong_test
from sklearn.metrics import roc_auc_score, roc_curve

with open("markers.txt") as data:
    rows = np.array([[float(v) for v in line.split()] for line in data if line.strip()])
diseased = rows[:, 0].astype(int)
a = rows[:, 1]
b = rows[:, 2]

lines = []
fpr, tpr, thresholds = roc_curve(diseased, a, drop_intermediate=False)
values = [len(fpr)]
for i in range(len(fpr)):
    values += [thresholds[i], fpr[i], tpr[i]]
lines.append("curve_a " + " ".join(repr(float(v)) for v in values))
lines.append(
    "auc %r %r"
    % (float(roc_auc_score(diseased, a)), float(roc_auc_score(diseased, b)))
)
z, p, ci_a, ci_b, auc_a, auc_b, info = Delong_test(diseased, a, b)
lines.append(
    "delong %r %r %r %r %r %r %r"
    % (
        float(z),
        float(p),
        float(ci_a[0]),
        float(ci_a[1]),
        float(ci_b[0]),
        float(ci_b[1]),
        float(info["var_diff"]),
    )
)
j = int(np.argmax(tpr - fpr))
lines.append(
    "youden %r %r %r" % (float(thresholds[j]), float(tpr[j]), float(1 - fpr[j]))
)
with open("roc_expected.txt", "w") as out:
    out.write("\n".join(lines) + "\n")
