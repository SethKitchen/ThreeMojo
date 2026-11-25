# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from leakage.c of OWA EPANET 2.3.6. Copyright (c) 2023 the EPANET
# contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The leakage demands of leaky pipes (leakage.c).

A pipe leak follows the FAVAD equation Q = Co (Ao + m H) sqrt(H). The
leak of each pipe goes to its end junctions as two equivalent emitters,
H = Cfa Qfa^2 for the fixed area and H = Cva Qva^(2/3) for the variable
area.
"""

from std.math import sqrt

from extensions.epanet.cmath import cpow, mul
from extensions.epanet.kinds import JUNCTION, M_PER_FT, PIPE
from extensions.epanet.model import Leakage, Project

comptime _QTOL = 0.0001


def openleakage(mut pr: Project):
    """Find the leakage coefficients of the junctions.

    Args:
        pr: The project.
    """
    pr.hyd.leakage = List[Leakage]()
    pr.hyd.has_leakage = False
    for i in range(len(pr.hyd.leakage_flow)):  # pragma: no branch
        pr.hyd.leakage_flow[i] = 0.0
    pr.hyd.has_leakage = _check_for_leakage(pr)
    if not pr.hyd.has_leakage:
        return
    for _ in range(pr.net.njuncs + 1):  # pragma: no branch
        pr.hyd.leakage.append(Leakage(0.0, 0.0, 0.0, 0.0))
    _convert_pipe_to_node_leakage(pr)
    _init_node_leakage(pr)


def _check_for_leakage(pr: Project) -> Bool:
    """Return True if a pipe has a leak area or a leak expansion."""
    for i in range(1, pr.net.nlinks + 1):
        ref link = pr.net.link[i]
        if link.type.value > PIPE.value:
            continue
        if link.leak_area > 0.0 or link.leak_expan > 0.0:
            return True
    return False


def _convert_pipe_to_node_leakage(mut pr: Project):
    """Add the leak coefficients of each pipe to its end junctions."""
    var c_orif = mul(4.8149766, 1.0e-6)
    # `openleakage` calls this only when a pipe leaks.
    for i in range(1, pr.net.nlinks + 1):  # pragma: no branch
        var link = pr.net.link[i].copy()
        if link.type.value > PIPE.value:
            continue
        var j1 = pr.net.node[link.n1].type == JUNCTION
        var j2 = pr.net.node[link.n2].type == JUNCTION
        if not j1 and not j2:
            continue
        if link.leak_area == 0.0 and link.leak_expan == 0.0:
            continue
        var c_area = mul(c_orif, link.leak_area) / mul(M_PER_FT, M_PER_FT)
        var c_expan = mul(c_orif, link.leak_expan) / M_PER_FT
        var len = link.len / 100.0
        if j1 and j2:
            len *= 0.5
        c_area *= len
        c_expan *= len
        if j1:
            pr.hyd.leakage[link.n1].cfa += c_area
            pr.hyd.leakage[link.n1].cva += c_expan
        if j2:
            pr.hyd.leakage[link.n2].cfa += c_area
            pr.hyd.leakage[link.n2].cva += c_expan


def _init_node_leakage(mut pr: Project):
    """Turn the summed coefficients into emitter coefficients."""
    for i in range(1, pr.net.njuncs + 1):
        ref lk = pr.hyd.leakage[i]
        var c_area = lk.cfa
        if c_area > 0.0:
            lk.cfa = 1.0 / mul(c_area, c_area)
        else:
            lk.cfa = 0.0
        var c_expan = lk.cva
        if c_expan > 0.0:
            lk.cva = 1.0 / cpow(c_expan, 2.0 / 3.0)
        else:
            lk.cva = 0.0
        if lk.cfa > 0.0:
            lk.qfa = 0.001
        if lk.cva > 0.0:
            lk.qva = 0.001


def leakagecoeffs(mut pr: Project):
    """Add the leakage terms to the matrix of the hydraulic equations.

    Args:
        pr: The project.
    """
    var hfa = 0.0
    var gfa = 0.0
    var hva = 0.0
    var gva = 0.0
    for i in range(1, pr.net.njuncs + 1):
        if not _leakage_headloss(pr, i, hfa, gfa, hva, gva):
            continue
        var el = pr.net.node[i].el
        var row = pr.hyd.sm.row[i]
        if gfa > 0.0:
            pr.hyd.sm.aii[row] += 1.0 / gfa
            pr.hyd.sm.f[row] += (hfa + el) / gfa
        if gva > 0.0:
            pr.hyd.sm.aii[row] += 1.0 / gva
            pr.hyd.sm.f[row] += (hva + el) / gva
        pr.hyd.xflow[i] -= pr.hyd.leakage[i].qfa + pr.hyd.leakage[i].qva


def leakageflowchange(mut pr: Project, i: Int) -> Float64:
    """Update the leakage flow of a junction from the new heads.

    Args:
        pr: The project.
        i: The junction index.

    Returns:
        The change of the leakage flow.
    """
    var hfa = 0.0
    var gfa = 0.0
    var hva = 0.0
    var gva = 0.0
    if not _leakage_headloss(pr, i, hfa, gfa, hva, gva):
        return 0.0
    var h = pr.hyd.node_head[i] - pr.net.node[i].el
    var relax = pr.hyd.relax_factor
    var dqfa = 0.0
    if gfa > 0.0:
        dqfa = mul((hfa - h) / gfa, relax)
        pr.hyd.leakage[i].qfa -= dqfa
    var dqva = 0.0
    if gva > 0.0:
        dqva = mul((hva - h) / gva, relax)
        pr.hyd.leakage[i].qva -= dqva
    pr.hyd.leakage_flow[i] = pr.hyd.leakage[i].qfa + pr.hyd.leakage[i].qva
    return dqfa + dqva


def leakagehasconverged(pr: Project) -> Bool:
    """Return True if each leakage flow matches its head.

    Args:
        pr: The project.

    Returns:
        Whether each leakage flow is within 0.0001 cfs of its value at
        the current head.
    """
    for i in range(1, pr.net.njuncs + 1):
        ref lk = pr.hyd.leakage[i]
        if lk.cfa == 0.0 and lk.cva == 0.0:
            continue
        var h = pr.hyd.node_head[i] - pr.net.node[i].el
        var qref = 0.0
        if h > 0.0:
            if lk.cfa > 0.0:
                qref = sqrt(h / lk.cfa)
            if lk.cva > 0.0:
                qref += cpow(h / lk.cva, 1.5)
        var qtest = lk.qfa + lk.qva
        if abs(qref - qtest) > _QTOL:
            return False
    return True


def _leakage_headloss(
    pr: Project,
    i: Int,
    mut hfa: Float64,
    mut gfa: Float64,
    mut hva: Float64,
    mut gva: Float64,
) -> Bool:
    """Find the head loss and gradient of the two leakage emitters."""
    ref lk = pr.hyd.leakage[i]
    if lk.cfa == 0.0 and lk.cva == 0.0:
        return False
    if lk.cfa == 0.0:
        hfa = 0.0
        gfa = 0.0
    else:
        _eval_leak_headloss(lk.qfa, lk.cfa, 0.5, hfa, gfa)
    if lk.cva == 0.0:
        hva = 0.0
        gva = 0.0
    else:
        _eval_leak_headloss(lk.qva, lk.cva, 1.5, hva, gva)
    return True


def _eval_leak_headloss(
    q: Float64,
    c: Float64,
    n0: Float64,
    mut hloss: Float64,
    mut hgrad: Float64,
):
    """Find the head loss of an emitter H = c q^(1/n0) and its gradient."""
    var n = 1.0 / n0
    hgrad = mul(mul(n, c), cpow(abs(q), n - 1.0))
    hloss = mul(hgrad, q) / n
    var a = mul(1.0e9, q)
    var b = sqrt(mul(a, a) + 1.0e-6)
    hloss += (a - b) / 2.0
    hgrad += mul(1.0e9 / 2.0, 1.0 - a / b)
