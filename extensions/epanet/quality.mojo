# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from quality.c, qualroute.c and qualreact.c of OWA EPANET 2.3.6.
# Copyright (c) 2023 the EPANET contributors. MIT license: see
# THIRD-PARTY-NOTICES.md.

"""The water quality engine of EPANET (quality.c, qualroute.c, qualreact.c).

The engine moves water through each pipe as a chain of segments, from
the upstream end to the downstream end. Each time step it reacts the
segments, then takes the nodes in flow order: the water that flows into
a node mixes, and the mixture enters the pipes that flow out of it.
Tanks mix by one of four models. The engine reads the hydraulics that
`nexthyd` saved, rounded to single precision as in the C engine.
"""

from extensions.epanet.cmath import cpow, mul
from extensions.epanet.kinds import (
    AGE,
    BIG,
    CHEM,
    CLOSED,
    CONCEN,
    FIFO,
    FLOWPACED,
    FlowDirection,
    GPM_PER_CFS,
    JUNCTION,
    L_PER_FT3,
    MASS,
    MIX1,
    MIX2,
    NEGATIVE,
    NONE,
    PI,
    PIPE,
    POSITIVE,
    RESERVOIR,
    SEC_PER_DAY,
    SETPOINT,
    StatusType,
    TANK,
    TINY,
    TRACE,
    ZERO_FLOW,
)
from extensions.epanet.model import ELEV, Project, QUALITY, Seg

comptime Q_STAGNANT = 0.005 / GPM_PER_CFS


def _sgn(x: Float64) -> Float64:
    """Return -1 for a negative number and 1 otherwise."""
    if x < 0.0:
        return -1.0
    return 1.0


