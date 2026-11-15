# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write a synthetic protein alignment and the conservation of each of its
columns, with numpy, scipy and Biopython.

    python3 make_conservation.py

Run it with numpy 2.5.4, scipy 1.18.1 and Biopython 1.88. It writes
`conservation_msa.fasta` and `conservation_expected.txt` beside it.

The alignment has 12 sequences of 48 columns, from one root sequence by
random changes, with some columns held, some free, and some gaps. The
first sequence has no gap. The background is the mean composition of the
alignment, in the order ARNDCQEGHILKMFPSTWYV, so that no value is 0.

The weights are those of Henikoff and Henikoff (1994), in numpy: in each
column, each sequence with a residue gets `1 / (r n)`, where r is the
count of residue types in the column and n the count of its own type.
Gaps get nothing, and the weights are scaled to sum to 1.

For each column, with uniform weights and then with these weights, a line
holds:

- the weighted share of gaps;
- the Shannon entropy in bits of the residue shares, from scipy's
  `entropy`;
- the relative entropy in bits to the background, from Biopython's
  `motifs.Motif.relative_entropy` with the weighted counts and no
  pseudocounts;
- the Jensen-Shannon divergence in bits to the background, the square of
  scipy's `jensenshannon` with base 2;
- the score: the divergence times one less the share of gaps.

A column with gaps only has 0 for each value but the share of gaps.
"""

import os

import numpy
import scipy.spatial.distance
import scipy.stats
from Bio import motifs

HERE = os.path.dirname(os.path.abspath(__file__))
ORDER = "ARNDCQEGHILKMFPSTWYV"
ROWS = 12
COLUMNS = 48

rng = numpy.random.default_rng(1126)
root = rng.choice(list(ORDER), COLUMNS)
rows = []
for r in range(ROWS):
    row = list(root)
    for c in range(COLUMNS):
        # Columns 0 to 11 are held; 12 to 35 change at a rate that rises;
        # 36 to 47 are free.
        rate = 0.0 if c < 12 else (0.03 * (c - 11) if c < 36 else 0.9)
        if rng.random() < rate:
            row[c] = rng.choice(list(ORDER))
        if r > 0 and c >= 20 and rng.random() < 0.12:
            row[c] = "-"
    rows.append("".join(row))
# One column of gaps only, but in the first sequence.
for r in range(1, ROWS):
    rows[r] = rows[r][:30] + "-" + rows[r][31:]
rows[1] = rows[1][:5] + "-" + rows[1][6:]

counts = numpy.zeros((COLUMNS, 20))
for row in rows:
    for c, a in enumerate(row):
        if a != "-":
            counts[c, ORDER.index(a)] += 1
background = counts.sum(axis=0) / counts.sum()
assert background.min() > 0


def henikoff(rows):
    w = numpy.zeros(len(rows))
    for c in range(COLUMNS):
        col = [row[c] for row in rows]
        kinds = {a for a in col if a != "-"}
        for j, a in enumerate(col):
            if a != "-":
                w[j] += 1.0 / (len(kinds) * col.count(a))
    return w / w.sum()


def scores(weights):
    out = []
    table = numpy.zeros((COLUMNS, 20))
    gaps = numpy.zeros(COLUMNS)
    for c in range(COLUMNS):
        for j, row in enumerate(rows):
            if row[c] == "-":
                gaps[c] += weights[j]
            else:
                table[c, ORDER.index(row[c])] += weights[j]
    motif = motifs.Motif(alphabet=ORDER, counts={a: list(table[:, i]) for i, a in enumerate(ORDER)})
    motif.background = {a: background[i] for i, a in enumerate(ORDER)}
    motif.pseudocounts = 0
    relative = motif.relative_entropy
    for c in range(COLUMNS):
        total = table[c].sum()
        if total == 0:
            out.append([gaps[c], 0.0, 0.0, 0.0, 0.0])
            continue
        p = table[c] / total
        h = scipy.stats.entropy(p, base=2)
        mine = float(numpy.sum(p[p > 0] * numpy.log2(p[p > 0] / background[p > 0])))
        assert abs(mine - relative[c]) <= 1e-12 * max(1.0, abs(mine))
        jsd = scipy.spatial.distance.jensenshannon(p, background, base=2) ** 2
        out.append([gaps[c], h, relative[c], jsd, jsd * (1.0 - gaps[c])])
    return out


def words(values):
    return " ".join(repr(float(v)) for v in values)


with open(os.path.join(HERE, "conservation_msa.fasta"), "w") as out:
    for r, row in enumerate(rows):
        out.write(">seq%d synthetic\n%s\n%s\n" % (r, row[:30], row[30:]))

lines = ["background " + words(background)]
weights = henikoff(rows)
lines.append("weights " + words(weights))
for name, w in (("uniform", numpy.full(ROWS, 1.0 / ROWS)), ("weighted", weights)):
    for c, values in enumerate(scores(w)):
        lines.append("%s %d %s" % (name, c, words(values)))
with open(os.path.join(HERE, "conservation_expected.txt"), "w") as out:
    out.write("\n".join(lines) + "\n")
