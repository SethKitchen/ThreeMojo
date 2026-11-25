# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from hydcoeffs.c of OWA EPANET 2.3.6. Copyright (c) 2023 the
# EPANET contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The coefficients of the matrix of the hydraulic equations (hydcoeffs.c).

`headlosscoeffs` finds the inverse head loss gradient P and the flow
correction Y of each link. `matrixcoeffs` then adds the links, the
emitters, the pressure driven demands, the leaks and the valves to the
matrix and to its right side.
"""

from std.math import sqrt

from extensions.epanet.kinds import (
    CONST_HP,
    CUSTOM,
    CVPIPE,
    DDA,
    DW,
    FCV,
    GPV,
    HW,
    MISSING,
    PBV,
    PCV,
    PI,
    PIPE,
    PRV,
    PSV,
    PUMP,
    TCV,
    TINY,
    ACTIVE,
    CLOSED,
)
from extensions.epanet.cmath import clog, cpow, mul
from extensions.epanet.leakage import leakagecoeffs
from extensions.epanet.lookup import findpump, findvalve
from extensions.epanet.model import FLOW, HEAD, Project

comptime A1 = 3.14159265358979323850e03
comptime A2 = 1.57079632679489661930e03
comptime A8 = 4.61841319859066668690e00
comptime A9 = -8.68588963806503655300e-01
comptime AB = 3.28895476345399058690e-03
comptime AC = -5.14214965799093883760e-03
comptime CSMALL = 1.0e-6
comptime CBIG = 1.0e8


def _sgn(x: Float64) -> Float64:
    """Return -1 for a negative number and 1 otherwise."""
    if x < 0.0:
        return -1.0
    return 1.0


def addlowerbarrier(dq: Float64, mut hloss: Float64, mut hgrad: Float64):
    """Add a barrier that keeps a flow from going below zero.

    Args:
        dq: The flow less its lower limit.
        hloss: The head loss. The barrier term is added.
        hgrad: The head loss gradient. The barrier term is added.
    """
    var a = mul(1.0e9, dq)
    var b = sqrt(mul(a, a) + 1.0e-6)
    hloss += (a - b) / 2.0
    hgrad += mul(1.0e9 / 2.0, 1.0 - a / b)


def addupperbarrier(dq: Float64, mut hloss: Float64, mut hgrad: Float64):
    """Add a barrier that keeps a flow from going above a limit.

    Args:
        dq: The flow less its upper limit.
        hloss: The head loss. The barrier term is added.
        hgrad: The head loss gradient. The barrier term is added.
    """
    var a = mul(1.0e9, dq)
    var b = sqrt(mul(a, a) + 1.0e-6)
    hloss += (a + b) / 2.0
    hgrad += mul(1.0e9 / 2.0, 1.0 + a / b)


def resistcoeff(mut pr: Project, k: Int):
    """Find the flow resistance coefficient of a link.

    Args:
        pr: The project.
        k: The link index.
    """
    var t = pr.net.link[k].type
    if t == CVPIPE or t == PIPE:
        var e = pr.net.link[k].kc
        var d = pr.net.link[k].diam
        var length = pr.net.link[k].len
        var f = pr.hyd.formflag
        if f == HW:
            pr.net.link[k].r = (
                mul(4.727, length) / cpow(e, pr.hyd.hexp) / cpow(d, 4.871)
            )
        elif f == DW:
            var area = mul(PI, mul(d, d)) / 4.0
            pr.net.link[k].r = length / 2.0 / 32.2 / d / mul(area, area)
        else:
            var c = mul(4.0, e) / mul(mul(1.49, PI), mul(d, d))
            pr.net.link[k].r = mul(
                mul(mul(c, c), cpow(d / 4.0, -1.333)), length
            )
    elif t == PUMP:
        pr.net.link[k].r = CBIG
    elif t == PCV:
        pr.net.link[k].r = pcvlosscoeff(pr, k, pr.net.link[k].kc)
    else:
        pr.net.link[k].r = CSMALL


def pcvlosscoeff(pr: Project, k: Int, s: Float64) -> Float64:
    """Find the minor loss coefficient of a positional control valve.

    Args:
        pr: The project.
        k: The link index.
        s: The percent open.

    Returns:
        The minor loss coefficient at that opening.
    """
    if s == MISSING:
        return 0.0
    var kmo = pr.net.link[k].km
    if s >= 100.0:
        return kmo
    if s <= 0.0:
        return CBIG
    var c = pr.net.valve[findvalve(pr.net, k)].curve
    var kvr: Float64
    if c == 0:
        kvr = s
    else:
        ref x = pr.net.curve[c].x
        ref y = pr.net.curve[c].y
        var npts = len(x)
        if s < x[0]:
            kvr = mul(s / x[0], y[0])
        elif s > x[npts - 1]:
            var k2 = npts - 1
            kvr = mul((s - x[k2]) / (100.0 - x[k2]), 100.0 - y[k2]) + y[k2]
        else:
            # x[0] <= s <= x[npts - 1], so the search stops at a point.
            var k2 = 0
            while x[k2] < s:
                k2 += 1
            if k2 == 0:
                k2 += 1
            var k1 = k2 - 1
            kvr = (y[k2] - y[k1]) / (x[k2] - x[k1])
            kvr = y[k1] + mul(kvr, s - x[k1])
    kvr /= 100.0
    kvr = min(kvr, 1.0)
    kvr = max(kvr, CSMALL)
    var km = kmo / mul(kvr, kvr)
    return min(km, CBIG)


def headlosscoeffs(mut pr: Project):
    """Find the head loss coefficients P and Y of every link.

    Args:
        pr: The project.
    """
    for k in range(1, pr.net.nlinks + 1):
        var t = pr.net.link[k].type
        if t == CVPIPE or t == PIPE:
            _pipecoeff(pr, k)
        elif t == PUMP:
            _pumpcoeff(pr, k)
        elif t == PBV:
            _pbvcoeff(pr, k)
        elif t == TCV:
            _tcvcoeff(pr, k)
        elif t == PCV:
            _pcvcoeff(pr, k)
        elif t == GPV:
            _gpvcoeff(pr, k)
        else:
            if pr.hyd.link_setting[k] == MISSING:
                _valvecoeff(pr, k)
            else:
                pr.hyd.p[k] = 0.0


def matrixcoeffs(mut pr: Project):
    """Fill the matrix of the hydraulic equations and its right side.

    Args:
        pr: The project, after `headlosscoeffs`.
    """
    # `createsparse` and `openhyd` give each array an entry 0.
    for i in range(len(pr.hyd.sm.aii)):  # pragma: no branch
        pr.hyd.sm.aii[i] = 0.0
    for i in range(len(pr.hyd.sm.aij)):  # pragma: no branch
        pr.hyd.sm.aij[i] = 0.0
    for i in range(len(pr.hyd.sm.f)):  # pragma: no branch
        pr.hyd.sm.f[i] = 0.0
    for i in range(len(pr.hyd.xflow)):  # pragma: no branch
        pr.hyd.xflow[i] = 0.0
    _linkcoeffs(pr)
    _emittercoeffs(pr)
    _demandcoeffs(pr)
    if pr.hyd.has_leakage:
        leakagecoeffs(pr)
    _nodecoeffs(pr)
    _valvecoeffs(pr)


def _linkcoeffs(mut pr: Project):
    """Add the links to the matrix."""
    var njuncs = pr.net.njuncs
    for k in range(1, pr.net.nlinks + 1):
        var p = pr.hyd.p[k]
        if p == 0.0:
            continue
        var n1 = pr.net.link[k].n1
        var n2 = pr.net.link[k].n2
        var q = pr.hyd.link_flow[k]
        var y = pr.hyd.y[k]
        pr.hyd.xflow[n1] -= q
        pr.hyd.xflow[n2] += q
        pr.hyd.sm.aij[pr.hyd.sm.ndx[k]] -= p
        var r1 = pr.hyd.sm.row[n1]
        var r2 = pr.hyd.sm.row[n2]
        if n1 <= njuncs:
            pr.hyd.sm.aii[r1] += p
            pr.hyd.sm.f[r1] += y
        else:
            pr.hyd.sm.f[r2] += mul(p, pr.hyd.node_head[n1])
        if n2 <= njuncs:
            pr.hyd.sm.aii[r2] += p
            pr.hyd.sm.f[r2] -= y
        else:
            pr.hyd.sm.f[r1] += mul(p, pr.hyd.node_head[n2])


def _nodecoeffs(mut pr: Project):
    """Add the net flow into each junction to the right side."""
    for i in range(1, pr.net.njuncs + 1):
        pr.hyd.xflow[i] -= pr.hyd.demand_flow[i]
        pr.hyd.sm.f[pr.hyd.sm.row[i]] += pr.hyd.xflow[i]


def _valvecoeffs(mut pr: Project):
    """Add the pressure and flow control valves to the matrix."""
    for i in range(1, pr.net.nvalves + 1):
        var k = pr.net.valve[i].link
        if pr.hyd.link_setting[k] == MISSING:
            continue
        var n1 = pr.net.link[k].n1
        var n2 = pr.net.link[k].n2
        var t = pr.net.link[k].type
        if t == PRV:
            _prvcoeff(pr, k, n1, n2)
        elif t == PSV:
            _psvcoeff(pr, k, n1, n2)
        elif t == FCV:
            _fcvcoeff(pr, k, n1, n2)


def _emittercoeffs(mut pr: Project):
    """Add the emitters to the matrix."""
    var hloss = 0.0
    var hgrad = 0.0
    for i in range(1, pr.net.njuncs + 1):
        if pr.net.node[i].ke == 0.0:
            continue
        emitterheadloss(pr, i, hloss, hgrad)
        var row = pr.hyd.sm.row[i]
        pr.hyd.sm.aii[row] += 1.0 / hgrad
        pr.hyd.sm.f[row] += (hloss + pr.net.node[i].el) / hgrad
        pr.hyd.xflow[i] -= pr.hyd.emitter_flow[i]


def emitterheadloss(
    pr: Project, i: Int, mut hloss: Float64, mut hgrad: Float64
):
    """Find the head loss through an emitter and its gradient.

    Args:
        pr: The project.
        i: The junction index.
        hloss: Receives the head loss.
        hgrad: Receives the head loss gradient.
    """
    var ke = max(CSMALL, pr.net.node[i].ke)
    var q = pr.hyd.emitter_flow[i]
    var qexp = pr.hyd.qexp
    hgrad = mul(mul(qexp, ke), cpow(abs(q), qexp - 1.0))
    if hgrad < pr.hyd.rqtol:
        hgrad = pr.hyd.rqtol / qexp
        hloss = mul(hgrad, q)
    else:
        hloss = mul(hgrad, q) / qexp
    if not pr.hyd.emit_back_flag:
        addlowerbarrier(q, hloss, hgrad)


def _demandcoeffs(mut pr: Project):
    """Add the pressure driven demands to the matrix."""
    if pr.hyd.demand_model == DDA:
        return
    var dp = pr.hyd.preq - pr.hyd.pmin
    var n = 1.0 / pr.hyd.pexp
    var hloss = 0.0
    var hgrad = 0.0
    for i in range(1, pr.net.njuncs + 1):
        if pr.hyd.full_demand[i] <= 0.0:
            continue
        demandheadloss(pr, i, dp, n, hloss, hgrad)
        if hgrad > 0.0:
            var row = pr.hyd.sm.row[i]
            pr.hyd.sm.aii[row] += 1.0 / hgrad
            pr.hyd.sm.f[row] += (
                hloss + pr.net.node[i].el + pr.hyd.pmin
            ) / hgrad


def demandheadloss(
    pr: Project,
    i: Int,
    dp: Float64,
    n: Float64,
    mut hloss: Float64,
    mut hgrad: Float64,
):
    """Find the head loss of a pressure driven demand and its gradient.

    Args:
        pr: The project.
        i: The junction index.
        dp: The pressure range over which the demand varies.
        n: The inverse of the pressure exponent.
        hloss: Receives the head loss.
        hgrad: Receives the head loss gradient.
    """
    var d = pr.hyd.demand_flow[i]
    var dfull = pr.hyd.full_demand[i]
    var r = abs(d) / dfull
    hgrad = mul(mul(n, dp), cpow(r, n - 1.0)) / dfull
    hloss = mul(hgrad, d) / n
    addlowerbarrier(d, hloss, hgrad)
    addupperbarrier(d - dfull, hloss, hgrad)


def _pipecoeff(mut pr: Project, k: Int):
    """Find the head loss coefficients of a pipe."""
    if pr.hyd.link_status[k].value <= CLOSED.value:
        pr.hyd.p[k] = 1.0 / CBIG
        pr.hyd.y[k] = pr.hyd.link_flow[k]
        return
    if pr.hyd.formflag == DW:
        _dwpipecoeff(pr, k)
        return
    var q = abs(pr.hyd.link_flow[k])
    var ml = pr.net.link[k].km
    var r = pr.net.link[k].r
    var hexp = pr.hyd.hexp
    var hgrad = mul(mul(hexp, r), cpow(q, hexp - 1.0))
    var hloss: Float64
    if hgrad < pr.hyd.rqtol:
        hgrad = pr.hyd.rqtol / hexp
        hloss = mul(hgrad, q)
    else:
        hloss = mul(hgrad, q) / hexp
    if ml > 0.0:
        hloss += mul(mul(ml, q), q)
        hgrad += mul(mul(2.0, ml), q)
    hloss *= _sgn(pr.hyd.link_flow[k])
    pr.hyd.p[k] = 1.0 / hgrad
    pr.hyd.y[k] = hloss / hgrad


def _dwpipecoeff(mut pr: Project, k: Int):
    """Find the Darcy-Weisbach head loss coefficients of a pipe."""
    var flow = pr.hyd.link_flow[k]
    var q = abs(flow)
    var r = pr.net.link[k].r
    var ml = pr.net.link[k].km
    var e = pr.net.link[k].kc / pr.net.link[k].diam
    var s = mul(pr.hyd.viscos, pr.net.link[k].diam)
    var hloss: Float64
    var hgrad: Float64
    if q <= mul(A2, s):
        r = mul(mul(mul(16.0, PI), s), r)
        hloss = mul(flow, r + mul(ml, q))
        hgrad = r + mul(mul(2.0, ml), q)
    else:
        var dfdq = 0.0
        var f = _friction_factor(q, e, s, dfdq)
        var r1 = mul(f, r) + ml
        hloss = mul(mul(r1, q), flow)
        hgrad = mul(mul(2.0, r1), q) + mul(mul(mul(dfdq, r), q), q)
    pr.hyd.p[k] = 1.0 / hgrad
    pr.hyd.y[k] = hloss / hgrad


def _friction_factor(
    q: Float64, e: Float64, s: Float64, mut dfdq: Float64
) -> Float64:
    """Find the Darcy-Weisbach friction factor and its flow derivative."""
    var w = q / s
    var f: Float64
    if w >= A1:
        var y1 = A8 / cpow(w, 0.9)
        var y2 = e / 3.7 + y1
        var y3 = mul(A9, clog(y2))
        f = 1.0 / mul(y3, y3)
        dfdq = mul(mul(mul(1.8, f), y1), A9) / y2 / y3 / q
    else:
        var y2 = e / 3.7 + AB
        var y3 = mul(A9, clog(y2))
        var fa = 1.0 / mul(y3, y3)
        var fb = mul(2.0 + AC / mul(y2, y3), fa)
        var r = w / A2
        var x1 = mul(7.0, fa) - fb
        var x2 = 0.128 - mul(17.0, fa) + mul(2.5, fb)
        var x3 = -0.128 + mul(13.0, fa) - (fb + fb)
        var x4 = 0.032 - mul(3.0, fa) + mul(0.5, fb)
        f = x1 + mul(r, x2 + mul(r, x3 + mul(r, x4)))
        dfdq = (x2 + mul(r, mul(2.0, x3) + mul(mul(r, 3.0), x4))) / s / A2
    return f


def _pumpcoeff(mut pr: Project, k: Int):
    """Find the head gain coefficients of a pump."""
    var setting = pr.hyd.link_setting[k]
    var flow = pr.hyd.link_flow[k]
    if pr.hyd.link_status[k].value <= CLOSED.value or setting == 0.0:
        pr.hyd.p[k] = 1.0 / CBIG
        pr.hyd.y[k] = flow
        return
    var q = abs(flow)
    var p = findpump(pr.net, k)
    # `validatepumps` refuses a pump with no curve.
    var ptype = pr.net.pump[p].ptype
    var hgrad: Float64
    var hloss: Float64
    if ptype == CUSTOM:
        var h0 = 0.0
        var r = 0.0
        curvecoeff(pr, pr.net.pump[p].hcurve, q / setting, h0, r)
        pr.net.pump[p].h0 = -h0
        pr.net.pump[p].r = -r
        pr.net.pump[p].n = 1.0
        hgrad = mul(pr.net.pump[p].r, setting)
        hloss = mul(pr.net.pump[p].h0, mul(setting, setting)) + mul(hgrad, flow)
    else:
        var h0 = mul(mul(setting, setting), pr.net.pump[p].h0)
        var n = pr.net.pump[p].n
        if abs(n - 1.0) < TINY:
            n = 1.0
        var r = mul(pr.net.pump[p].r, cpow(setting, 2.0 - n))
        if ptype == CONST_HP:
            hgrad = -r / q / q
            if hgrad > CBIG:
                pr.hyd.p[k] = 1.0 / CBIG
                pr.hyd.y[k] = flow
                return
            elif hgrad < CSMALL:
                pr.hyd.p[k] = 1.0 / CSMALL
                pr.hyd.y[k] = flow
                return
            hloss = r / flow
        elif n != 1.0:
            hgrad = mul(mul(n, r), cpow(q, n - 1.0))
            if hgrad < pr.hyd.rqtol:
                hgrad = pr.hyd.rqtol
                hloss = h0 + mul(hgrad, flow)
            else:
                hloss = h0 + mul(hgrad, flow) / n
        else:
            hgrad = r
            hloss = h0 + mul(hgrad, flow)
    pr.hyd.p[k] = 1.0 / hgrad
    pr.hyd.y[k] = hloss / hgrad


def curvecoeff(
    pr: Project, i: Int, q0: Float64, mut h0: Float64, mut r: Float64
):
    """Find the line through the curve segment that holds a flow.

    Args:
        pr: The project.
        i: The curve index.
        q0: The flow in cubic feet per second.
        h0: Receives the head intercept of the segment, in feet.
        r: Receives the slope of the segment, in feet per cfs.
    """
    var q = mul(q0, pr.ucf[FLOW])
    ref x = pr.net.curve[i].x
    ref y = pr.net.curve[i].y
    var npts = len(x)
    var k2 = 0
    while k2 < npts and x[k2] < q:
        k2 += 1
    if k2 == 0:
        k2 += 1
    elif k2 == npts:
        k2 -= 1
    var k1 = k2 - 1
    r = (y[k2] - y[k1]) / (x[k2] - x[k1])
    h0 = y[k1] - mul(r, x[k1])
    h0 = h0 / pr.ucf[HEAD]
    r = mul(r, pr.ucf[FLOW]) / pr.ucf[HEAD]


def _gpvcoeff(mut pr: Project, k: Int):
    """Find the head loss coefficients of a general purpose valve."""
    if pr.hyd.link_status[k].value <= CLOSED.value:
        _valvecoeff(pr, k)
        return
    var i = pr.net.valve[findvalve(pr.net, k)].curve
    var q = max(abs(pr.hyd.link_flow[k]), TINY)
    var h0 = 0.0
    var r = 0.0
    curvecoeff(pr, i, q, h0, r)
    r = max(r, TINY)
    pr.hyd.p[k] = 1.0 / r
    pr.hyd.y[k] = mul(h0 / r + q, _sgn(pr.hyd.link_flow[k]))


def _pbvcoeff(mut pr: Project, k: Int):
    """Find the head loss coefficients of a pressure breaker valve."""
    var setting = pr.hyd.link_setting[k]
    if (
        pr.hyd.link_status[k].value <= CLOSED.value
        or setting == MISSING
        or setting == 0.0
    ):
        _valvecoeff(pr, k)
    else:
        var flow = pr.hyd.link_flow[k]
        if mul(pr.net.link[k].km, mul(flow, flow)) > setting:
            _valvecoeff(pr, k)
        else:
            pr.hyd.p[k] = CBIG
            pr.hyd.y[k] = mul(setting, CBIG)


def _tcvcoeff(mut pr: Project, k: Int):
    """Find the head loss coefficients of a throttle control valve."""
    var km = pr.net.link[k].km
    var setting = pr.hyd.link_setting[k]
    if setting != MISSING:
        var d = pr.net.link[k].diam
        pr.net.link[k].km = mul(0.02517, setting) / mul(mul(d, d), mul(d, d))
    _valvecoeff(pr, k)
    pr.net.link[k].km = km


def _pcvcoeff(mut pr: Project, k: Int):
    """Find the head loss coefficients of a positional control valve."""
    var km = pr.net.link[k].km
    if pr.hyd.link_setting[k] != MISSING:
        pr.net.link[k].km = pr.net.link[k].r
    _valvecoeff(pr, k)
    pr.net.link[k].km = km


def _add_open_valve(mut pr: Project, k: Int, i: Int, j: Int):
    """Add a valve that is not active to the matrix."""
    _valvecoeff(pr, k)
    var p = pr.hyd.p[k]
    var dy = pr.hyd.y[k] - pr.hyd.link_flow[k]
    pr.hyd.sm.aij[pr.hyd.sm.ndx[k]] -= p
    pr.hyd.sm.aii[i] += p
    pr.hyd.sm.aii[j] += p
    pr.hyd.sm.f[i] += dy
    pr.hyd.sm.f[j] -= dy


def _prvcoeff(mut pr: Project, k: Int, n1: Int, n2: Int):
    """Add a pressure reducing valve to the matrix."""
    var i = pr.hyd.sm.row[n1]
    var j = pr.hyd.sm.row[n2]
    var hset = pr.net.node[n2].el + pr.hyd.link_setting[k]
    if pr.hyd.link_status[k] == ACTIVE:
        pr.hyd.p[k] = 0.0
        pr.hyd.y[k] = pr.hyd.link_flow[k] + pr.hyd.xflow[n2]
        pr.hyd.sm.f[j] += mul(hset, CBIG)
        pr.hyd.sm.aii[j] += CBIG
        if pr.hyd.xflow[n2] < 0.0:
            pr.hyd.sm.f[i] += pr.hyd.xflow[n2]
        return
    _add_open_valve(pr, k, i, j)


def _psvcoeff(mut pr: Project, k: Int, n1: Int, n2: Int):
    """Add a pressure sustaining valve to the matrix."""
    var i = pr.hyd.sm.row[n1]
    var j = pr.hyd.sm.row[n2]
    var hset = pr.net.node[n1].el + pr.hyd.link_setting[k]
    if pr.hyd.link_status[k] == ACTIVE:
        pr.hyd.p[k] = 0.0
        pr.hyd.y[k] = pr.hyd.link_flow[k] - pr.hyd.xflow[n1]
        pr.hyd.sm.f[i] += mul(hset, CBIG)
        pr.hyd.sm.aii[i] += CBIG
        if pr.hyd.xflow[n1] > 0.0:
            pr.hyd.sm.f[j] += pr.hyd.xflow[n1]
        pr.hyd.sm.aij[pr.hyd.sm.ndx[k]] -= 1.0 / CBIG
        pr.hyd.sm.aii[j] += 1.0 / CBIG
        return
    _add_open_valve(pr, k, i, j)


def _fcvcoeff(mut pr: Project, k: Int, n1: Int, n2: Int):
    """Add a flow control valve to the matrix."""
    var q = pr.hyd.link_setting[k]
    var i = pr.hyd.sm.row[n1]
    var j = pr.hyd.sm.row[n2]
    if pr.hyd.link_status[k] == ACTIVE:
        pr.hyd.xflow[n1] -= q
        pr.hyd.xflow[n2] += q
        pr.hyd.y[k] = pr.hyd.link_flow[k] - q
        pr.hyd.sm.f[i] -= q
        pr.hyd.sm.f[j] += q
        pr.hyd.p[k] = 1.0 / CBIG
        pr.hyd.sm.aij[pr.hyd.sm.ndx[k]] -= pr.hyd.p[k]
        pr.hyd.sm.aii[i] += pr.hyd.p[k]
        pr.hyd.sm.aii[j] += pr.hyd.p[k]
    else:
        _add_open_valve(pr, k, i, j)


def _valvecoeff(mut pr: Project, k: Int):
    """Find the head loss coefficients of an open or closed valve."""
    var flow = pr.hyd.link_flow[k]
    if pr.hyd.link_status[k].value <= CLOSED.value:
        pr.hyd.p[k] = 1.0 / CBIG
        pr.hyd.y[k] = flow
        return
    var km = pr.net.link[k].km
    if km > 0.0:
        var q = abs(flow)
        var hgrad = mul(mul(2.0, km), q)
        var hloss: Float64
        if hgrad < pr.hyd.rqtol:
            hgrad = pr.hyd.rqtol / 2.0
            hloss = mul(flow, hgrad)
        else:
            hloss = mul(flow, hgrad) / 2.0
        pr.hyd.p[k] = 1.0 / hgrad
        pr.hyd.y[k] = hloss / hgrad
    else:
        pr.hyd.p[k] = 1.0 / CSMALL
        pr.hyd.y[k] = flow
