# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from hydsolver.c of OWA EPANET 2.3.6. Copyright (c) 2023 the
# EPANET contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The global gradient algorithm of EPANET (hydsolver.c).

`hydsolve` finds the heads and the flows at one time. Each iteration
fills the matrix, solves it for the junction heads, and corrects the
flows. Between iterations the solver updates the status of valves,
pumps and check valves.
"""

from extensions.epanet.cmath import cpow, mul
from extensions.epanet.coeffs import (
    demandheadloss,
    emitterheadloss,
    headlosscoeffs,
    matrixcoeffs,
)
from extensions.epanet.hydstatus import linkstatus, valvestatus
from extensions.epanet.kinds import (
    ACTIVE,
    CLOSED,
    CONST_HP,
    DDA,
    FCV,
    HILEVEL,
    LOWLEVEL,
    MISSING,
    PDA,
    PIPE,
    PRV,
    PSV,
    PUMP,
    XFCV,
    XPRESSURE,
)
from extensions.epanet.leakage import leakageflowchange, leakagehasconverged
from extensions.epanet.lookup import findpump
from extensions.epanet.model import Project
from extensions.epanet.smatrix import linsolve


@fieldwise_init
struct Hydbalance(Copyable, Movable):
    """The largest head error and flow change of an iteration."""

    var maxheaderror: Float64
    var maxflowerror: Float64
    var maxflowchange: Float64
    var maxheadlink: Int
    var maxflownode: Int
    var maxflowlink: Int


def hydsolve(mut pr: Project, mut iter: Int, mut relerr: Float64) -> Int:
    """Solve the network equations for the heads and the flows.

    Args:
        pr: The project.
        iter: Receives the number of iterations.
        relerr: Receives the relative flow change of the last iteration.

    Returns:
        0, or error 110 if the matrix is ill-conditioned.
    """
    var hbal = Hydbalance(0.0, 0.0, 0.0, 0, 0, 0)
    var nextcheck = pr.hyd.check_freq
    pr.hyd.relax_factor = 1.0
    pr.hyd.deficient_nodes = 0
    pr.hyd.demand_reduction = 0.0
    var maxtrials = pr.hyd.max_iter
    if pr.hyd.extra_iter > 0:
        maxtrials += min(pr.hyd.extra_iter, 2147483647 - maxtrials)
    var errcode = 0
    var njuncs = pr.net.njuncs
    iter = 1
    while iter <= maxtrials:
        headlosscoeffs(pr)
        matrixcoeffs(pr)
        errcode = linsolve(pr.hyd.sm, njuncs)
        if errcode > 0:
            if _badvalve(pr, pr.hyd.sm.order[errcode]):
                continue
            break
        for i in range(1, njuncs + 1):
            pr.hyd.node_head[i] = pr.hyd.sm.f[pr.hyd.sm.row[i]]
        relerr = _newflows(pr, hbal)
        pr.hyd.relax_factor = 1.0
        var valve_change = False
        if pr.hyd.damp_limit > 0.0:
            if relerr <= pr.hyd.damp_limit:
                pr.hyd.relax_factor = 0.6
                valve_change = valvestatus(pr)
        else:
            valve_change = valvestatus(pr)
        if _hasconverged(pr, relerr, hbal):
            if iter > pr.hyd.max_iter:
                break
            var stat_change = valve_change
            if linkstatus(pr):
                stat_change = True
            if _pswitch(pr):
                stat_change = True
            if not stat_change:
                break
            nextcheck = iter + pr.hyd.check_freq
        elif iter <= pr.hyd.max_check and iter == nextcheck:
            _ = linkstatus(pr)
            nextcheck += pr.hyd.check_freq
        iter += 1
    if errcode > 0:
        errcode = 110
    for i in range(1, njuncs + 1):
        pr.hyd.node_demand[i] = (
            pr.hyd.demand_flow[i]
            + pr.hyd.emitter_flow[i]
            + pr.hyd.leakage_flow[i]
        )
    pr.hyd.relative_error = relerr
    pr.hyd.max_head_error = hbal.maxheaderror
    pr.hyd.max_flow_change = hbal.maxflowchange
    pr.hyd.iterations = iter
    return errcode


def _badvalve(mut pr: Project, n: Int) -> Bool:
    """Make an active valve at a node of a singular matrix inactive."""
    for i in range(1, pr.net.nvalves + 1):
        var k = pr.net.valve[i].link
        var n1 = pr.net.link[k].n1
        var n2 = pr.net.link[k].n2
        if n == n1 or n == n2:
            var t = pr.net.link[k].type
            if t == PRV or t == PSV or t == FCV:
                if pr.hyd.link_status[k] == ACTIVE:
                    if t == FCV:
                        pr.hyd.link_status[k] = XFCV
                    else:
                        pr.hyd.link_status[k] = XPRESSURE
                    return True
            return False
    return False


def _pswitch(mut pr: Project) -> Bool:
    """Apply the junction pressure controls."""
    var anychange = False
    for i in range(1, pr.net.ncontrols + 1):
        # `controldata` gives each control a link.
        var k = pr.net.control[i].link
        var n = pr.net.control[i].node
        var reset = False
        if n > 0 and n <= pr.net.njuncs:
            var ctype = pr.net.control[i].type
            var grade = pr.net.control[i].grade
            if ctype == LOWLEVEL and pr.hyd.node_head[n] <= grade + pr.hyd.htol:
                reset = True
            if ctype == HILEVEL and pr.hyd.node_head[n] >= grade - pr.hyd.htol:
                reset = True
        if not reset:
            continue
        var t = pr.net.link[k].type
        var s = pr.hyd.link_status[k]
        var cstatus = pr.net.control[i].status
        var csetting = pr.net.control[i].setting
        var change = False
        if t == PIPE:
            if s != cstatus:
                change = True
        if t == PUMP:
            if pr.hyd.link_setting[k] != csetting:
                change = True
        if t.value >= PRV.value:
            if pr.hyd.link_setting[k] != csetting:
                change = True
            elif pr.hyd.link_setting[k] == MISSING and s != cstatus:
                change = True
        if change:
            pr.hyd.link_status[k] = cstatus
            if t.value > PIPE.value:
                pr.hyd.link_setting[k] = csetting
            anychange = True
    return anychange


def _newflows(mut pr: Project, mut hbal: Hydbalance) -> Float64:
    """Correct the flows and return the relative flow change."""
    var qsum = 0.0
    var dqsum = 0.0
    hbal.maxflowchange = 0.0
    hbal.maxflowlink = 1
    hbal.maxflownode = -1
    _newlinkflows(pr, hbal, qsum, dqsum)
    _newemitterflows(pr, hbal, qsum, dqsum)
    _newdemandflows(pr, hbal, qsum, dqsum)
    if pr.hyd.has_leakage:
        _newleakageflows(pr, hbal, qsum, dqsum)
    if qsum > pr.hyd.hacc:
        return dqsum / qsum
    return dqsum


def _track_node(mut hbal: Hydbalance, dq: Float64, i: Int):
    """Record a node flow change if it is the largest."""
    if abs(dq) > hbal.maxflowchange:
        hbal.maxflowchange = abs(dq)
        hbal.maxflownode = i
        hbal.maxflowlink = -1


def _newlinkflows(
    mut pr: Project,
    mut hbal: Hydbalance,
    mut qsum: Float64,
    mut dqsum: Float64,
):
    """Correct the link flows."""
    var njuncs = pr.net.njuncs
    # `validatenetwork` checks that there is a tank or a reservoir.
    for n in range(njuncs + 1, pr.net.nnodes + 1):  # pragma: no branch
        pr.hyd.node_demand[n] = 0.0
    for k in range(1, pr.net.nlinks + 1):
        var n1 = pr.net.link[k].n1
        var n2 = pr.net.link[k].n2
        var dh = pr.hyd.node_head[n1] - pr.hyd.node_head[n2]
        var dq = pr.hyd.y[k] - mul(pr.hyd.p[k], dh)
        dq *= pr.hyd.relax_factor
        if pr.net.link[k].type == PUMP:
            var n = findpump(pr.net, k)
            if pr.net.pump[n].ptype == CONST_HP and dq > pr.hyd.link_flow[k]:
                dq = pr.hyd.link_flow[k] / 2.0
        pr.hyd.link_flow[k] -= dq
        qsum += abs(pr.hyd.link_flow[k])
        dqsum += abs(dq)
        if abs(dq) > hbal.maxflowchange:
            hbal.maxflowchange = abs(dq)
            hbal.maxflowlink = k
            hbal.maxflownode = -1
        if pr.hyd.link_status[k].value > CLOSED.value:
            if n1 > njuncs:
                pr.hyd.node_demand[n1] -= pr.hyd.link_flow[k]
            if n2 > njuncs:
                pr.hyd.node_demand[n2] += pr.hyd.link_flow[k]


def _newemitterflows(
    mut pr: Project,
    mut hbal: Hydbalance,
    mut qsum: Float64,
    mut dqsum: Float64,
):
    """Correct the emitter flows."""
    var hloss = 0.0
    var hgrad = 0.0
    for i in range(1, pr.net.njuncs + 1):
        if pr.net.node[i].ke == 0.0:
            continue
        emitterheadloss(pr, i, hloss, hgrad)
        var dh = pr.hyd.node_head[i] - pr.net.node[i].el
        var dq = (hloss - dh) / hgrad
        dq *= pr.hyd.relax_factor
        pr.hyd.emitter_flow[i] -= dq
        qsum += abs(pr.hyd.emitter_flow[i])
        dqsum += abs(dq)
        _track_node(hbal, dq, i)


def _newleakageflows(
    mut pr: Project,
    mut hbal: Hydbalance,
    mut qsum: Float64,
    mut dqsum: Float64,
):
    """Correct the leakage flows."""
    for i in range(1, pr.net.njuncs + 1):
        var dq = leakageflowchange(pr, i)
        if dq == 0.0:
            continue
        qsum += abs(pr.hyd.leakage_flow[i])
        dqsum += abs(dq)
        _track_node(hbal, dq, i)


def _newdemandflows(
    mut pr: Project,
    mut hbal: Hydbalance,
    mut qsum: Float64,
    mut dqsum: Float64,
):
    """Correct the pressure driven demands."""
    if pr.hyd.demand_model == DDA:
        return
    var dp = pr.hyd.preq - pr.hyd.pmin
    var n = 1.0 / pr.hyd.pexp
    var hloss = 0.0
    var hgrad = 0.0
    for i in range(1, pr.net.njuncs + 1):
        var full = pr.hyd.full_demand[i]
        if full <= 0.0:
            continue
        demandheadloss(pr, i, dp, n, hloss, hgrad)
        var dh = pr.hyd.node_head[i] - pr.net.node[i].el - pr.hyd.pmin
        var dq = (hloss - dh) / hgrad
        dq *= pr.hyd.relax_factor
        if abs(dq) > mul(0.4, full):
            dq = mul(0.4 if dq >= 0.0 else -0.4, full)
        pr.hyd.demand_flow[i] -= dq
        qsum += abs(pr.hyd.demand_flow[i])
        dqsum += abs(dq)
        _track_node(hbal, dq, i)


def _checkhydbalance(mut pr: Project, mut hbal: Hydbalance):
    """Find the largest head loss error of the links."""
    hbal.maxheaderror = 0.0
    hbal.maxheadlink = 1
    headlosscoeffs(pr)
    for k in range(1, pr.net.nlinks + 1):
        if pr.hyd.link_status[k].value <= CLOSED.value:
            continue
        if pr.hyd.p[k] == 0.0:
            continue
        var n1 = pr.net.link[k].n1
        var n2 = pr.net.link[k].n2
        var dh = pr.hyd.node_head[n1] - pr.hyd.node_head[n2]
        var headloss = pr.hyd.y[k] / pr.hyd.p[k]
        var headerror = abs(dh - headloss)
        if headerror > hbal.maxheaderror:
            hbal.maxheaderror = headerror
            hbal.maxheadlink = k


def _hasconverged(
    mut pr: Project, relerr: Float64, mut hbal: Hydbalance
) -> Bool:
    """Return True if the solution meets every convergence limit."""
    if relerr > pr.hyd.hacc:
        return False
    _checkhydbalance(pr, hbal)
    if (
        pr.hyd.head_error_limit > 0.0
        and hbal.maxheaderror > pr.hyd.head_error_limit
    ):
        return False
    if (
        pr.hyd.flow_change_limit > 0.0
        and hbal.maxflowchange > pr.hyd.flow_change_limit
    ):
        return False
    if pr.hyd.has_leakage and not leakagehasconverged(pr):
        return False
    if pr.hyd.demand_model == PDA:
        return _pdaconverged(pr)
    return True


def _pdaconverged(mut pr: Project) -> Bool:
    """Return True if each pressure driven demand matches its pressure."""
    comptime QTOL = 0.0001
    var converged = True
    var total_demand = 0.0
    var total_reduction = 0.0
    var dp = pr.hyd.preq - pr.hyd.pmin
    pr.hyd.deficient_nodes = 0
    pr.hyd.demand_reduction = 0.0
    for i in range(1, pr.net.njuncs + 1):
        var full = pr.hyd.full_demand[i]
        if full <= 0.0:
            continue
        var p = pr.hyd.node_head[i] - pr.net.node[i].el
        var q: Float64
        if p <= pr.hyd.pmin:
            q = 0.0
        elif p >= pr.hyd.preq:
            q = full
        else:
            var r = (p - pr.hyd.pmin) / dp
            q = mul(full, cpow(r, pr.hyd.pexp))
        if abs(q - pr.hyd.demand_flow[i]) > QTOL:
            converged = False
        if pr.hyd.demand_flow[i] + QTOL < full:
            pr.hyd.deficient_nodes += 1
            total_demand += full
            total_reduction += full - pr.hyd.demand_flow[i]
    if total_demand > 0.0:
        pr.hyd.demand_reduction = mul(total_reduction / total_demand, 100.0)
    return converged
