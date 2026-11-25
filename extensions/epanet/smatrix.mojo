# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from smatrix.c and project.c of OWA EPANET 2.3.6. Copyright (c)
# 2023 the EPANET contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The sparse matrix of the hydraulic equations and its Cholesky solver.

`createsparse` orders the junctions to keep the factor sparse, finds the
fill-in of the factor, and stores the position of each nonzero.
`linsolve` factors the matrix and solves the equations. Each adjacency
list keeps its first entry at index 0, as the head of the C list.
"""

from std.math import sqrt

from extensions.epanet.cmath import mul
from extensions.epanet.genmmd import genmmd
from extensions.epanet.model import AdjItem, Network, Project, Smatrix


def buildadjlists(mut net: Network):
    """Build the list of the links at each node.

    Args:
        net: The network. Its `adjlist` is replaced.
    """
    net.adjlist = List[List[AdjItem]]()
    for _ in range(net.nnodes + 1):  # pragma: no branch
        net.adjlist.append(List[AdjItem]())
    for k in range(1, net.nlinks + 1):
        var i = net.link[k].n1
        var j = net.link[k].n2
        net.adjlist[i].insert(0, AdjItem(j, k))
        net.adjlist[j].insert(0, AdjItem(i, k))


def unlinked(net: Network, mut errors: List[String]) -> Int:
    """Check that each junction has a link.

    Args:
        net: The network, with its adjacency lists.
        errors: Receives a message for each junction with no link, for
            up to 10 junctions.

    Returns:
        0, or error 233 if a junction has no link.
    """
    var count = 0
    for i in range(1, net.njuncs + 1):
        if len(net.adjlist[i]) == 0:
            count += 1
            errors.append(
                String(
                    "Error 234: network has an unconnected node with ID: ",
                    net.node[i].id,
                )
            )
        if count >= 10:
            break
    if count > 0:
        return 233
    return 0


def _linked(adj: List[List[AdjItem]], i: Int, j: Int) -> Bool:
    """Return True if node i has node j in its list."""
    for a in adj[i]:  # pragma: no branch
        if a.node == j:
            return True
    return False


def createsparse(mut pr: Project):
    """Make the sparse structure of the matrix of the hydraulic equations.

    Args:
        pr: The project, after its network is read.
    """
    var nnodes = pr.net.nnodes
    var nlinks = pr.net.nlinks
    var njuncs = pr.net.njuncs
    ref sm = pr.hyd.sm
    sm.order = List[Int](length=nnodes + 1, fill=0)
    sm.row = List[Int](length=nnodes + 1, fill=0)
    sm.ndx = List[Int](length=nlinks + 1, fill=0)
    # Local adjacency lists, with parallel links removed.
    var adj = List[List[AdjItem]]()
    for _ in range(nnodes + 1):  # pragma: no branch
        adj.append(List[AdjItem]())
    for k in range(1, nlinks + 1):
        var i = pr.net.link[k].n1
        var j = pr.net.link[k].n2
        var pmark = False
        sm.ndx[k] = k
        for a in adj[i]:
            if a.node == j:
                sm.ndx[k] = a.link
                pmark = True
                break
        adj[i].insert(0, AdjItem(0 if pmark else j, k))
        adj[j].insert(0, AdjItem(0 if pmark else i, k))
    for i in range(1, nnodes + 1):  # pragma: no branch
        var kept = List[AdjItem]()
        for a in adj[i]:
            if a.node != 0:
                kept.append(a.copy())
        adj[i] = kept^
    # From here on, each node in a list is greater than 0.
    # Reorder the junctions to keep the factor sparse.
    for k in range(1, nnodes + 1):  # pragma: no branch
        sm.row[k] = k
        sm.order[k] = k
    var adjncy = List[Int](length=2 * nlinks + 2, fill=0)
    var xadj = List[Int](length=njuncs + 2, fill=0)
    xadj[1] = 1
    var m = 1
    for k in range(1, njuncs + 1):
        for a in adj[k]:
            if a.node <= njuncs:
                adjncy[m] = a.node
                m += 1
        xadj[k + 1] = m
    genmmd(njuncs, xadj, adjncy, sm.row, sm.order)
    # Symbolic factorization: add the fill-in links.
    sm.ncoeffs = nlinks
    var degree = List[Int](length=nnodes + 1, fill=0)
    for k in range(1, njuncs + 1):
        degree[k] = len(adj[k])
    for k in range(1, njuncs + 1):
        var knode = sm.order[k]
        var p = 0
        while p < len(adj[knode]):
            var node = adj[knode][p].node
            if degree[node] > 0:
                degree[node] -= 1
                var inode = node
                var q = p + 1
                while q < len(adj[knode]):
                    var jnode = adj[knode][q].node
                    if degree[jnode] > 0:
                        if not _linked(adj, inode, jnode):
                            sm.ncoeffs += 1
                            adj[inode].insert(0, AdjItem(jnode, sm.ncoeffs))
                            adj[jnode].insert(0, AdjItem(inode, sm.ncoeffs))
                            degree[inode] += 1
                            degree[jnode] += 1
                    q += 1
            p += 1
        degree[knode] = 0
    # Store the row of each nonzero of each column of the factor.
    var n = njuncs
    sm.xlnz = List[Int](length=n + 2, fill=0)
    sm.nzsub = List[Int](length=sm.ncoeffs + 2, fill=0)
    sm.lnz = List[Int](length=sm.ncoeffs + 2, fill=0)
    var kk = 0
    sm.xlnz[1] = 1
    for i in range(1, n + 1):
        var count = 0
        var ii = sm.order[i]
        for a in adj[ii]:
            var j = sm.row[a.node]
            if j > i and j <= n:
                count += 1
                kk += 1
                sm.nzsub[kk] = j
                sm.lnz[kk] = a.link
        sm.xlnz[i + 1] = sm.xlnz[i] + count
    _sortsparse(sm, n)
    sm.aij = List[Float64](length=sm.ncoeffs + 1, fill=0.0)
    sm.aii = List[Float64](length=nnodes + 1, fill=0.0)
    sm.f = List[Float64](length=nnodes + 1, fill=0.0)
    sm.temp = List[Float64](length=nnodes + 1, fill=0.0)
    sm.link = List[Int](length=nnodes + 1, fill=0)
    sm.first = List[Int](length=nnodes + 1, fill=0)
    buildadjlists(pr.net)


def _sortsparse(mut sm: Smatrix, n: Int):
    """Put the row indices of each column in ascending order."""
    var nzt = List[Int](length=n + 2, fill=0)
    for i in range(1, n + 1):
        for k in range(sm.xlnz[i], sm.xlnz[i + 1]):
            nzt[sm.nzsub[k]] += 1
    var xlnzt = List[Int](length=n + 2, fill=0)
    xlnzt[1] = 1
    for i in range(1, n + 1):
        xlnzt[i + 1] = xlnzt[i] + nzt[i]
    var nzsubt = List[Int](length=sm.ncoeffs + 2, fill=0)
    var lnzt = List[Int](length=sm.ncoeffs + 2, fill=0)
    _transpose(n, sm.xlnz, sm.nzsub, sm.lnz, xlnzt, nzsubt, lnzt, nzt)
    _transpose(n, xlnzt, nzsubt, lnzt, sm.xlnz, sm.nzsub, sm.lnz, nzt)


def _transpose(
    n: Int,
    il: List[Int],
    jl: List[Int],
    xl: List[Int],
    ilt: List[Int],
    mut jlt: List[Int],
    mut xlt: List[Int],
    mut nzt: List[Int],
):
    """Find the sparse storage of the transpose of a matrix."""
    for i in range(1, n + 1):
        nzt[i] = 0
    for i in range(1, n + 1):
        for k in range(il[i], il[i + 1]):
            var j = jl[k]
            var kk = ilt[j] + nzt[j]
            jlt[kk] = i
            xlt[kk] = xl[k]
            nzt[j] += 1


def linsolve(mut sm: Smatrix, n: Int) -> Int:
    """Solve the equations by a Cholesky factorization of the matrix.

    Args:
        sm: The matrix. `f` receives the solution.
        n: The number of equations.

    Returns:
        0, or the index of the equation that makes the matrix
        ill-conditioned.
    """
    for i in range(n + 1):  # pragma: no branch
        sm.temp[i] = 0.0
        sm.link[i] = 0
        sm.first[i] = 0
    for j in range(1, n + 1):
        var diagj = 0.0
        var k = sm.link[j]
        while k != 0:
            var newk = sm.link[k]
            var kfirst = sm.first[k]
            var ljk = sm.aij[sm.lnz[kfirst]]
            diagj += mul(ljk, ljk)
            var istrt = kfirst + 1
            var istop = sm.xlnz[k + 1] - 1
            if istop >= istrt:
                sm.first[k] = istrt
                var isub = sm.nzsub[istrt]
                sm.link[k] = sm.link[isub]
                sm.link[isub] = k
                for i in range(istrt, istop + 1):  # pragma: no branch
                    isub = sm.nzsub[i]
                    sm.temp[isub] += mul(sm.aij[sm.lnz[i]], ljk)
            k = newk
        diagj = sm.aii[j] - diagj
        if diagj <= 0.0:
            return j
        diagj = sqrt(diagj)
        sm.aii[j] = diagj
        var istrt = sm.xlnz[j]
        var istop = sm.xlnz[j + 1] - 1
        if istop >= istrt:
            sm.first[j] = istrt
            var isub = sm.nzsub[istrt]
            sm.link[j] = sm.link[isub]
            sm.link[isub] = j
            for i in range(istrt, istop + 1):  # pragma: no branch
                isub = sm.nzsub[i]
                var bj = (sm.aij[sm.lnz[i]] - sm.temp[isub]) / diagj
                sm.aij[sm.lnz[i]] = bj
                sm.temp[isub] = 0.0
    for j in range(1, n + 1):
        var bj = sm.f[j] / sm.aii[j]
        sm.f[j] = bj
        for i in range(sm.xlnz[j], sm.xlnz[j + 1]):
            sm.f[sm.nzsub[i]] -= mul(sm.aij[sm.lnz[i]], bj)
    for j in range(n, 0, -1):
        var bj = sm.f[j]
        for i in range(sm.xlnz[j], sm.xlnz[j + 1]):
            bj -= mul(sm.aij[sm.lnz[i]], sm.f[sm.nzsub[i]])
        sm.f[j] = bj / sm.aii[j]
    return 0
