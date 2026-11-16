# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The neighbor-joining tree of a synthetic outbreak in three wards.

    mojo run -I . examples/phylogeny.mojo [out/phylogeny.png]

The page is Molecular structures. A protein of 300 residues of a synthetic
pathogen spreads from one source into three wards. In each ward, it
reaches four patients, and it changes a little on each branch of the
spread. `alignment_distances` aligns each pair of the twelve sequences,
`kimura_distances` corrects the p-distances, and `neighbor_joining` builds
the tree. The tree finds the three wards: the patients of each ward share
a branch.

Neighbor joining does not find the root, so `midpoint_root` roots the
tree at the middle of its longest path between two patients. The root is
at the left.

This is a synthetic outbreak, for teaching. It is not a study of a real
pathogen.
"""

from extensions.molecule.phylogeny import (
    alignment_distances,
    kimura_distances,
    midpoint_root,
    neighbor_joining,
    tree_image,
)
from extensions.village.hud import Rgb, TextStyle, draw_styled
from render.png import encode
from std.pathlib import Path
from tools._example_output import example_destination
from extensions.numerics.noise import Xorshift64

comptime DEFAULT_OUTPUT = "out/phylogeny.png"
comptime AMINO = "ARNDCQEGHILKMFPSTWYV"
comptime LENGTH = 300


def _residue(mut noise: Xorshift64) -> Int:
    """Return a residue from 0 to 19, each as likely."""
    return Int(noise.uniform() * 20.0) % 20


def _evolve(
    mut noise: Xorshift64, sequence: List[Int], branch: Float64
) -> List[Int]:
    """Change each site with the chance of the branch length."""
    var out = sequence.copy()
    for site in range(len(out)):
        if noise.uniform() < branch:
            out[site] = (out[site] + 1 + Int(noise.uniform() * 19.0)) % 20
    return out^


def _text(sequence: List[Int]) -> String:
    var out = String("")
    var codes = String(AMINO).as_bytes()
    for k in sequence:
        out += chr(Int(codes[k]))
    return out


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var noise = Xorshift64(20261115)
    var source = List[Int]()
    for _ in range(LENGTH):
        source.append(_residue(noise))
    var names = List[String]()
    var sequences = List[String]()
    var wards: List[String] = ["A", "B", "C"]
    var reach: List[Float64] = [0.06, 0.09, 0.05]
    for w in range(3):
        var ward = _evolve(noise, source, reach[w])
        var pair = _evolve(noise, ward, 0.03)
        for p in range(4):
            var parent = pair.copy() if p < 2 else ward.copy()
            var patient = _evolve(noise, parent, 0.01 + 0.015 * Float64(p))
            names.append("Ward " + wards[w] + " patient " + String(p + 1))
            sequences.append(_text(patient))
    var distances = kimura_distances(
        alignment_distances(sequences, -10.0, -0.5)
    )
    var tree = midpoint_root(neighbor_joining(distances, names))
    var drawing = tree_image(tree, 720, 420, 220)
    var style = TextStyle(12.0, Rgb(30, 30, 34), 1.0, 0, 0, 0, 0)
    for leaf in range(tree.leaf_count()):
        draw_styled(
            drawing.image,
            Float32(drawing.xs[leaf]),
            Float32(drawing.ys[leaf]) - 6.0,
            names[leaf],
            style,
        )
    Path(destination).write_bytes(encode(drawing.image))
    print(tree.newick())
    print("Wrote", destination)
