# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from validate.c of OWA EPANET 2.3.6. Copyright (c) 2023 the EPANET
# contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The checks of a network before a hydraulic run.

`validateproject` checks the tanks, the pumps, the patterns, the curves
and the valves. It also finds the coefficients of each pump curve.
`reindextanks` closes the gap in the node array that a junction line
with an error leaves before the first tank.
"""


from extensions.epanet.cmath import clog, cpow, mul
from extensions.epanet.kinds import (
    BIG,
    CONST_HP,
    CUSTOM,
    GPV,
    NOCURVE,
    POWER_FUNC,
    PUMP_CURVE,
    TINY,
)
from extensions.epanet.model import Curve, ELEV, FLOW, HEAD, Node, Project
from extensions.epanet.ruleparse import adjusttankrules


def validtankcurve(curve: Curve) -> Bool:
    """Return True if a volume curve rises with the water depth.

    Args:
        curve: The volume curve.

    Returns:
        Whether the curve has two or more points with x and y increasing.
    """
    if curve.npts() < 2:
        return False
    for i in range(1, curve.npts()):  # pragma: no branch
        if curve.x[i] <= curve.x[i - 1] or curve.y[i] <= curve.y[i - 1]:
            return False
    return True


def validatetanks(pr: Project, mut errors: List[String]) -> Bool:
    """Check the levels and the volume curves of the tanks.

    Args:
        pr: The project.
        errors: Receives a message for each tank with an error.

    Returns:
        Whether all tanks are valid.
    """
    var result = True
    # `validatenetwork` has checked that there is a tank or a reservoir.
    for j in range(1, pr.net.ntanks + 1):  # pragma: no branch
        ref tank = pr.net.tank[j]
        if tank.a == 0.0:
            continue
        var levelerr = (
            tank.h0 > tank.hmax or tank.hmin > tank.hmax or tank.h0 < tank.hmin
        )
        var elev = pr.net.node[tank.node].el
        var i = tank.vcurve
        if i > 0:
            ref curve = pr.net.curve[i]
            if not validtankcurve(curve):
                errors.append(_msg(228, "node", pr.net.node[tank.node].id))
                result = False
                continue
            var n = curve.npts() - 1
            if (
                mul(tank.hmin - elev, pr.ucf[ELEV]) < curve.x[0] - TINY
                or mul(tank.hmax - elev, pr.ucf[ELEV]) > curve.x[n] + TINY
            ):
                levelerr = True
        if levelerr:
            errors.append(_msg(225, "node", pr.net.node[tank.node].id))
            result = False
    return result


def _msg(code: Int, kind: String, id: String) -> String:
    """Return the message of a validation error."""
    return String("Error ", code, ": ", _text(code), " ", kind, " ", id)


def _text(code: Int) -> String:
    """Return the text of a validation error code."""
    if code == 206:
        return "undefined curve for GPV"
    if code == 225:
        return "invalid lower/upper levels for tank"
    if code == 226:
        return "no head curve or power rating for pump"
    if code == 227:
        return "invalid head curve for pump"
    if code == 228:
        return "invalid volume curve for tank"
    if code == 230:
        return "nonincreasing x-values for curve"
    return "no data provided for curve"


def validatecurves(pr: Project, mut errors: List[String]) -> Bool:
    """Check that each curve has data with increasing x values.

    Args:
        pr: The project.
        errors: Receives a message for each curve with an error.

    Returns:
        Whether all curves are valid.
    """
    var result = True
    for j in range(1, pr.net.ncurves + 1):
        ref curve = pr.net.curve[j]
        # Each curve has a line of data: `netsize` finds a curve there.
        var npts = curve.npts()
        for i in range(1, npts):
            if curve.x[i - 1] >= curve.x[i]:
                errors.append(_msg(230, "curve", curve.id))
                result = False
                break
    return result


def validatevalves(pr: Project, mut errors: List[String]) -> Bool:
    """Check that each GPV has a head loss curve of two or more points.

    Args:
        pr: The project.
        errors: Receives a message for each GPV with an error.

    Returns:
        Whether all GPVs are valid.
    """
    var result = True
    for i in range(1, pr.net.nvalves + 1):
        ref link = pr.net.link[pr.net.valve[i].link]
        if link.type != GPV:
            continue
        var c = pr.net.valve[i].curve
        if c < 1:
            errors.append(_msg(206, "link", link.id))
            result = False
        elif pr.net.curve[c].npts() == 1:
            errors.append(_msg(231, "curve", pr.net.curve[c].id))
            result = False
    return result


def powerfuncpump(
    h0: Float64,
    h1: Float64,
    h2: Float64,
    q1: Float64,
    q2: Float64,
    mut a: Float64,
    mut b: Float64,
    mut c: Float64,
) -> Bool:
    """Find the coefficients of a power function pump curve H = a - b Q^c.

    Args:
        h0: The shutoff head.
        h1: The design head.
        h2: The head at the maximum flow.
        q1: The design flow.
        q2: The maximum flow.
        a: Receives the shutoff head.
        b: Receives the coefficient, which is negative.
        c: Receives the exponent.

    Returns:
        Whether the points make a valid curve.
    """
    if (
        h0 < TINY
        or h0 - h1 < TINY
        or h1 - h2 < TINY
        or q1 < TINY
        or q2 - q1 < TINY
    ):
        return False
    a = h0
    var h4 = h0 - h1
    var h5 = h0 - h2
    # h5 > h4 > 0 and q2 > q1 > 0, so c > 0 and b < 0.
    c = clog(h5 / h4) / clog(q2 / q1)
    if c > 20.0:
        return False
    b = -h4 / cpow(q1, c)
    return True


def updatepumpparams(mut pr: Project, i: Int) -> Int:
    """Find the curve coefficients of a pump.

    Args:
        pr: The project.
        i: The pump index.

    Returns:
        0, or error 226 for a pump with no curve and no power, or 227
        for a pump with an invalid curve.
    """
    var hcurve = pr.net.pump[i].hcurve
    if hcurve > 0:
        return _pumpcurvepump(pr, i, hcurve)
    var km = pr.net.link[pr.net.pump[i].link].km
    ref pump = pr.net.pump[i]
    if km > 0.0:
        pump.ptype = CONST_HP
        pump.h0 = 0.0
        pump.r = mul(-8.814, km)
        pump.n = -1.0
        pump.hmax = BIG
        pump.qmax = BIG
        pump.q0 = 1.0
        return 0
    pump.ptype = NOCURVE
    return 226


def _pumpcurvepump(mut pr: Project, i: Int, ci: Int) -> Int:
    """Find the coefficients of a pump from its head curve."""
    var ucf_flow = pr.ucf[FLOW]
    var ucf_head = pr.ucf[HEAD]
    ref curve = pr.net.curve[ci]
    ref pump = pr.net.pump[i]
    curve.type = PUMP_CURVE
    var npts = curve.npts()
    var h0: Float64
    var h1: Float64
    var h2: Float64
    var q1: Float64
    var q2: Float64
    if npts == 1:
        pump.ptype = POWER_FUNC
        q1 = curve.x[0]
        h1 = curve.y[0]
        h0 = mul(1.33334, h1)
        q2 = mul(2.0, q1)
        h2 = 0.0
    elif npts == 3 and curve.x[0] == 0.0:
        pump.ptype = POWER_FUNC
        h0 = curve.y[0]
        q1 = curve.x[1]
        h1 = curve.y[1]
        q2 = curve.x[2]
        h2 = curve.y[2]
    else:
        pump.ptype = CUSTOM
        for m in range(1, npts):  # pragma: no branch
            if curve.y[m] >= curve.y[m - 1]:
                pump.ptype = NOCURVE
                return 227
        pump.qmax = curve.x[npts - 1]
        pump.q0 = (curve.x[0] + pump.qmax) / 2.0 / ucf_flow
        pump.qmax /= ucf_flow
        pump.hmax = curve.y[0] / ucf_head
        return 0
    var a = 0.0
    var b = 0.0
    var c = 0.0
    if not powerfuncpump(h0, h1, h2, q1, q2, a, b, c):
        pump.ptype = NOCURVE
        return 227
    pump.h0 = -a / ucf_head
    pump.r = mul(-b, cpow(ucf_flow, c) / ucf_head)
    pump.n = c
    pump.q0 = q1 / ucf_flow
    pump.qmax = cpow(-a / b, 1.0 / c) / ucf_flow
    pump.hmax = h0 / ucf_head
    return 0


def validatepumps(mut pr: Project, mut errors: List[String]) -> Bool:
    """Find the curve coefficients of each pump and check them.

    Args:
        pr: The project.
        errors: Receives a message for each pump with an error.

    Returns:
        Whether all pumps are valid.
    """
    var result = True
    for i in range(1, pr.net.npumps + 1):
        var errcode = updatepumpparams(pr, i)
        if errcode != 0:
            errors.append(
                _msg(errcode, "link", pr.net.link[pr.net.pump[i].link].id)
            )
            result = False
    return result


def validateproject(mut pr: Project, mut errors: List[String]) -> Int:
    """Check the network data before a hydraulic run.

    Args:
        pr: The project.
        errors: Receives a message for each object with an error.

    Returns:
        0, error 223 for fewer than two nodes, 224 for no tank or
        reservoir, or 110 for any other error.
    """
    if pr.net.nnodes < 2:
        return 223
    if pr.net.ntanks == 0:
        return 224
    var errcode = 0
    if not validatetanks(pr, errors):
        errcode = 110
    if not validatepumps(pr, errors):
        errcode = 110
    if not validatecurves(pr, errors):
        errcode = 110
    if not validatevalves(pr, errors):
        errcode = 110
    return errcode


def reindextanks(mut pr: Project):
    """Move the tank nodes down to follow the junctions directly.

    A junction line with an error leaves fewer junctions than junction
    lines, and so a gap before the first tank node.

    Args:
        pr: The project, after `readdata`.
    """
    var ndiff = pr.parser.max_juncs - pr.net.njuncs
    if ndiff <= 0:
        return
    for i in range(1, pr.net.ntanks + 1):
        var n1 = pr.net.tank[i].node
        var n2 = n1 - ndiff
        pr.net.node_index[pr.net.node[n1].id] = n2
        pr.net.tank[i].node = n2
        pr.net.node[n2] = pr.net.node[n1].copy()
        for j in range(1, pr.net.nlinks + 1):
            if pr.net.link[j].n1 == n1:
                pr.net.link[j].n1 = n2
            if pr.net.link[j].n2 == n1:
                pr.net.link[j].n2 = n2
        for j in range(1, pr.net.ncontrols + 1):
            if pr.net.control[j].node == n1:
                pr.net.control[j].node = n2
        if pr.qual.trace_node == n1:
            pr.qual.trace_node = n2
    adjusttankrules(pr, -ndiff)
    pr.parser.max_juncs = pr.net.njuncs
    pr.parser.max_nodes = pr.net.njuncs + pr.net.ntanks
    var size = pr.net.nnodes + 2
    while len(pr.net.node) > size:
        _ = pr.net.node.pop()