def openqual(mut pr: Project) -> Int:
    """Make the water quality solver.

    The hydraulics come from a run that saved its results, or from the
    hydraulic solver while it is open.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    pr.qual.open_qflag = False
    if not pr.hyd.open_hflag and not pr.save_hflag:
        return 104
    if pr.qual.qualflag == NONE:
        pr.qual.open_qflag = True
        return 0
    # `openhyd` has checked the network and built its adjacency lists,
    # so the checks that EPANET makes when it has no lists are not needed.
    var n = pr.net.nlinks + 1
    pr.qual.flow_dir = List[FlowDirection](length=n, fill=ZERO_FLOW)
    pr.qual.pipe_rate_coeff = List[Float64](length=n, fill=0.0)
    n = pr.net.nlinks + pr.net.ntanks + 1
    pr.qual.first_seg = List[Int](length=n, fill=0)
    pr.qual.last_seg = List[Int](length=n, fill=0)
    pr.qual.sorted_nodes = List[Int](length=pr.net.nnodes + 1, fill=0)
    pr.qual.open_qflag = True
    return 0


def initqual(mut pr: Project):
    """Set the starting state of a water quality run.

    Args:
        pr: The project, after `openqual`.
    """
    pr.times.qtime = 0
    pr.times.htime = 0
    pr.times.rtime = pr.times.rstart
    pr.hyd_file_pos = 0
    for i in range(1, pr.net.nnodes + 1):  # pragma: no branch
        if pr.qual.qualflag == TRACE:
            pr.qual.node_qual[i] = 0.0
        else:
            pr.qual.node_qual[i] = pr.net.node[i].c0
        if pr.net.node[i].has_source:
            pr.net.node[i].source.smass = 0.0
    if pr.qual.qualflag == NONE:
        return
    for i in range(1, pr.net.ntanks + 1):  # pragma: no branch
        pr.net.tank[i].c = pr.qual.node_qual[pr.net.tank[i].node]
        pr.net.tank[i].vq = pr.net.tank[i].v0
    if pr.qual.qualflag == TRACE:
        pr.qual.node_qual[pr.qual.trace_node] = 100.0
    if pr.qual.diffus > 0.0:
        pr.qual.sc = pr.hyd.viscos / pr.qual.diffus
    else:
        pr.qual.sc = 0.0
    pr.qual.bucf = _getucf(pr.qual.bulk_order)
    pr.qual.tucf = _getucf(pr.qual.tank_order)
    pr.qual.reactflag = _setreactflag(pr)
    pr.qual.free_seg = 0
    pr.qual.seg = List[Seg]()
    pr.qual.seg.append(Seg(0.0, 0.0, 0))
    pr.qual.mass_balance.seg_count = 0
    _initsegs(pr)
    for i in range(1, pr.net.nlinks + 1):
        pr.qual.flow_dir[i] = ZERO_FLOW
    pr.qual.wbulk = 0.0
    pr.qual.wwall = 0.0
    pr.qual.wtank = 0.0
    pr.qual.wsource = 0.0
    pr.qual.mass_balance.initial = _findstoredmass(pr)
    pr.qual.mass_balance.inflow = 0.0
    pr.qual.mass_balance.outflow = 0.0
    pr.qual.mass_balance.reacted = 0.0
    pr.qual.mass_balance.final = 0.0
    pr.qual.mass_balance.ratio = 0.0
    pr.qual.mass_balance.seg_count = 0


def _readhyd(mut pr: Project, mut hydtime: Int, mut hydstep: Int) -> Bool:
    """Load the next saved hydraulic step into the hydraulic state."""
    if pr.hyd_file_pos >= len(pr.hyd_file):
        return False
    ref rec = pr.hyd_file[pr.hyd_file_pos]
    hydtime = rec.time
    hydstep = rec.step
    for i in range(1, pr.net.nnodes + 1):  # pragma: no branch
        pr.hyd.node_demand[i] = Float64(rec.demand[i - 1])
        pr.hyd.node_head[i] = Float64(rec.head[i - 1])
    for i in range(1, pr.net.nlinks + 1):
        pr.hyd.link_flow[i] = Float64(rec.flow[i - 1])
        pr.hyd.link_status[i] = StatusType(Int(rec.status[i - 1]))
        pr.hyd.link_setting[i] = Float64(rec.setting[i - 1])
    pr.hyd_file_pos += 1
    return True


def runqual(mut pr: Project, mut t: Int) -> Int:
    """Load the hydraulics of a new hydraulic step when one starts.

    While the hydraulic solver is open, its current state is used, and
    `nexthyd` moves the hydraulic clock. Otherwise the saved hydraulics
    are read.

    Args:
        pr: The project.
        t: Receives the current time, in seconds.

    Returns:
        0, or error 307 if the saved hydraulics run out.
    """
    t = pr.times.qtime
    if pr.times.qtime == pr.times.htime:
        var from_file = not pr.hyd.open_hflag
        var hydtime = 0
        var hydstep = 0
        if from_file:
            if not _readhyd(pr, hydtime, hydstep):
                return 307
            pr.times.htime = hydtime
        if pr.times.htime >= pr.times.rtime:
            pr.times.rtime += pr.times.rstep
        if pr.qual.qualflag != NONE and pr.times.qtime < pr.times.dur:
            if pr.qual.reactflag and pr.qual.qualflag != AGE:
                _ratecoeffs(pr)
            if _flowdirchanged(pr):
                _sortnodes(pr)
        if from_file:
            pr.times.htime = hydtime + hydstep
    return 0


def nextqual(mut pr: Project, mut tstep: Int) -> Int:
    """Move the water quality to the start of the next hydraulic step.

    Args:
        pr: The project.
        tstep: Receives the time step, in seconds. It is 0 at the end.

    Returns:
        0.
    """
    tstep = 0
    var hydstep = 0
    if pr.times.htime <= pr.times.dur:
        hydstep = pr.times.htime - pr.times.qtime
    if pr.qual.qualflag != NONE and hydstep > 0:
        var qtime = 0
        while qtime < hydstep:
            var dt = min(pr.times.qstep, hydstep - qtime)
            qtime += dt
            _transport(pr, dt)
    _evalmassbalance(pr)
    tstep = hydstep
    pr.times.qtime += hydstep
    return 0


def avgqual(pr: Project, k: Int) -> Float64:
    """Return the average quality of the water in a link.

    Args:
        pr: The project.
        k: The link index.

    Returns:
        The volume-weighted mean of the segments, or the mean of the end
        nodes for a link with no segments.
    """
    if pr.qual.qualflag == NONE:
        return 0.0
    var vsum = 0.0
    var msum = 0.0
    if len(pr.qual.first_seg) > k:
        var s = pr.qual.first_seg[k]
        while s != 0:
            ref seg = pr.qual.seg[s]
            vsum += seg.v
            msum += mul(seg.c, seg.v)
            s = seg.prev
    if vsum > 0.0:
        return msum / vsum
    return (
        pr.qual.node_qual[pr.net.link[k].n1]
        + pr.qual.node_qual[pr.net.link[k].n2]
    ) / 2.0


def _findsourcequal(
    mut pr: Project, n: Int, volout: Float64, tstep: Int
) -> Float64:
    """Return the quality that a source adds to the outflow of a node."""
    if pr.qual.qualflag != CHEM:
        return 0.0
    if not pr.net.node[n].has_source:
        return 0.0
    pr.net.node[n].source.smass = 0.0
    if pr.net.node[n].source.c0 == 0.0:
        return 0.0
    var dt = Float64(tstep)
    if volout / dt <= Q_STAGNANT:
        return 0.0
    var c = _sourcequal(pr, n)
    var stype = pr.net.node[n].source.type
    if stype == CONCEN:
        if pr.net.node[n].type == JUNCTION:
            if pr.hyd.node_demand[n] < 0.0:
                c = mul(mul(-c, pr.hyd.node_demand[n]), dt) / volout
            else:
                c = 0.0
    elif stype == MASS:
        c = mul(c, dt) / volout
    elif stype == SETPOINT:
        c = max(c - pr.qual.node_qual[n], 0.0)
    var massadded = mul(c, volout)
    pr.net.node[n].source.smass = massadded / dt
    if pr.times.qtime >= pr.times.rstart:
        pr.qual.wsource += massadded
    return c


def _sourcequal(pr: Project, n: Int) -> Float64:
    """Return the strength of the source of a node at the current time."""
    ref source = pr.net.node[n].source
    var c = source.c0
    if source.type == MASS:
        c /= 60.0
    else:
        c /= pr.ucf[QUALITY]
    var i = source.pat
    if i == 0:
        return c
    ref f = pr.net.pattern[i].f
    var k = ((pr.times.qtime + pr.times.pstart) // pr.times.pstep) % len(f)
    return mul(c, f[k])


def _evalmassbalance(mut pr: Project):
    """Find the ratio of the mass that leaves to the mass that enters."""
    ref mb = pr.qual.mass_balance
    if pr.qual.qualflag == NONE:
        mb.ratio = 1.0
        return
    var final = _findstoredmass(pr)
    pr.qual.mass_balance.final = final
    var massin = pr.qual.mass_balance.initial + pr.qual.mass_balance.inflow
    var massout = pr.qual.mass_balance.outflow + final
    var massreacted = pr.qual.mass_balance.reacted
    if massreacted > 0.0:
        massout += massreacted
    else:
        massin -= massreacted
    if massin == 0.0:
        pr.qual.mass_balance.ratio = 1.0
    else:
        pr.qual.mass_balance.ratio = massout / massin


def _findstoredmass(pr: Project) -> Float64:
    """Return the mass in all the pipes and tanks."""
    var totalmass = 0.0
    for k in range(1, pr.net.nlinks + 1):
        var s = pr.qual.first_seg[k]
        while s != 0:
            totalmass += mul(pr.qual.seg[s].c, pr.qual.seg[s].v)
            s = pr.qual.seg[s].prev
    for i in range(1, pr.net.ntanks + 1):  # pragma: no branch
        if pr.net.tank[i].a == 0.0:
            continue
        var s = pr.qual.first_seg[pr.net.nlinks + i]
        while s != 0:
            totalmass += mul(pr.qual.seg[s].c, pr.qual.seg[s].v)
            s = pr.qual.seg[s].prev
    return totalmass


def _linkflow(pr: Project, k: Int) -> Float64:
    """Return the flow of a link, 0 if it is closed."""
    if pr.hyd.link_status[k].value <= CLOSED.value:
        return 0.0
    return pr.hyd.link_flow[k]


def _flowdirchanged(mut pr: Project) -> Bool:
    """Update the flow directions and reverse the segments of a reversal."""
    var result = False
    for k in range(1, pr.net.nlinks + 1):
        var olddir = pr.qual.flow_dir[k].value
        var q = _linkflow(pr, k)
        var newdir = -1 if q < 0.0 else 1
        if abs(q) < Q_STAGNANT:
            newdir = 0
        if newdir * olddir < 0:
            _reversesegs(pr, k)
        if newdir != olddir:
            result = True
        pr.qual.flow_dir[k] = FlowDirection(newdir)
    return result


def _transport(mut pr: Project, tstep: Int):
    """Move the water quality forward by one quality time step."""
    if pr.qual.reactflag:
        _reactpipes(pr, tstep)
        _reacttanks(pr, tstep)
    var dt = Float64(tstep)
    for j in range(1, pr.net.nnodes + 1):  # pragma: no branch
        var n = pr.qual.sorted_nodes[j]
        var volin = 0.0
        var massin = 0.0
        var volout = 0.0
        for a in range(len(pr.net.adjlist[n])):
            var k = pr.net.adjlist[n][a].link
            var m = pr.net.link[k].n2
            if pr.qual.flow_dir[k].value < 0:
                m = pr.net.link[k].n1
            if m == n:
                _evalnodeinflow(pr, k, tstep, volin, massin)
            else:
                volout += abs(_linkflow(pr, k))
        if pr.net.node[n].type == JUNCTION:
            volout += max(0.0, pr.hyd.node_demand[n])
        volout = mul(volout, dt)
        var nodequal = _findnodequal(pr, n, volin, massin, volout, tstep)
        for a in range(len(pr.net.adjlist[n])):
            var k = pr.net.adjlist[n][a].link
            var m = pr.net.link[k].n1
            if pr.qual.flow_dir[k].value < 0:
                m = pr.net.link[k].n2
            if m == n:
                _evalnodeoutflow(pr, k, nodequal, tstep)
        _updatemassbalance(pr, n, massin, volout, tstep)


def _evalnodeinflow(
    mut pr: Project,
    k: Int,
    tstep: Int,
    mut volin: Float64,
    mut massin: Float64,
):
    """Take the water that a link delivers to its downstream node."""
    var q = _linkflow(pr, k)
    var v = mul(abs(q), Float64(tstep))
    while v > 0.0:
        var s = pr.qual.first_seg[k]
        if s == 0:
            break
        var vseg = min(pr.qual.seg[s].v, v)
        volin += vseg
        massin += mul(vseg, pr.qual.seg[s].c)
        v -= vseg
        # vseg is at most v, so v >= 0 here.
        if vseg >= pr.qual.seg[s].v:
            pr.qual.first_seg[k] = pr.qual.seg[s].prev
            if pr.qual.first_seg[k] == 0:
                pr.qual.last_seg[k] = 0
            pr.qual.seg[s].prev = pr.qual.free_seg
            pr.qual.free_seg = s
            pr.qual.mass_balance.seg_count -= 1
        else:
            pr.qual.seg[s].v -= vseg


def _findnodequal(
    mut pr: Project,
    n: Int,
    volin0: Float64,
    massin: Float64,
    volout: Float64,
    tstep: Int,
) -> Float64:
    """Mix the inflow of a node and add its source."""
    var volin = volin0
    var ntype = pr.net.node[n].type
    if ntype == JUNCTION:
        volin -= mul(min(0.0, pr.hyd.node_demand[n]), Float64(tstep))
        if volin > 0.0:
            pr.qual.node_qual[n] = massin / volin
        elif pr.qual.reactflag:
            pr.qual.node_qual[n] = _noflowqual(pr, n)
    elif ntype == TANK:
        pr.qual.node_qual[n] = _mixtank(pr, n, volin, massin, volout)
    pr.qual.source_qual = 0.0
    if pr.qual.qualflag == TRACE:
        if n == pr.qual.trace_node:
            if ntype == RESERVOIR:
                pr.qual.source_qual = 100.0
            else:
                pr.qual.source_qual = max(100.0 - pr.qual.node_qual[n], 0.0)
            pr.qual.node_qual[n] = 100.0
        return pr.qual.node_qual[n]
    pr.qual.source_qual = _findsourcequal(pr, n, volout, tstep)
    if pr.qual.source_qual == 0.0:
        return pr.qual.node_qual[n]
    if ntype == JUNCTION:
        pr.qual.node_qual[n] += pr.qual.source_qual
        return pr.qual.node_qual[n]
    if ntype == TANK:
        return pr.qual.node_qual[n] + pr.qual.source_qual
    pr.qual.node_qual[n] = pr.qual.source_qual
    return pr.qual.source_qual


def _noflowqual(pr: Project, n: Int) -> Float64:
    """Return the mean quality next to a junction with no inflow."""
    var c = 0.0
    var kount = 0
    for a in range(len(pr.net.adjlist[n])):
        var k = pr.net.adjlist[n][a].link
        var dir = pr.qual.flow_dir[k].value
        var inflow: Bool
        if pr.net.link[k].n2 == n and dir >= 0:
            inflow = True
        elif pr.net.link[k].n1 == n and dir < 0:
            inflow = True
        else:
            inflow = False
        if inflow and pr.qual.first_seg[k] != 0:
            c += pr.qual.seg[pr.qual.first_seg[k]].c
            kount += 1
        elif not inflow and pr.qual.last_seg[k] != 0:
            c += pr.qual.seg[pr.qual.last_seg[k]].c
            kount += 1
    if kount > 0:
        c = c / Float64(kount)
    return c


def _evalnodeoutflow(mut pr: Project, k: Int, c: Float64, tstep: Int):
    """Put the water that leaves a node into an outflow link."""
    var v = mul(abs(_linkflow(pr, k)), Float64(tstep))
    if v == 0.0:
        return
    var s = pr.qual.last_seg[k]
    if s != 0:
        ref seg = pr.qual.seg[s]
        if abs(seg.c - c) < pr.qual.ctol:
            seg.c = (mul(seg.c, seg.v) + mul(c, v)) / (seg.v + v)
            seg.v += v
            return
    _addseg(pr, k, v, c)


def _updatemassbalance(
    mut pr: Project, n: Int, massin: Float64, volout: Float64, tstep: Int
):
    """Add the mass that a node takes out and puts in."""
    var masslost = 0.0
    var massadded: Float64
    var ntype = pr.net.node[n].type
    if ntype == JUNCTION:
        masslost = mul(
            mul(max(0.0, pr.hyd.node_demand[n]), Float64(tstep)),
            pr.qual.node_qual[n],
        )
        massadded = mul(pr.qual.source_qual, volout)
    elif ntype == RESERVOIR:
        masslost = massin
        if pr.qual.source_qual > 0.0:
            massadded = mul(pr.qual.source_qual, volout)
        else:
            massadded = mul(pr.qual.node_qual[n], volout)
    else:
        massadded = mul(pr.qual.source_qual, volout)
    pr.qual.mass_balance.outflow += masslost
    pr.qual.mass_balance.inflow += massadded


def _sortnodes(mut pr: Project):
    """Sort the nodes from upstream to downstream.

    Each node goes on the stack once. When the stack is empty, each node
    that is not sorted has an inflow, so `_selectnonstacknode` finds one
    and every node is sorted. EPANET's error 120 cannot occur.
    """
    var nnodes = pr.net.nnodes
    var indegree = List[Int](length=nnodes + 1, fill=0)
    var stack = List[Int](length=nnodes + 1, fill=0)
    var stacksize = 0
    var numsorted = 0
    # `runqual` sorts only when a link changes its flow direction.
    for k in range(1, pr.net.nlinks + 1):  # pragma: no branch
        var dir = pr.qual.flow_dir[k]
        var n: Int
        if dir == POSITIVE:
            n = pr.net.link[k].n2
        elif dir == NEGATIVE:
            n = pr.net.link[k].n1
        else:
            continue
        indegree[n] += 1
    for i in range(1, nnodes + 1):  # pragma: no branch
        if indegree[i] == 0:
            stacksize += 1
            stack[stacksize] = i
    while numsorted < nnodes:
        if stacksize == 0:
            var j = _selectnonstacknode(pr, numsorted, indegree)
            indegree[j] = 0
            stacksize += 1
            stack[stacksize] = j
        var i = stack[stacksize]
        stacksize -= 1
        numsorted += 1
        pr.qual.sorted_nodes[numsorted] = i
        for a in range(len(pr.net.adjlist[i])):
            var k = pr.net.adjlist[i][a].link
            var dir = pr.qual.flow_dir[k].value
            if dir == 0:
                continue
            var n = pr.net.link[k].n2
            if dir < 0:
                n = pr.net.link[k].n1
            if n != i and indegree[n] > 0:
                indegree[n] -= 1
                if indegree[n] == 0:
                    stacksize += 1
                    stack[stacksize] = n


def _selectnonstacknode(
    pr: Project, numsorted: Int, indegree: List[Int]
) -> Int:
    """Pick a node to break a flow cycle.

    `_sortnodes` calls this when a node that is not sorted has an inflow.
    """
    for i in range(numsorted, 0, -1):
        var m = pr.qual.sorted_nodes[i]
        for a in pr.net.adjlist[m]:
            if indegree[a.node] > 0:
                return a.node
    var i = 1
    while indegree[i] == 0:
        i += 1
    return i


def _initsegs(mut pr: Project):
    """Fill each pipe and tank with one segment of its starting quality."""
    for k in range(1, pr.net.nlinks + 1):
        pr.qual.first_seg[k] = 0
        pr.qual.last_seg[k] = 0
        if pr.net.link[k].type.value <= PIPE.value:
            var d = pr.net.link[k].diam
            var v = mul(mul(0.785398, pr.net.link[k].len), mul(d, d))
            var c = pr.qual.node_qual[pr.net.link[k].n2]
            _addseg(pr, k, v, c)
    for j in range(1, pr.net.ntanks + 1):  # pragma: no branch
        if pr.net.tank[j].a == 0.0:
            continue
        var c = pr.net.node[pr.net.tank[j].node].c0
        var v = pr.net.tank[j].v0
        var k = pr.net.nlinks + j
        pr.qual.first_seg[k] = 0
        pr.qual.last_seg[k] = 0
        _addseg(pr, k, v, c)
        if pr.net.tank[j].mix_model == MIX2:
            var v1 = max(
                0.0, v - mul(pr.net.tank[j].v1frac, pr.net.tank[j].vmax)
            )
            pr.qual.seg[pr.qual.first_seg[k]].v = v1
            v = v - v1
            _addseg(pr, k, v, c)


def _reversesegs(mut pr: Project, k: Int):
    """Reverse the order of the segments of a link or a tank."""
    var s = pr.qual.first_seg[k]
    pr.qual.first_seg[k] = pr.qual.last_seg[k]
    pr.qual.last_seg[k] = s
    var pseg = 0
    while s != 0:
        var nseg = pr.qual.seg[s].prev
        pr.qual.seg[s].prev = pseg
        pseg = s
        s = nseg


def _addseg(mut pr: Project, k: Int, v: Float64, c: Float64):
    """Add a segment at the upstream end of a link or a tank."""
    var s: Int
    if pr.qual.free_seg != 0:
        s = pr.qual.free_seg
        pr.qual.free_seg = pr.qual.seg[s].prev
        pr.qual.seg[s] = Seg(v, c, 0)
    else:
        s = len(pr.qual.seg)
        pr.qual.seg.append(Seg(v, c, 0))
    if pr.qual.first_seg[k] == 0:
        pr.qual.first_seg[k] = s
    if pr.qual.last_seg[k] != 0:
        pr.qual.seg[pr.qual.last_seg[k]].prev = s
    pr.qual.last_seg[k] = s
    pr.qual.mass_balance.seg_count += 1


def _setreactflag(pr: Project) -> Bool:
    """Return True if any pipe or tank reacts."""
    if pr.qual.qualflag == TRACE:
        return False
    if pr.qual.qualflag == AGE:
        return True
    for i in range(1, pr.net.nlinks + 1):
        if pr.net.link[i].type.value <= PIPE.value:
            if pr.net.link[i].kb != 0.0 or pr.net.link[i].kw != 0.0:
                return True
    for i in range(1, pr.net.ntanks + 1):  # pragma: no branch
        if pr.net.tank[i].kb != 0.0:
            return True
    return False


def _getucf(order0: Float64) -> Float64:
    """Return the unit factor of a bulk reaction of an order."""
    var order = order0
    if order < 0.0:
        order = 0.0
    if order == 1.0:
        return 1.0
    return 1.0 / cpow(L_PER_FT3, order - 1.0)


def _ratecoeffs(mut pr: Project):
    """Find the wall reaction rate coefficient of each pipe."""
    for k in range(1, pr.net.nlinks + 1):
        var kw = pr.net.link[k].kw
        if kw != 0.0:
            kw = _piperate(pr, k)
        pr.net.link[k].rc = kw
        pr.qual.pipe_rate_coeff[k] = 0.0


def _piperate(pr: Project, k: Int) -> Float64:
    """Return the wall reaction rate of a pipe with mass transfer."""
    var d = pr.net.link[k].diam
    if pr.qual.sc == 0.0:
        if pr.qual.wall_order == 0.0:
            return BIG
        return mul(pr.net.link[k].kw, 4.0 / d) / pr.ucf[ELEV]
    var q = _linkflow(pr, k)
    var a = mul(mul(PI, d), d) / 4.0
    var u = abs(q) / a
    var re = mul(u, d) / pr.hyd.viscos
    var sh: Float64
    if re < 1.0:
        sh = 2.0
    elif re >= 2300.0:
        sh = mul(mul(0.0149, cpow(re, 0.88)), cpow(pr.qual.sc, 0.333))
    else:
        var y = mul(mul(d / pr.net.link[k].len, re), pr.qual.sc)
        sh = 3.65 + mul(0.0668, y) / (1.0 + mul(0.04, cpow(y, 0.667)))
    var kf = mul(sh, pr.qual.diffus) / d
    if pr.qual.wall_order == 0.0:
        return kf
    var kw = pr.net.link[k].kw / pr.ucf[ELEV]
    kw = mul(mul(4.0 / d, kw), kf) / (kf + abs(kw))
    return kw


def _reactpipes(mut pr: Project, dt: Int):
    """React the water in each pipe over a time step."""
    for k in range(1, pr.net.nlinks + 1):
        if pr.net.link[k].type.value > PIPE.value:
            continue
        var rsum = 0.0
        var vsum = 0.0
        var s = pr.qual.first_seg[k]
        while s != 0:
            var cseg = pr.qual.seg[s].c
            var v = pr.qual.seg[s].v
            var cnew = _pipereact(pr, k, cseg, v, dt)
            pr.qual.seg[s].c = cnew
            pr.qual.mass_balance.reacted += mul(cseg - cnew, v)
            if pr.qual.qualflag == CHEM:
                rsum += mul(abs(cnew - cseg), v)
                vsum += v
            s = pr.qual.seg[s].prev
        if vsum > 0.0:
            pr.qual.pipe_rate_coeff[k] = mul(
                rsum / vsum / Float64(dt), Float64(SEC_PER_DAY)
            )
        else:
            pr.qual.pipe_rate_coeff[k] = 0.0


def _reacttanks(mut pr: Project, dt: Int):
    """React the water in each tank over a time step."""
    for i in range(1, pr.net.ntanks + 1):  # pragma: no branch
        if pr.net.tank[i].a == 0.0:
            continue
        var kb = pr.net.tank[i].kb
        var s = pr.qual.first_seg[pr.net.nlinks + i]
        while s != 0:
            var c = pr.qual.seg[s].c
            var v = pr.qual.seg[s].v
            var cnew = _tankreact(pr, c, v, kb, dt)
            pr.qual.seg[s].c = cnew
            pr.qual.mass_balance.reacted += mul(c - cnew, v)
            s = pr.qual.seg[s].prev


def _pipereact(
    mut pr: Project, k: Int, c: Float64, v: Float64, dt: Int
) -> Float64:
    """Return the quality of a pipe segment after a time step."""
    if pr.qual.qualflag == AGE:
        var dc = Float64(dt) / 3600.0
        return max(0.0, c + dc)
    var rbulk = mul(
        _bulkrate(pr, c, pr.net.link[k].kb, pr.qual.bulk_order), pr.qual.bucf
    )
    var rwall = _wallrate(
        pr, c, pr.net.link[k].diam, pr.net.link[k].kw, pr.net.link[k].rc
    )
    var dcbulk = mul(rbulk, Float64(dt))
    var dcwall = mul(rwall, Float64(dt))
    if pr.times.qtime >= pr.times.rstart:
        pr.qual.wbulk += mul(abs(dcbulk), v)
        pr.qual.wwall += mul(abs(dcwall), v)
    var dc = dcbulk + dcwall
    return max(0.0, c + dc)


def _tankreact(
    mut pr: Project, c: Float64, v: Float64, kb: Float64, dt: Int
) -> Float64:
    """Return the quality of a tank segment after a time step."""
    var dc: Float64
    if pr.qual.qualflag == AGE:
        dc = Float64(dt) / 3600.0
    else:
        var rbulk = mul(_bulkrate(pr, c, kb, pr.qual.tank_order), pr.qual.tucf)
        dc = mul(rbulk, Float64(dt))
        if pr.times.qtime >= pr.times.rstart:
            pr.qual.wtank += mul(abs(dc), v)
    return max(0.0, c + dc)


def _bulkrate(pr: Project, c0: Float64, kb: Float64, order: Float64) -> Float64:
    """Return the bulk reaction rate at a quality."""
    var c = c0
    if order == 0.0:
        c = 1.0
    elif order < 0.0:
        var c1 = pr.qual.climit + mul(_sgn(kb), c)
        if abs(c1) < TINY:
            c1 = mul(_sgn(c1), TINY)
        c = c / c1
    else:
        var c1: Float64
        if pr.qual.climit == 0.0:
            c1 = c
        else:
            c1 = max(0.0, mul(_sgn(kb), pr.qual.climit - c))
        if order == 1.0:
            c = c1
        elif order == 2.0:
            c = mul(c1, c)
        elif c <= 0.0:
            c = 0.0
        else:
            c = mul(c1, cpow(c, order - 1.0))
    if c < 0.0:
        c = 0.0
    return mul(kb, c)


def _wallrate(
    pr: Project, c: Float64, d: Float64, kw0: Float64, kf0: Float64
) -> Float64:
    """Return the wall reaction rate at a quality.

    `pipedata` refuses a pipe diameter that is not positive, so d > 0.
    """
    if kw0 == 0.0:
        return 0.0
    if pr.qual.wall_order == 0.0:
        var kf = mul(mul(_sgn(kw0), c), kf0)
        var ucf = pr.ucf[ELEV]
        var kw = mul(kw0, mul(ucf, ucf))
        if abs(kf) < abs(kw):
            kw = kf
        return mul(kw, 4.0) / d
    return mul(c, kf0)


def _mixtank(
    mut pr: Project, n: Int, volin: Float64, massin: Float64, volout: Float64
) -> Float64:
    """Mix the inflow of a tank by its mixing model."""
    var i = n - pr.net.njuncs
    var vnet = volin - volout
    var model = pr.net.tank[i].mix_model
    if model == MIX1:
        _tankmix1(pr, i, volin, massin, vnet)
    elif model == MIX2:
        _tankmix2(pr, i, volin, massin, vnet)
    elif model == FIFO:
        _tankmix3(pr, i, volin, massin, vnet)
    else:
        _tankmix4(pr, i, volin, massin, vnet)
    return pr.net.tank[i].c


def _tankmix1(
    mut pr: Project, i: Int, vin: Float64, win: Float64, vnet: Float64
):
    """Mix a tank completely."""
    var k = pr.net.nlinks + i
    var s = pr.qual.first_seg[k]
    if s == 0:
        return
    ref seg = pr.qual.seg[s]
    var vnew = seg.v + vin
    if vnew > 0.0:
        seg.c = (mul(seg.c, seg.v) + win) / vnew
    seg.v += vnet
    seg.v = max(0.0, seg.v)
    pr.net.tank[i].c = seg.c
    var vmax = pr.net.tank[i].vmax
    if seg.v > vmax:
        pr.qual.mass_balance.outflow += mul(seg.v - vmax, pr.net.tank[i].c)
        seg.v = vmax


def _tankmix2(
    mut pr: Project, i: Int, vin: Float64, win: Float64, vnet: Float64
):
    """Mix a tank with a mixing zone and a stagnant zone."""
    var k = pr.net.nlinks + i
    var mz = pr.qual.last_seg[k]
    var sz = pr.qual.first_seg[k]
    # `_initsegs` gives a tank both of its segments, or none.
    if mz == 0:
        return
    var vmax = pr.net.tank[i].vmax
    var vmz = mul(pr.net.tank[i].v1frac, vmax)
    var mzc = pr.qual.seg[mz].c
    var mzv = pr.qual.seg[mz].v
    var szc = pr.qual.seg[sz].c
    var szv = pr.qual.seg[sz].v
    var vt = 0.0
    if vnet > 0.0:
        vt = max(0.0, mzv + vnet - vmz)
        # vnet = vin - vout with vout >= 0, so vin > 0 here.
        mzc = (mul(mzc, mzv) + win) / (mzv + vin)
        if vt > 0.0:
            szc = (mul(szc, szv) + mul(mzc, vt)) / (szv + vt)
    elif vnet < 0.0:
        if szv > 0.0:
            vt = min(szv, -vnet)
        if vin + vt > 0.0:
            mzc = (mul(mzc, mzv) + win + mul(szc, vt)) / (mzv + vin + vt)
    if vt > 0.0:
        if vnet > 0.0:
            mzv = vmz
            szv += vt
            var vsz = vmax - vmz
            if szv > vsz:
                pr.qual.mass_balance.outflow += mul(szv - vsz, szc)
                szv = vsz
        else:
            szv = max(0.0, szv - vt)
            mzv = vmz + vt + vnet
    else:
        mzv += vnet
        mzv = min(mzv, vmz)
        mzv = max(0.0, mzv)
        if vmz - mzv > 0.0:
            szv = 0.0
    pr.qual.seg[mz].c = mzc
    pr.qual.seg[mz].v = mzv
    pr.qual.seg[sz].c = szc
    pr.qual.seg[sz].v = szv
    pr.net.tank[i].c = mzc


def _withdraw(
    mut pr: Project, k: Int, vout0: Float64, mut vsum: Float64
) -> Float64:
    """Take a volume from the leading segments of a tank; return its mass.

    The tank has a segment. The last segment gives all the volume that is
    left and is never freed, so the tank keeps a segment.
    """
    var vout = vout0
    var wsum = 0.0
    while vout > 0.0:
        var s = pr.qual.first_seg[k]
        var vseg = min(pr.qual.seg[s].v, vout)
        if s == pr.qual.last_seg[k]:
            vseg = vout
        vsum += vseg
        wsum += mul(pr.qual.seg[s].c, vseg)
        vout -= vseg
        # vseg is at most vout, so vout >= 0 here.
        if vseg >= pr.qual.seg[s].v:
            if pr.qual.seg[s].prev != 0:
                pr.qual.first_seg[k] = pr.qual.seg[s].prev
                pr.qual.seg[s].prev = pr.qual.free_seg
                pr.qual.free_seg = s
        else:
            pr.qual.seg[s].v -= vseg
    return wsum


def _tankmix3(
    mut pr: Project, i: Int, vin: Float64, win: Float64, vnet: Float64
):
    """Mix a tank as first in, first out plug flow."""
    var k = pr.net.nlinks + i
    # A tank has a first and a last segment, or neither: see `_withdraw`.
    if pr.qual.last_seg[k] == 0:
        return
    if vin > 0.0:
        var cin = win / vin
        var s = pr.qual.last_seg[k]
        if abs(pr.qual.seg[s].c - cin) < pr.qual.ctol:
            pr.qual.seg[s].v += vin
        else:
            _addseg(pr, k, vin, cin)
    var vover = _tankoverflow(pr, i, vnet)
    var vout = vin - vnet + vover
    var vsum = 0.0
    var wsum = _withdraw(pr, k, vout, vsum)
    if vsum > 0.0:
        pr.net.tank[i].c = wsum / vsum
    else:
        pr.net.tank[i].c = pr.qual.seg[pr.qual.first_seg[k]].c
    pr.qual.mass_balance.outflow += mul(vover, pr.net.tank[i].c)


def _tankmix4(
    mut pr: Project, i: Int, vin: Float64, win: Float64, vnet0: Float64
):
    """Mix a tank as last in, first out plug flow."""
    var k = pr.net.nlinks + i
    # A tank has a first and a last segment, or neither: see `_withdraw`.
    if pr.qual.last_seg[k] == 0:
        return
    var vnet = vnet0
    var vover = _tankoverflow(pr, i, vnet)
    var cin = win / vin if vin > 0.0 else 0.0
    pr.net.tank[i].c = pr.qual.seg[pr.qual.last_seg[k]].c
    var s = pr.qual.last_seg[k]
    if vnet > 0.0:
        if abs(pr.qual.seg[s].c - cin) < pr.qual.ctol:
            pr.qual.seg[s].v += vnet
        else:
            _addseg(pr, k, vnet, cin)
        pr.net.tank[i].c = pr.qual.seg[pr.qual.last_seg[k]].c
        if vover > 0.0:
            var vsum = 0.0
            var wsum = _withdraw(pr, k, vover, vsum)
            pr.qual.mass_balance.outflow += wsum
    elif vnet < 0.0:
        _reversesegs(pr, k)
        var vsum = 0.0
        var wsum = _withdraw(pr, k, -vnet, vsum)
        _reversesegs(pr, k)
        pr.net.tank[i].c = (wsum + win) / (vsum + vin)


def _tankoverflow(mut pr: Project, i: Int, vnet: Float64) -> Float64:
    """Return the volume that overflows a tank and update its volume."""
    ref tank = pr.net.tank[i]
    var vover = 0.0
    if tank.can_overflow and vnet > 0.0:
        vover = max(0.0, tank.vq + vnet - tank.vmax)
    tank.vq += vnet - vover
    return vover
