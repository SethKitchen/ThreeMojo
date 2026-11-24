# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from genmmd.c of OWA EPANET 2.3.6. Copyright (c) 2023 the EPANET
# contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The multiple minimum degree ordering of EPANET (genmmd.c).

The C file is a translation of the Fortran routine GENMMD of George and
Liu, with its labels kept as gotos. Here each goto loop is a `while`
loop, and the arrays start at index 1 as in the C code.

EPANET calls the routine with `delta = -1`, so each round eliminates one
node and then updates the degrees. This port is that case. The C code
also resets its tags when a tag reaches INT_MAX. A 64-bit tag cannot
reach that limit on a network that fits in memory, so the port has no
reset.

The C code also has tests that only multiple elimination (`delta >= 0`)
needs, for a node that an earlier elimination of the same round has
changed. With one elimination in each round, these facts hold, and the
port has no such tests:

- When a round starts, each node that is not eliminated is in a degree
  list. So `_mmdelm` finds no node with `dbakw` 0, and no node in an
  element's list with `dforw < 0`.
- `_mmdelm` compresses the list of each node that the new element
  reaches, so the lists of the nodes that are not eliminated stay
  symmetric. A node that `_mmdupd` merges lists only its two elements,
  so no other list holds it. A scan of a list therefore marks no node
  twice.
- After `_mmdelm`, each node that the new element reaches has `dbakw`
  0, or `qsize` 0 if it was merged.
- `_mmdelm` puts the new element after the one other entry of a node
  with two neighbors, so that entry comes first.

