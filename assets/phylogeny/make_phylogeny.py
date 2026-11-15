# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write distance trees of synthetic protein sequences with Biopython and
scipy.

    python3 make_phylogeny.py > phylogeny_expected.txt

Run it with numpy 2.5.4, scipy 1.18.1 and Biopython 1.88. Eight sequences
of 120 residues evolve from one random root along a known tree, by
substitutions only, so that they keep one length and need no gap. Each
branch changes each site with a chance of its length.

- Each `sequence` line holds a name and its sequence.
- Each `p` line holds one row of the p-distances, the share of sites that
  differ.
- Each `kimura` line holds one row of Kimura's protein distances,
  `-ln(1 - p - 0.2 p^2)`.
- Each `nj` line holds one row of the leaf-to-leaf path lengths of the
  neighbor-joining tree of the p-distances, from Biopython's
  `DistanceTreeConstructor.nj`.
- Each `upgma` line holds one row of the cophenetic distances of the UPGMA
  tree of the p-distances, from scipy's `linkage` with the average method.
- The `midpoint` line holds the depth of each leaf below the root of the
  neighbor-joining tree after Biopython's `root_at_midpoint`.
"""

import numpy
from Bio.Phylo.TreeConstruction import DistanceMatrix, DistanceTreeConstructor
from scipy.cluster.hierarchy import cophenet, linkage
from scipy.spatial.distance import squareform

AMINO = "ARNDCQEGHILKMFPSTWYV"
generator = numpy.random.default_rng(20261115)
length = 120
root = generator.integers(0, 20, length)


def evolve(sequence, branch):
    out = sequence.copy()
    for site in range(length):
        if generator.random() < branch:
            out[site] = (out[site] + generator.integers(1, 20)) % 20
    return out


# ((A:0.05,B:0.08):0.1,(C:0.06,(D:0.04,E:0.07):0.05):0.08,((F:0.1,G:0.03):0.06,H:0.12):0.09)
ab = evolve(root, 0.10)
cde = evolve(root, 0.08)
de = evolve(cde, 0.05)
fgh = evolve(root, 0.09)
fg = evolve(fgh, 0.06)
leaves = {
    "A": evolve(ab, 0.05),
    "B": evolve(ab, 0.08),
    "C": evolve(cde, 0.06),
    "D": evolve(de, 0.04),
    "E": evolve(de, 0.07),
    "F": evolve(fg, 0.10),
    "G": evolve(fg, 0.03),
    "H": evolve(fgh, 0.12),
}
names = list(leaves)
for name in names:
    print("sequence", name, "".join(AMINO[k] for k in leaves[name]))
n = len(names)
p = numpy.zeros((n, n))
for i in range(n):
    for j in range(n):
        p[i, j] = numpy.mean(leaves[names[i]] != leaves[names[j]])


def rows(name, matrix):
    for row in matrix:
        print(name, " ".join(repr(float(v)) for v in row))


rows("p", p)
rows("kimura", -numpy.log(1.0 - p - 0.2 * p * p))
lower = [[float(p[i, j]) for j in range(i + 1)] for i in range(n)]
tree = DistanceTreeConstructor().nj(DistanceMatrix(names, lower))
patristic = numpy.array([[tree.distance(a, b) if a != b else 0.0 for b in names] for a in names])
rows("nj", patristic)
tree.root_at_midpoint()
print("midpoint", " ".join(repr(float(tree.distance(name))) for name in names))
rows("upgma", squareform(cophenet(linkage(squareform(p), method="average"))))
