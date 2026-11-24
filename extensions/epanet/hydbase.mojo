# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from hydraul.c of OWA EPANET 2.3.6. Copyright (c) 2023 the EPANET
# contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The link and tank helpers of the hydraulic engine (hydraul.c).

The controls, the rules and the time steps share these functions: they
open, close and set links, and they convert between tank volume and
tank head.
"""

from std.math import pi

from extensions.epanet.cmath import mul
from extensions.epanet.coeffs import pcvlosscoeff
from extensions.epanet.kinds import (
    ACTIVE,
    CLOSED,
    CONST_HP,
    FCV,
    GPV,
    MISSING,
    OPEN,
    PCV,
    PUMP,
    StatusType,
)
from extensions.epanet.lookup import findpump, interp
from extensions.epanet.model import HEAD, Project, VOLUME

comptime QZERO = 1.0e-6


def initlinkflow(mut pr: Project, i: Int, s: StatusType, k: Float64):
    """Set the starting flow of a link.

    Args:
        pr: The project.
        i: The link index.
        s: The link status.
        k: The link setting.
    """
    if s == CLOSED:
        pr.hyd.link_flow[i] = QZERO
    elif pr.net.link[i].type == PUMP:
        pr.hyd.link_flow[i] = mul(k, pr.net.pump[findpump(pr.net, i)].q0)
    else:
        var d = pr.net.link[i].diam
        pr.hyd.link_flow[i] = mul(pi, mul(d, d)) / 4.0


def resetpumpflow(mut pr: Project, i: Int):
    """Reset the flow of a constant power pump that starts.

    Args:
        pr: The project.
        i: The link index of the pump.
    """
    ref pump = pr.net.pump[findpump(pr.net, i)]
    if pump.ptype == CONST_HP:
        pr.hyd.link_flow[i] = pump.q0


def setlinkstatus(mut pr: Project, index: Int, value: Int):
    """Open or close a link.

    Args:
        pr: The project.
        index: The link index.
        value: 1 to open the link, 0 to close it. The rules give no
            other value.
    """
    var t = pr.net.link[index].type
    if value == 1:
        if t == PUMP:
            pr.hyd.link_setting[index] = 1.0
            if pr.hyd.link_status[index] == CLOSED:
                resetpumpflow(pr, index)
        if t.value > PUMP.value and t != GPV:
            pr.hyd.link_setting[index] = MISSING
        pr.hyd.link_status[index] = OPEN
    else:
        if t == PUMP:
            pr.hyd.link_setting[index] = 0.0
        if t.value > PUMP.value and t != GPV:
            pr.hyd.link_setting[index] = MISSING
        pr.hyd.link_status[index] = CLOSED


def setlinksetting(mut pr: Project, index: Int, value0: Float64):
    """Change the setting of a link.

    Args:
        pr: The project.
        index: The link index.
        value0: The new setting.
    """
    var value = value0
    var t = pr.net.link[index].type
    if t == PUMP:
        if value < 0.0:
            value = 0.0
        pr.hyd.link_setting[index] = value
        if value > 0.0 and pr.hyd.link_status[index].value <= CLOSED.value:
            resetpumpflow(pr, index)
            pr.hyd.link_status[index] = OPEN
        if value == 0.0 and pr.hyd.link_status[index].value > CLOSED.value:
            pr.hyd.link_status[index] = CLOSED
    elif t == FCV:
        pr.hyd.link_setting[index] = value
        pr.hyd.link_status[index] = ACTIVE
    else:
        if (
            pr.hyd.link_setting[index] == MISSING
            and pr.hyd.link_status[index].value <= CLOSED.value
        ):
            pr.hyd.link_status[index] = OPEN
        if t == PCV:
            pr.net.link[index].r = pcvlosscoeff(pr, index, value)
        pr.hyd.link_setting[index] = value


def tankvolume(pr: Project, i: Int, h: Float64) -> Float64:
    """Return the volume of a tank at a head.

    Args:
        pr: The project.
        i: The tank index.
        h: The head, in feet.

    Returns:
        The volume, in cubic feet.
    """
    ref tank = pr.net.tank[i]
    var j = tank.vcurve
    if j == 0:
        return tank.vmin + mul(h - tank.hmin, tank.a)
    ref curve = pr.net.curve[j]
    var y = mul(h - pr.net.node[tank.node].el, pr.ucf[HEAD])
    return interp(curve.x, curve.y, y) / pr.ucf[VOLUME]


def tankgrade(pr: Project, i: Int, v: Float64) -> Float64:
    """Return the head of a tank at a volume.

    Args:
        pr: The project.
        i: The tank index.
        v: The volume, in cubic feet.

    Returns:
        The head, in feet.
    """
    ref tank = pr.net.tank[i]
    var j = tank.vcurve
    if j == 0:
        return tank.hmin + (v - tank.vmin) / tank.a
    ref curve = pr.net.curve[j]
    var y = interp(curve.y, curve.x, mul(v, pr.ucf[VOLUME]))
    return pr.net.node[tank.node].el + y / pr.ucf[HEAD]


def tanklevels(mut pr: Project, tstep: Int):
    """Move the tank volumes and heads forward by a time step.

    Args:
        pr: The project.
        tstep: The time step, in seconds.
    """
    for i in range(1, pr.net.ntanks + 1):  # pragma: no branch
        if pr.net.tank[i].a == 0.0:
            continue
        var n = pr.net.tank[i].node
        var q = pr.hyd.node_demand[n]
        if abs(q) <= QZERO:
            continue
        ref tank = pr.net.tank[i]
        tank.v += mul(q, Float64(tstep))
        if tank.v + q >= tank.vmax:
            tank.v = tank.vmax
        elif tank.v + q <= tank.vmin:
            tank.v = tank.vmin
        var v = tank.v
        pr.hyd.node_head[n] = tankgrade(pr, i, v)


def round_c(x: Float64) -> Int:
    """Round half up, as the ROUND macro of EPANET does for x >= 0.

    The callers divide a volume by a flow of the same sign, so x >= 0.

    Args:
        x: The number, not negative.

    Returns:
        The rounded number.
    """
    return Int(x + 0.5)
