# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The minimum degree ordering against the genmmd routine of EPANET 2.3.6.

`assets/epanet/genmmd.expected` holds graphs of many shapes and the
ordering that the C routine gives for each, from
`assets/epanet/make_epanet_genmmd.py`. The port must give the same
permutation and the same inverse permutation for each graph.
"""

from std.testing import TestSuite, assert_equal

from extensions.epanet.genmmd import genmmd


def _ints(line: String) raises -> List[Int]:
    """Return the numbers after the first word of a line, from index 1.

    Index 0 holds 0, so that the list starts at index 1 as in EPANET.
    """
    var out: List[Int] = [0]
    var first = True
    for w in line.split():
        if first:
            first = False
            continue
        out.append(Int(String(w)))
    return out^


def _check_graphs(first: Int, last: Int) raises:
    """Order each graph from `first` to `last` - 1 and compare."""
    var text = open("assets/epanet/genmmd.expected", "r").read()
    var lines = text.split("\n")
    var count = 0
    var i = 0
    while i + 4 < len(lines):
        var line = String(lines[i])
        var head = line.split()
        if len(head) != 3 or String(head[0]) != "graph":
            raise Error(String("bad line ", i + 1, ": ", lines[i]))
        if count >= first and count < last:
            var n = Int(String(head[2]))
            var xadj = _ints(String(lines[i + 1]))
            var adjncy = _ints(String(lines[i + 2]))
            adjncy.append(0)
            var perm = _ints(String(lines[i + 3]))
            var invp = _ints(String(lines[i + 4]))
            var got_perm = List[Int](length=n + 2, fill=0)
            var got_invp = List[Int](length=n + 2, fill=0)
            for k in range(n + 2):
                got_perm[k] = k
                got_invp[k] = k
            genmmd(n, xadj, adjncy, got_invp, got_perm)
            for k in range(1, n + 1):
                if got_perm[k] != perm[k] or got_invp[k] != invp[k]:
                    raise Error(
                        String(
                            head[1],
                            " position ",
                            k,
                            ": perm ",
                            got_perm[k],
                            " for ",
                            perm[k],
                            ", invp ",
                            got_invp[k],
                            " for ",
                            invp[k],
                        )
                    )
        count += 1
        i += 5
    assert_equal(count, 291)


def test_small_shapes() raises:
    """Paths, stars, rings, wheels, and complete and bipartite graphs."""
    _check_graphs(0, 59)


def test_grids_and_cubes() raises:
    """Grids of 2 x 2 to 8 x 9 nodes, and cubes of 1 to 5 dimensions."""
    _check_graphs(59, 99)


def test_trees() raises:
    """Random trees."""
    _check_graphs(99, 139)


def test_random_graphs() raises:
    """The first half of the random graphs."""
    _check_graphs(139, 199)


def test_more_random_graphs() raises:
    """The second half of the random graphs."""
    _check_graphs(199, 259)


def test_graphs_in_parts() raises:
    """Graphs in two parts, and graphs with isolated nodes."""
    _check_graphs(259, 291)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
