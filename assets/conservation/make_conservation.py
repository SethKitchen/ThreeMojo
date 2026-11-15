# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the conservation of each column of a synthetic protein
alignment, with numpy, scipy and Biopython.

    mojo run -I . tools/make_conservation.mojo
    cd assets/conservation && python3 make_conservation.py

Run it with numpy 2.5.4, scipy 1.18.1 and Biopython 1.88.
`tools/make_conservation.mojo` writes the alignment,
`conservation_msa.fasta`: 12 sequences of 48 columns, from one root
sequence by random changes, with some columns held, some free, and some
gaps. The first sequence has no gap. This script writes
`conservation_expected.txt`.

The background is the mean composition of the alignment, in the order
ARNDCQEGHILKMFPSTWYV, so that no value is 0. For each column, with
uniform weights, a line holds:

- the share of gaps;
- the Shannon entropy in bits of the residue shares, from scipy's
  `entropy`;
- the relative entropy in bits to the background, from Biopython's
  `motifs.Motif.relative_entropy` with the counts and no pseudocounts;
- the Jensen-Shannon divergence in bits to the background, the square of
  scipy's `jensenshannon` with base 2;
- the score: the divergence times one less the share of gaps.

A column with gaps only has 0 for each value but the share of gaps. No
library gives the weights of Henikoff and Henikoff (1994), so the Mojo
tests check them and the weighted scores by hand.
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

rows = []
with open(os.path.join(HERE, "conservation_msa.fasta")) as data:
    for line in data:
        line = line.strip()
        if line.startswith(">"):
            rows.append("")
        elif line:
            rows[-1] += line
assert len(rows) == ROWS and all(len(row) == COLUMNS for row in rows)

counts = numpy.zeros((COLUMNS, 20))
for row in rows:
    for c, a in enumerate(row):
        if a != "-":
            counts[c, ORDER.index(a)] += 1
background = counts.sum(axis=0) / counts.sum()
assert background.min() > 0


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


lines = ["background " + words(background)]
for c, values in enumerate(scores(numpy.full(ROWS, 1.0 / ROWS))):
    lines.append("uniform %d %s" % (c, words(values)))
with open(os.path.join(HERE, "conservation_expected.txt"), "w") as out:
    out.write("\n".join(lines) + "\n")
