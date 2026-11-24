# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the orderings that the genmmd routine of EPANET gives for graphs.

    python3 make_epanet_genmmd.py LIBRARY > genmmd.expected

LIBRARY is the EPANET library that `make_epanet.py` names. The script
makes small graphs of many shapes: paths, stars, rings, complete and
bipartite graphs, grids, trees, random graphs, and graphs in parts. It
calls `genmmd` for each graph with the arguments that `createsparse`
gives: `delta = -1` and `maxint = INT_MAX`.

For each graph the output has five lines:

    graph NAME N
    xadj X1 ... XN+1
    adjncy A1 ... AM
    perm P1 ... PN
    invp I1 ... IN

The arrays start at index 1, as in EPANET. `adjncy` is the input, before
`genmmd` changes it.
"""

import ctypes
import sys


class Lcg:
    """A small random number generator that gives the same numbers on
    every Python version."""

    def __init__(self, seed):
        self.state = seed

    def next(self, n):
        """Return a number from 0 to n - 1."""
        self.state = (self.state * 1103515245 + 12345) % 2147483648
        return (self.state >> 8) % n


def graph(n, edges):
    """Return the adjacency lists of a simple graph with nodes 1 to n."""
    adj = [[] for _ in range(n + 1)]
    for i, j in edges:
        if i != j and j not in adj[i]:
            adj[i].insert(0, j)
            adj[j].insert(0, i)
    return adj


def shapes():
    """Return the name, the node count and the edges of each graph."""
    out = []
    for n in range(1, 8):
        out.append(("path%d" % n, n, [(i, i + 1) for i in range(1, n)]))
        out.append(("star%d" % n, n, [(1, i) for i in range(2, n + 1)]))
        out.append(("complete%d" % n, n, [(i, j) for i in range(1, n + 1) for j in range(i + 1, n + 1)]))
    for n in range(3, 10):
        out.append(("ring%d" % n, n, [(i, i % n + 1) for i in range(1, n + 1)]))
        out.append(("wheel%d" % n, n + 1, [(i, i % n + 1) for i in range(1, n + 1)] + [(n + 1, i) for i in range(1, n + 1)]))
    for a in range(1, 5):
        for b in range(1, 7):
            out.append(("bipartite%dx%d" % (a, b), a + b, [(i, a + j) for i in range(1, a + 1) for j in range(1, b + 1)]))
    for r in range(2, 9):
        for c in range(r, 10):
            e = []
            for i in range(r):
                for j in range(c):
                    k = i * c + j + 1
                    if j + 1 < c:
                        e.append((k, k + 1))
                    if i + 1 < r:
                        e.append((k, k + c))
            out.append(("grid%dx%d" % (r, c), r * c, e))
    for d in range(1, 6):
        n = 2 ** d
        out.append(("cube%d" % d, n, [(i + 1, (i ^ (1 << b)) + 1) for i in range(n) for b in range(d) if i < i ^ (1 << b)]))
    rng = Lcg(20261124)
    for t in range(40):
        n = 2 + rng.next(40)
        out.append(("tree%d" % t, n, [(i, 1 + rng.next(i - 1)) for i in range(2, n + 1)]))
    for t in range(120):
        n = 2 + rng.next(60)
        p = 1 + rng.next(40)
        e = [(i, j) for i in range(1, n + 1) for j in range(i + 1, n + 1) if rng.next(100) < p]
        out.append(("random%d" % t, n, e))
    for t in range(30):
        n = 4 + rng.next(30)
        cut = 1 + rng.next(n - 1)
        e = [(i, j) for i in range(1, n + 1) for j in range(i + 1, n + 1)
             if (i <= cut) == (j <= cut) and rng.next(100) < 30]
        out.append(("parts%d" % t, n, e))
    out.append(("isolated5", 5, []))
    out.append(("isolated_and_path", 6, [(2, 3), (3, 4)]))
    return out


def main():
    """Write the orderings of the graphs."""
    lib = ctypes.CDLL(sys.argv[1])
    for name, n, edges in shapes():
        adj = graph(n, edges)
        xadj = [0, 1]
        adjncy = [0]
        for k in range(1, n + 1):
            adjncy += adj[k]
            xadj.append(len(adjncy))
        ints = ctypes.c_int * (n + 2)
        cx = (ctypes.c_int * len(xadj))(*xadj)
        ca = (ctypes.c_int * (len(adjncy) + 1))(*adjncy)
        invp = ints(*range(n + 2))
        perm = ints(*range(n + 2))
        work = [ints() for _ in range(4)]
        neqns = ctypes.c_int(n)
        delta = ctypes.c_int(-1)
        maxint = ctypes.c_int(2147483647)
        nofsub = ctypes.c_int(0)
        lib.genmmd(ctypes.byref(neqns), cx, ca, invp, perm, ctypes.byref(delta), work[0], work[1], work[2],
                   work[3], ctypes.byref(maxint), ctypes.byref(nofsub))
        print("graph", name, n)
        print(" ".join(["xadj"] + [str(x) for x in xadj[1:]]))
        print(" ".join(["adjncy"] + [str(x) for x in adjncy[1:]]))
        print(" ".join(["perm"] + [str(perm[i]) for i in range(1, n + 1)]))
        print(" ".join(["invp"] + [str(invp[i]) for i in range(1, n + 1)]))


main()
