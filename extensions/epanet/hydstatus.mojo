# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from hydstatus.c of OWA EPANET 2.3.6. Copyright (c) 2023 the
# EPANET contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The status checks of links during a hydraulic solution (hydstatus.c).

`valvestatus` updates the pressure reducing and sustaining valves.
`linkstatus` updates the check valves, the pumps, the flow control
valves and the links into full or empty tanks.
"""

from extensions.epanet.cmath import mul
from extensions.epanet.kinds import (
    ACTIVE,
    BIG,
    CLOSED,
    CONST_HP,
    CVPIPE,
    FCV,
    MISSING,
    OPEN,
    PRV,
    PSV,
    PUMP,
    StatusType,
    TEMPCLOSED,
    TINY,
    XFCV,
    XHEAD,
    XPRESSURE,
)
from extensions.epanet.lookup import findpump
from extensions.epanet.model import Project


def valvestatus(mut pr: Project) -> Bool:
    """Update the status of each pressure reducing and sustaining valve.

    Args:
        pr: The project.

    Returns:
        Whether a status changed.
    """
    var change = False
    for i in range(1, pr.net.nvalves + 1):
        var k = pr.net.valve[i].link
        if pr.hyd.link_setting[k] == MISSING:
            continue
        var n1 = pr.net.link[k].n1
        var n2 = pr.net.link[k].n2
        var status = pr.hyd.link_status[k]
        var t = pr.net.link[k].type
        var h1 = pr.hyd.node_head[n1]
        var h2 = pr.hyd.node_head[n2]
        if t == PRV:
            var hset = pr.net.node[n2].el + pr.hyd.link_setting[k]
            pr.hyd.link_status[k] = _prvstatus(pr, k, status, hset, h1, h2)
        elif t == PSV:
            var hset = pr.net.node[n1].el + pr.hyd.link_setting[k]
            pr.hyd.link_status[k] = _psvstatus(pr, k, status, hset, h1, h2)
        else:
            continue
        if status != pr.hyd.link_status[k]:
            change = True
    return change


def linkstatus(mut pr: Project) -> Bool:
    """Update the status of the links that change with the flow.

    Args:
        pr: The project.

    Returns:
        Whether a status changed.
    """
    var change = False
    var njuncs = pr.net.njuncs
    for k in range(1, pr.net.nlinks + 1):
        var n1 = pr.net.link[k].n1
        var n2 = pr.net.link[k].n2
        var h1 = pr.hyd.node_head[n1]
        var h2 = pr.hyd.node_head[n2]
        var dh = h1 - h2
        var status = pr.hyd.link_status[k]
        var t = pr.net.link[k].type
        if status == XHEAD or status == TEMPCLOSED:
            pr.hyd.link_status[k] = OPEN
        if t == CVPIPE:
            pr.hyd.link_status[k] = _cvstatus(
                pr, pr.hyd.link_status[k], dh, pr.hyd.link_flow[k]
            )
        if (
            t == PUMP
            and pr.hyd.link_status[k].value >= OPEN.value
            and pr.hyd.link_setting[k] > 0.0
        ):
            pr.hyd.link_status[k] = _pumpstatus(pr, k, -dh)
        if t == FCV and pr.hyd.link_setting[k] != MISSING:
            pr.hyd.link_status[k] = _fcvstatus(pr, k, status, h1, h2)
        if n1 > njuncs:
            _tankstatus(pr, k, n1, pr.hyd.link_flow[k])
        if n2 > njuncs:
            _tankstatus(pr, k, n2, -pr.hyd.link_flow[k])
        if status != pr.hyd.link_status[k]:
            change = True
    return change


def _cvstatus(
    pr: Project, s: StatusType, dh: Float64, q: Float64
) -> StatusType:
    """Return the new status of a check valve."""
    var htol = pr.hyd.htol
    var qtol = pr.hyd.qtol
    if abs(dh) > htol:
        if dh < -htol:
            return CLOSED
        elif q < -qtol:
            return CLOSED
        return OPEN
    if q < -qtol:
        return CLOSED
    return s


def _pumpstatus(pr: Project, k: Int, dh: Float64) -> StatusType:
    """Return the new status of a pump from its head gain."""
    var p = findpump(pr.net, k)
    var hmax: Float64
    if pr.net.pump[p].ptype == CONST_HP:
        hmax = BIG
        if pr.hyd.link_flow[k] < TINY:
            return TEMPCLOSED
    else:
        var s = pr.hyd.link_setting[k]
        hmax = mul(mul(s, s), pr.net.pump[p].hmax)
    if dh > hmax + pr.hyd.htol:
        return XHEAD
    return OPEN


def _prvstatus(
    pr: Project,
    k: Int,
    s: StatusType,
    hset: Float64,
    h1: Float64,
    h2: Float64,
) -> StatusType:
    """Return the new status of a pressure reducing valve."""
    var htol = pr.hyd.htol
    var q = pr.hyd.link_flow[k]
    var hml = mul(pr.net.link[k].km, mul(q, q))
    var qtol = pr.hyd.qtol
    if s == ACTIVE:
        if q < -qtol:
            return CLOSED
        elif h1 - hml < hset - htol:
            return OPEN
        return ACTIVE
    if s == OPEN:
        if q < -qtol:
            return CLOSED
        elif h2 >= hset + htol:
            return ACTIVE
        return OPEN
    if s == CLOSED:
        if h1 >= hset + htol and h2 < hset - htol:
            return ACTIVE
        elif h1 < hset - htol and h1 > h2 + htol:
            return OPEN
        return CLOSED
    # `valvedata` refuses a valve on a tank, so no tank closes this valve
    # and the status left is XPRESSURE.
    if q < -qtol:
        return CLOSED
    return s


def _psvstatus(
    pr: Project,
    k: Int,
    s: StatusType,
    hset: Float64,
    h1: Float64,
    h2: Float64,
) -> StatusType:
    """Return the new status of a pressure sustaining valve."""
    var htol = pr.hyd.htol
    var q = pr.hyd.link_flow[k]
    var hml = mul(pr.net.link[k].km, mul(q, q))
    var qtol = pr.hyd.qtol
    if s == ACTIVE:
        if q < -qtol:
            return CLOSED
        elif h2 + hml > hset + htol:
            return OPEN
        return ACTIVE
    if s == OPEN:
        if q < -qtol:
            return CLOSED
        elif h1 < hset - htol:
            return ACTIVE
        return OPEN
    if s == CLOSED:
        if h2 > hset + htol and h1 > h2 + htol:
            return OPEN
        elif h1 >= hset + htol and h1 > h2 + htol:
            return ACTIVE
        return CLOSED
    # As for a PRV, the status left is XPRESSURE.
    if q < -qtol:
        return CLOSED
    return s


def _fcvstatus(
    pr: Project, k: Int, s: StatusType, h1: Float64, h2: Float64
) -> StatusType:
    """Return the new status of a flow control valve."""
    var q = pr.hyd.link_flow[k]
    if h1 - h2 < -pr.hyd.htol:
        return XFCV
    elif q < -pr.hyd.qtol:
        return XFCV
    elif s == XFCV and q >= pr.hyd.link_setting[k]:
        return ACTIVE
    elif s == ACTIVE:
        if (h1 - h2) / mul(q, q) < pr.net.link[k].km:
            return XFCV
    return s


def _tankstatus(mut pr: Project, k: Int, n: Int, q: Float64):
    """Close a link into a full tank or out of an empty tank."""
    if pr.hyd.link_status[k].value <= CLOSED.value:
        return
    var i = n - pr.net.njuncs
    ref tank = pr.net.tank[i]
    if tank.a == 0.0:
        return
    if tank.v >= tank.vmax and not tank.can_overflow and q < 0.0:
        pr.hyd.link_status[k] = TEMPCLOSED
    elif tank.v <= tank.vmin and q > 0.0:
        pr.hyd.link_status[k] = TEMPCLOSED