`tests/test_epanet_genmmd.mojo` checks the port against the C routine on
291 graphs of many shapes.
"""

comptime MAXINT = 2147483647


def genmmd(
    neqns: Int,
    xadj: List[Int],
    mut adjncy: List[Int],
    mut invp: List[Int],
    mut perm: List[Int],
):
    """Find a minimum degree ordering of a symmetric graph.

    Args:
        neqns: The number of nodes.
        xadj: The start of the list of each node in `adjncy`. Entry
            `neqns + 1` is one past the end.
        adjncy: The neighbor lists. The routine changes them.
        invp: Receives the inverse permutation, `invp[node] = position`.
        perm: Receives the permutation, `perm[position] = node`.
    """
    if neqns <= 0:
        return
    var dhead = List[Int](length=neqns + 2, fill=0)
    var qsize = List[Int](length=neqns + 2, fill=0)
    var llist = List[Int](length=neqns + 2, fill=0)
    var marker = List[Int](length=neqns + 2, fill=0)
    _mmdint(neqns, xadj, dhead, invp, perm, qsize, llist, marker)
    var num = 1
    var nextmd = dhead[1]
    while nextmd > 0:
        var mdnode = nextmd
        nextmd = invp[mdnode]
        marker[mdnode] = MAXINT
        invp[mdnode] = -num
        num += 1
    if num <= neqns:
        var tag = 1
        dhead[1] = 0
        var mdeg = 2
        while True:
            while dhead[mdeg] <= 0:
                mdeg += 1
            var mdnode = dhead[mdeg]
            nextmd = invp[mdnode]
            dhead[mdeg] = nextmd
            if nextmd > 0:
                perm[nextmd] = -mdeg
            invp[mdnode] = -num
            if num + qsize[mdnode] > neqns:
                break
            tag += 1
            _mmdelm(
                mdnode,
                xadj,
                adjncy,
                dhead,
                invp,
                perm,
                qsize,
                llist,
                marker,
                tag,
            )
            num += qsize[mdnode]
            llist[mdnode] = 0
            if num > neqns:
                break
            _mmdupd(
                mdnode,
                neqns,
                xadj,
                adjncy,
                mdeg,
                dhead,
                invp,
                perm,
                qsize,
                llist,
                marker,
                tag,
            )
    _mmdnum(neqns, perm, invp, qsize)


def _mmdint(
    neqns: Int,
    xadj: List[Int],
    mut dhead: List[Int],
    mut dforw: List[Int],
    mut dbakw: List[Int],
    mut qsize: List[Int],
    mut llist: List[Int],
    mut marker: List[Int],
):
    """Put each node in the degree list of its degree."""
    for node in range(1, neqns + 1):  # pragma: no branch
        dhead[node] = 0
        qsize[node] = 1
        marker[node] = 0
        llist[node] = 0
    for node in range(1, neqns + 1):  # pragma: no branch
        var ndeg = xadj[node + 1] - xadj[node] + 1
        var fnode = dhead[ndeg]
        dforw[node] = fnode
        dhead[ndeg] = node
        if fnode > 0:
            dbakw[fnode] = node
        dbakw[node] = -ndeg


def _mmdelm(
    mdnode: Int,
    xadj: List[Int],
    mut adjncy: List[Int],
    mut dhead: List[Int],
    mut dforw: List[Int],
    mut dbakw: List[Int],
    mut qsize: List[Int],
    mut llist: List[Int],
    mut marker: List[Int],
    tag: Int,
):
    """Eliminate a node of minimum degree and update the quotient graph."""
    marker[mdnode] = tag
    var istrt = xadj[mdnode]
    var istop = xadj[mdnode + 1] - 1
    var elmnt = 0
    var rloc = istrt
    var rlmt = istop
    for i in range(istrt, istop + 1):  # pragma: no branch
        var nabor = adjncy[i]
        if nabor == 0:
            break
        marker[nabor] = tag
        if dforw[nabor] < 0:
            llist[nabor] = elmnt
            elmnt = nabor
        else:
            adjncy[rloc] = nabor
            rloc += 1
    while elmnt > 0:
        adjncy[rlmt] = -elmnt
        var link = elmnt
        var walking = True
        while walking:
            walking = False
            var jstrt = xadj[link]
            var jstop = xadj[link + 1] - 1
            for j in range(jstrt, jstop + 1):  # pragma: no branch
                var node = adjncy[j]
                link = -node
                if node < 0:
                    walking = True
                    break
                if node == 0:
                    break
                if marker[node] >= tag:
                    continue
                marker[node] = tag
                while rloc >= rlmt:
                    var spill = -adjncy[rlmt]
                    rloc = xadj[spill]
                    rlmt = xadj[spill + 1] - 1
                adjncy[rloc] = node
                rloc += 1
        elmnt = llist[elmnt]
    if rloc <= rlmt:
        adjncy[rloc] = 0
    var link = mdnode
    var walking = True
    while walking:
        walking = False
        var ristrt = xadj[link]
        var ristop = xadj[link + 1] - 1
        for i in range(ristrt, ristop + 1):  # pragma: no branch
            var rnode = adjncy[i]
            link = -rnode
            if rnode < 0:
                walking = True
                break
            if rnode == 0:
                return
            var pvnode = dbakw[rnode]
            if pvnode != -MAXINT:
                var nxnode = dforw[rnode]
                if nxnode > 0:
                    dbakw[nxnode] = pvnode
                if pvnode > 0:
                    dforw[pvnode] = nxnode
                else:
                    dhead[-pvnode] = nxnode
            var jstrt = xadj[rnode]
            var jstop = xadj[rnode + 1] - 1
            var xqnbr = jstrt
            for j in range(jstrt, jstop + 1):  # pragma: no branch
                var nabor = adjncy[j]
                if nabor == 0:
                    break
                if marker[nabor] >= tag:
                    continue
                adjncy[xqnbr] = nabor
                xqnbr += 1
            var nqnbrs = xqnbr - jstrt
            if nqnbrs <= 0:
                qsize[mdnode] += qsize[rnode]
                qsize[rnode] = 0
                marker[rnode] = MAXINT
                dforw[rnode] = -mdnode
                dbakw[rnode] = -MAXINT
            else:
                dforw[rnode] = nqnbrs + 1
                dbakw[rnode] = 0
                adjncy[xqnbr] = mdnode
                xqnbr += 1
                if xqnbr <= jstop:
                    adjncy[xqnbr] = 0


def _mmdupd(
    ehead: Int,
    neqns: Int,
    xadj: List[Int],
    adjncy: List[Int],
    mut mdeg: Int,
    mut dhead: List[Int],
    mut dforw: List[Int],
    mut dbakw: List[Int],
    mut qsize: List[Int],
    mut llist: List[Int],
    mut marker: List[Int],
    mut tag: Int,
):
    """Update the degrees of the nodes next to the eliminated nodes."""
    var mdeg0 = mdeg - 1
    var elmnt = ehead
    while elmnt > 0:
        var mtag = tag + mdeg0
        var q2head = 0
        var qxhead = 0
        var deg0 = 0
        var link = elmnt
        var walking = True
        while walking:
            walking = False
            var istrt = xadj[link]
            var istop = xadj[link + 1] - 1
            for i in range(istrt, istop + 1):  # pragma: no branch
                var enode = adjncy[i]
                link = -enode
                if enode < 0:
                    walking = True
                    break
                if enode == 0:
                    break
                if qsize[enode] == 0:
                    continue
                deg0 += qsize[enode]
                marker[enode] = mtag
                if dforw[enode] == 2:
                    llist[enode] = q2head
                    q2head = enode
                else:
                    llist[enode] = qxhead
                    qxhead = enode
        var enode = q2head
        var iq2 = True
        while True:
            if enode <= 0:
                if iq2:
                    enode = qxhead
                    iq2 = False
                    continue
                break
            if dbakw[enode] != 0:
                enode = llist[enode]
                continue
            tag += 1
            var deg = deg0
            if iq2:
                var istrt = xadj[enode]
                var nabor = adjncy[istrt]
                link = nabor
                if dforw[nabor] >= 0:
                    deg += qsize[nabor]
                else:
                    walking = True
                    while walking:
                        walking = False
                        var jstrt = xadj[link]
                        var jstop = xadj[link + 1] - 1
                        for i in range(jstrt, jstop + 1):  # pragma: no branch
                            var node = adjncy[i]
                            link = -node
                            if node == enode:
                                continue
                            if node < 0:
                                walking = True
                                break
                            if node == 0:
                                break
                            if qsize[node] == 0:
                                continue
                            if marker[node] < tag:
                                marker[node] = tag
                                deg += qsize[node]
                            elif dbakw[node] == 0:
                                if dforw[node] == 2:
                                    qsize[enode] += qsize[node]
                                    qsize[node] = 0
                                    marker[node] = MAXINT
                                    dforw[node] = -enode
                                    dbakw[node] = -MAXINT
                                else:
                                    dbakw[node] = -MAXINT
            else:
                var istrt = xadj[enode]
                var istop = xadj[enode + 1] - 1
                for i in range(istrt, istop + 1):  # pragma: no branch
                    var nabor = adjncy[i]
                    if nabor == 0:
                        break
                    marker[nabor] = tag
                    link = nabor
                    if dforw[nabor] >= 0:
                        deg += qsize[nabor]
                        continue
                    walking = True
                    while walking:
                        walking = False
                        var jstrt = xadj[link]
                        var jstop = xadj[link + 1] - 1
                        for j in range(jstrt, jstop + 1):  # pragma: no branch
                            var node = adjncy[j]
                            link = -node
                            if node < 0:
                                walking = True
                                break
                            if node == 0:
                                break
                            if marker[node] < tag:
                                marker[node] = tag
                                deg += qsize[node]
            deg = deg - qsize[enode] + 1
            var fnode = dhead[deg]
            dforw[enode] = fnode
            dbakw[enode] = -deg
            if fnode > 0:
                dbakw[fnode] = enode
            dhead[deg] = enode
            if deg < mdeg:
                mdeg = deg
            enode = llist[enode]
        tag = mtag
        elmnt = llist[elmnt]


def _mmdnum(
    neqns: Int, mut perm: List[Int], mut invp: List[Int], qsize: List[Int]
):
    """Number the nodes from the elimination forest."""
    for node in range(1, neqns + 1):  # pragma: no branch
        if qsize[node] <= 0:
            perm[node] = invp[node]
        else:
            perm[node] = -invp[node]
    for node in range(1, neqns + 1):  # pragma: no branch
        if perm[node] > 0:
            continue
        var father = node
        while perm[father] <= 0:
            father = -perm[father]
        var root = father
        var num = perm[root] + 1
        invp[node] = -num
        perm[root] = num
        father = node
        while True:
            var nextf = -perm[father]
            if nextf <= 0:
                break
            perm[father] = -root
            father = nextf
    for node in range(1, neqns + 1):  # pragma: no branch
        var num = -invp[node]
        invp[node] = num
        perm[num] = node
