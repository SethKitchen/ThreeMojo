# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Distance trees: p-distances, Kimura's distance, neighbor joining, UPGMA,
Newick text and drawings.

`assets/phylogeny/phylogeny_expected.txt` holds eight synthetic sequences
with the trees of Biopython and scipy. See
`assets/phylogeny/make_phylogeny.py`.
"""

from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from extensions.molecule.phylogeny import (
    MAX_TAXA,
    PhyloTree,
    alignment_distances,
    midpoint_root,
    kimura_distances,
    neighbor_joining,
    tree_image,
    upgma,
)
from extensions.numerics.dense import DenseMatrix
from render.framebuffer import Color, Framebuffer
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _matrix(rows: List[List[Float64]]) raises -> DenseMatrix:
    var n = len(rows)
    var out = DenseMatrix(n, n)
    for i in range(n):
        for j in range(n):
            out.set(i, j, rows[i][j])
    return out^


def _names(count: Int) -> List[String]:
    var out = List[String]()
    for i in range(count):
        out.append(String(chr(65 + i)))
    return out^


def _depth(tree: PhyloTree, leaf: Int) -> Float64:
    var total = 0.0
    var node = leaf
    while tree.parents[node] >= 0:
        total += tree.lengths[node]
        node = tree.parents[node]
    return total


def _is_dark(image: Framebuffer, x: Int, y: Int) raises:
    var probe = Framebuffer(1, 1, Color(0, 0, 0))
    draw_line(probe, 0, 0, 0, 0, Rgba(0.24, 0.24, 0.26, 1))
    assert_equal(image.pixels[(y * image.width + x) * 4], probe.pixels[0])


def test_against_references() raises:
    var names = List[String]()
    var sequences = List[String]()
    var rows = Dict[String, List[List[Float64]]]()
    var text = open("assets/phylogeny/phylogeny_expected.txt", "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        var head = String(parts[0])
        if head == "sequence":
            names.append(String(parts[1]))
            sequences.append(String(parts[2]))
            continue
        var values = List[Float64]()
        for at in range(1, len(parts)):
            values.append(atof(String(parts[at])))
        if head not in rows:
            rows[head] = List[List[Float64]]()
        rows[head].append(values^)
    assert_equal(len(names), 8)
    var p = alignment_distances(sequences, -10.0, -0.5)
    var kimura = kimura_distances(p)
    var joined = neighbor_joining(p, names)
    var clock = upgma(p, names)
    for i in range(8):
        for j in range(8):
            assert_almost_equal(p.get(i, j), rows["p"][i][j], atol=1e-15)
            assert_almost_equal(
                kimura.get(i, j), rows["kimura"][i][j], atol=1e-14
            )
            assert_almost_equal(
                joined.path_length(i, j), rows["nj"][i][j], atol=1e-13
            )
            assert_almost_equal(
                clock.path_length(i, j), rows["upgma"][i][j], atol=1e-14
            )
    assert_equal(len(joined.leaf_order()), 8)
    assert_true(joined.newick().endswith(";"))
    # Rooted at the midpoint, each leaf is as deep as Biopython puts it, and
    # the paths do not change.
    var rooted = midpoint_root(joined)
    for i in range(8):
        assert_almost_equal(
            _depth(rooted, i), rows["midpoint"][0][i], atol=1e-14
        )
        for j in range(8):
            assert_almost_equal(
                rooted.path_length(i, j), rows["nj"][i][j], atol=1e-13
            )


def test_exact_trees() raises:
    # Distances of the tree ((A:1,B:2):3,(C:4,D:5)) give it back.
    var additive = _matrix(
        [
            [0.0, 3.0, 8.0, 9.0],
            [3.0, 0.0, 9.0, 10.0],
            [8.0, 9.0, 0.0, 9.0],
            [9.0, 10.0, 9.0, 0.0],
        ]
    )
    var joined = neighbor_joining(additive, _names(4))
    for i in range(4):
        for j in range(4):
            assert_almost_equal(
                joined.path_length(i, j), additive.get(i, j), atol=1e-14
            )
    # The longest path, B to D, is 10 long, and its middle is the node over
    # C and D.
    var rooted = midpoint_root(joined)
    assert_almost_equal(_depth(rooted, 1), 5.0, atol=1e-14)
    assert_almost_equal(_depth(rooted, 3), 5.0, atol=1e-14)
    assert_almost_equal(_depth(rooted, 0), 4.0, atol=1e-14)
    assert_almost_equal(_depth(rooted, 2), 4.0, atol=1e-14)
    with assert_raises(contains="needs a root"):
        _ = midpoint_root(PhyloTree(_names(3)))
    # A clock: A and B 2 apart, C and D 4 apart, and 6 between the pairs.
    var clock = upgma(
        _matrix(
            [
                [0.0, 2.0, 6.0, 6.0],
                [2.0, 0.0, 6.0, 6.0],
                [6.0, 6.0, 0.0, 4.0],
                [6.0, 6.0, 4.0, 0.0],
            ]
        ),
        _names(4),
    )
    assert_equal(clock.newick(), "((D:2.0,C:2.0):1.0,(B:1.0,A:1.0):2.0):0.0;")
    var order = clock.leaf_order()
    assert_equal(order[0], 3)
    assert_equal(order[3], 0)
    # Two sequences join half way.
    var pair = neighbor_joining(_matrix([[0.0, 0.4], [0.4, 0.0]]), _names(2))
    assert_equal(pair.newick(), "(A:0.2,B:0.2):0.0;")
    with assert_raises(contains="no leaf of that index"):
        _ = pair.path_length(0, 2)
    with assert_raises(contains="no leaf of that index"):
        _ = pair.path_length(-1, 0)
    with assert_raises(contains="no leaf of that index"):
        _ = pair.path_length(2, 0)
    with assert_raises(contains="no leaf of that index"):
        _ = pair.path_length(0, -1)


def test_image() raises:
    var clock = upgma(
        _matrix(
            [
                [0.0, 2.0, 6.0, 6.0],
                [2.0, 0.0, 6.0, 6.0],
                [6.0, 6.0, 0.0, 4.0],
                [6.0, 6.0, 4.0, 0.0],
            ]
        ),
        _names(4),
    )
    var drawing = tree_image(clock, 200, 100, 50)
    # The leaves share a depth of 3: 142 pixels from x = 4. Rows are 28 apart.
    assert_equal(drawing.xs[0], 150)
    assert_equal(drawing.ys[3], 8)
    assert_equal(drawing.ys[0], 92)
    _is_dark(drawing.image, 100, 8)
    _is_dark(drawing.image, 4, 50)
    with assert_raises(contains="64 to 4096"):
        _ = tree_image(clock, 63, 100, 0)
    with assert_raises(contains="64 to 4096"):
        _ = tree_image(clock, 100, 4097, 0)
    with assert_raises(contains="64 to 4096"):
        _ = tree_image(clock, 4097, 100, 0)
    with assert_raises(contains="64 to 4096"):
        _ = tree_image(clock, 100, 63, 0)
    with assert_raises(contains="label space"):
        _ = tree_image(clock, 200, 100, -1)
    with assert_raises(contains="label space"):
        _ = tree_image(clock, 200, 100, 101)


def test_errors() raises:
    with assert_raises(contains="2 to 1000 sequences"):
        _ = alignment_distances(["ACD"], -10.0, -0.5)
    var many = List[String](length=MAX_TAXA + 1, fill="A")
    with assert_raises(contains="2 to 1000 sequences"):
        _ = alignment_distances(many, -10.0, -0.5)
    var bad: List[Float64] = [-0.1, nan[DType.float64](), inf[DType.float64]()]
    for v in bad:
        with assert_raises(contains="finite and 0 or more"):
            _ = kimura_distances(_matrix([[0.0, v], [v, 0.0]]))
    with assert_raises(contains="no Kimura distance"):
        _ = kimura_distances(_matrix([[0.0, 0.9], [0.9, 0.0]]))
    var two = _matrix([[0.0, 1.0], [1.0, 0.0]])
    with assert_raises(contains="2 to 1000 named rows"):
        _ = upgma(two, _names(1))
    with assert_raises(contains="2 to 1000 named rows"):
        _ = upgma(DenseMatrix(MAX_TAXA + 1, MAX_TAXA + 1), _names(MAX_TAXA + 1))
    with assert_raises(contains="2 to 1000 named rows"):
        _ = upgma(two, _names(3))
    with assert_raises(contains="2 to 1000 named rows"):
        _ = upgma(DenseMatrix(2, 3), _names(2))
    var cases: List[Float64] = [-1.0, inf[DType.float64]()]
    for v in cases:
        with assert_raises(contains="symmetric, finite"):
            _ = neighbor_joining(_matrix([[0.0, v], [v, 0.0]]), _names(2))
    with assert_raises(contains="symmetric, finite"):
        _ = neighbor_joining(_matrix([[0.0, 1.0], [2.0, 0.0]]), _names(2))
    with assert_raises(contains="0 on its diagonal"):
        _ = neighbor_joining(_matrix([[1.0, 1.0], [1.0, 0.0]]), _names(2))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
