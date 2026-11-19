# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write distance trees of synthetic protein sequences with Biopython and
scipy.

    mojo run -I . tools/make_phylogeny.mojo
    cd assets/phylogeny && python3 make_phylogeny.py > phylogeny_expected.txt

Run it with numpy 2.5.4, scipy 1.18.1 and Biopython 1.88.
`tools/make_phylogeny.mojo` writes eight sequences of 120 residues,
`sequences.txt`, that evolve from one random root along a known tree, by
substitutions only, so that they keep one length and need no gap.

- Each `sequence` line holds a name and its sequence.
- Each `p` line holds one row of the p-distances, the share of sites that
  differ, from Biopython's `DistanceCalculator` with the `identity` model.
- Each `nj` line holds one row of the leaf-to-leaf path lengths of the
  neighbor-joining tree of the p-distances, from Biopython's
  `DistanceTreeConstructor.nj`.
- Each `upgma` line holds one row of the cophenetic distances of the UPGMA
  tree of the p-distances, from scipy's `linkage` with the average method.
- The `midpoint` line holds the depth of each leaf below the root of the
  neighbor-joining tree after Biopython's `root_at_midpoint`.

No library gives Kimura's protein distance, `-ln(1 - p - 0.2 p^2)`, so
the Mojo tests check it against its closed form.
"""

import numpy
from Bio.Align import MultipleSeqAlignment
from Bio.Phylo.TreeConstruction import DistanceCalculator, DistanceMatrix, DistanceTreeConstructor
from Bio.Seq import Seq
from Bio.SeqRecord import SeqRecord
from scipy.cluster.hierarchy import cophenet, linkage
from scipy.spatial.distance import squareform

with open("sequences.txt") as data:
    leaves = dict(line.split() for line in data if line.strip())
names = list(leaves)
for name in names:
    print("sequence", name, leaves[name])
n = len(names)
alignment = MultipleSeqAlignment([SeqRecord(Seq(leaves[name]), id=name) for name in names])
identity = DistanceCalculator("identity").get_distance(alignment)
p = numpy.array([[identity[a, b] for b in names] for a in names])


def rows(name, matrix):
    for row in matrix:
        print(name, " ".join(repr(float(v)) for v in row))


rows("p", p)
lower = [[float(p[i, j]) for j in range(i + 1)] for i in range(n)]
tree = DistanceTreeConstructor().nj(DistanceMatrix(names, lower))
patristic = numpy.array([[tree.distance(a, b) if a != b else 0.0 for b in names] for a in names])
rows("nj", patristic)
tree.root_at_midpoint()
print("midpoint", " ".join(repr(float(tree.distance(name))) for name in names))
rows("upgma", squareform(cophenet(linkage(squareform(p), method="average"))))
