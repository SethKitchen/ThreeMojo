# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from rules.c of OWA EPANET 2.3.6. Copyright (c) 2023 the EPANET
# contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The evaluation of rule-based controls (rules.c).

`checkrules` tests the premises of each enabled rule. The actions of the
rules that fire go on an action list, one action for each link: a rule
of higher priority replaces the action of a rule of lower priority.
Then the actions that change a link are taken.
"""

from extensions.epanet.cmath import mul
from extensions.epanet.hydbase import setlinksetting, setlinkstatus
from extensions.epanet.kinds import (
    ACTIVE,
    CLOSED,
    FCV,
    MISSING,
    PBV,
    PRV,
    PSV,
    SEC_PER_DAY,
    TINY,
)
from extensions.epanet.model import (
    DEMAND,
    FLOW,
    HEAD,
    PRESSURE,
    Premise,
    Project,
)
from extensions.epanet.ruleparse import (
    EQ,
    GE,
    GT,
    IS_ACTIVE,
    IS_CLOSED,
    IS_NUMBER,
    IS_OPEN,
    LE,
    LT,
    NE,
    R_CLOCKTIME,
    R_DEMAND,
    R_DRAINTIME,
    R_FILLTIME,
    R_FLOW,
    R_GRADE,
    R_HEAD,
    R_LEVEL,
    R_OR,
    R_PRESSURE,
    R_SETTING,
    R_SYSTEM,
    R_TIME,
)


@fieldwise_init
struct _ActionItem(Copyable, Movable):
    """An action on the action list and the rule that gives it."""

    var rule: Int
    var action: Int
    var is_then: Bool


def checkrules(mut pr: Project, dt: Int) -> Int:
    """Evaluate the rules over the last time step and take their actions.

    Args:
        pr: The project.
        dt: The length of the time step, in seconds.

    Returns:
        The number of actions that changed a link.
    """
    pr.rules.time1 = pr.times.htime - dt + 1
    var items = List[_ActionItem]()
    # `_ruletimestep` calls this only when there are rules.
    for i in range(1, pr.net.nrules + 1):  # pragma: no branch
        if not pr.net.rule[i].is_enabled:
            continue
        if _evalpremises(pr, i):
            _updateactionlist(pr, items, i, True)
        else:
            _updateactionlist(pr, items, i, False)
    if len(items) == 0:
        return 0
    return _takeactions(pr, items)


def _evalpremises(pr: Project, i: Int) -> Bool:
    """Return True if the premises of a rule hold."""
    var result = True
    for p in pr.net.rule[i].premises:
        if p.logop == R_OR:
            if not result:
                result = _checkpremise(pr, p)
        else:
            if not result:
                return False
            result = _checkpremise(pr, p)
    return result


def _checkpremise(pr: Project, p: Premise) -> Bool:
    """Return True if a premise holds."""
    if p.variable == R_TIME or p.variable == R_CLOCKTIME:
        return _checktime(pr, p)
    elif p.status > IS_NUMBER:
        return _checkstatus(pr, p)
    return _checkvalue(pr, p)


def _checktime(pr: Project, p: Premise) -> Bool:
    """Return True if a time premise holds over the time step."""
    var t1: Int
    var t2: Int
    if p.variable == R_TIME:
        t1 = pr.rules.time1
        t2 = pr.times.htime
    else:
        t1 = (pr.rules.time1 + pr.times.tstart) % SEC_PER_DAY
        t2 = (pr.times.htime + pr.times.tstart) % SEC_PER_DAY
    var x = p.value
    var f1 = Float64(t1)
    var f2 = Float64(t2)
    if p.relop == LT:
        if f2 >= x:
            return False
    elif p.relop == LE:
        if f2 > x:
            return False
    elif p.relop == GT:
        if f2 <= x:
            return False
    elif p.relop == GE:
        if f2 < x:
            return False
    else:
        # EQ or NE: the time is within the time step, or is not.
        var flag = False
        if t2 < t1:
            if x >= f1 or x <= f2:
                flag = True
        else:
            if x >= f1 and x <= f2:
                flag = True
        if p.relop == EQ and not flag:
            return False
        if p.relop == NE and flag:
            return False
    return True


def _checkstatus(pr: Project, p: Premise) -> Bool:
    """Return True if a link status premise holds.

    `_checkpremise` calls this for a status of OPEN, CLOSED or ACTIVE.
    """
    var i = pr.hyd.link_status[p.index]
    var j: Int
    if i.value <= CLOSED.value:
        j = IS_CLOSED
    elif i == ACTIVE:
        j = IS_ACTIVE
    else:
        j = IS_OPEN
    if j == p.status and p.relop == EQ:
        return True
    if j != p.status and p.relop == NE:
        return True
    return False


def _checkvalue(pr: Project, p: Premise) -> Bool:
    """Return True if a numeric premise holds."""
    comptime tol = 1.0e-3
    var i = p.index
    var v = p.variable
    var njuncs = pr.net.njuncs
    var x: Float64
    if v == R_DEMAND:
        if p.object == R_SYSTEM:
            x = mul(pr.hyd.dsystem, pr.ucf[DEMAND])
        else:
            x = mul(pr.hyd.node_demand[i], pr.ucf[DEMAND])
    elif v == R_HEAD or v == R_GRADE:
        x = mul(pr.hyd.node_head[i], pr.ucf[HEAD])
    elif v == R_PRESSURE:
        x = mul(pr.hyd.node_head[i] - pr.net.node[i].el, pr.ucf[PRESSURE])
    elif v == R_LEVEL:
        x = mul(pr.hyd.node_head[i] - pr.net.node[i].el, pr.ucf[HEAD])
    elif v == R_FLOW:
        x = mul(abs(pr.hyd.link_flow[i]), pr.ucf[FLOW])
    elif v == R_SETTING:
        if pr.hyd.link_setting[i] == MISSING:
            return False
        x = pr.hyd.link_setting[i]
        var t = pr.net.link[i].type
        if t == PRV or t == PSV or t == PBV:
            x = mul(x, pr.ucf[PRESSURE])
        elif t == FCV:
            x = mul(x, pr.ucf[FLOW])
    elif v == R_FILLTIME:
        # `newpremise` refuses a fill or drain time for a junction.
        var j = i - njuncs
        if pr.net.tank[j].a == 0.0:
            return False
        if pr.hyd.node_demand[i] <= TINY:
            return False
        x = (pr.net.tank[j].vmax - pr.net.tank[j].v) / pr.hyd.node_demand[i]
    elif v == R_DRAINTIME:
        var j = i - njuncs
        if pr.net.tank[j].a == 0.0:
            return False
        if pr.hyd.node_demand[i] >= -TINY:
            return False
        x = (pr.net.tank[j].vmin - pr.net.tank[j].v) / pr.hyd.node_demand[i]
    else:
        return False
    var r = p.relop
    if r == EQ:
        if abs(x - p.value) > tol:
            return False
    elif r == NE:
        if abs(x - p.value) < tol:
            return False
    elif r == LT:
        if x > p.value + tol:
            return False
    elif r == LE:
        if x > p.value - tol:
            return False
    elif r == GT:
        if x < p.value - tol:
            return False
    else:
        # GE: the six relations are the only ones.
        if x < p.value + tol:
            return False
    return True


def _action_link(pr: Project, item: _ActionItem) -> Int:
    """Return the link of an action on the list."""
    if item.is_then:
        return pr.net.rule[item.rule].then_actions[item.action].link
    return pr.net.rule[item.rule].else_actions[item.action].link


def _updateactionlist(
    pr: Project, mut items: List[_ActionItem], i: Int, is_then: Bool
):
    """Put the THEN or ELSE actions of a rule on the action list."""
    var n: Int
    if is_then:
        n = len(pr.net.rule[i].then_actions)
    else:
        n = len(pr.net.rule[i].else_actions)
    for a in range(n):
        var item = _ActionItem(i, a, is_then)
        var link = _action_link(pr, item)
        var found = False
        for ref other in items:
            if _action_link(pr, other) == link:
                if pr.net.rule[i].priority > pr.net.rule[other.rule].priority:
                    other = item.copy()
                found = True
                break
        if not found:
            # The C code puts a new item at the head of its list.
            items.insert(0, item^)


def _takeactions(mut pr: Project, items: List[_ActionItem]) -> Int:
    """Take the actions that change a link and count them."""
    comptime tol = 1.0e-3
    var n = 0
    for item in items:  # pragma: no branch
        var status: Int
        var setting: Float64
        var k: Int
        if item.is_then:
            ref a = pr.net.rule[item.rule].then_actions[item.action]
            status = a.status
            setting = a.setting
            k = a.link
        else:
            ref a = pr.net.rule[item.rule].else_actions[item.action]
            status = a.status
            setting = a.setting
            k = a.link
        var s = pr.hyd.link_status[k]
        var v = pr.hyd.link_setting[k]
        var x = setting
        var flag = False
        if status == IS_OPEN and s.value <= CLOSED.value:
            setlinkstatus(pr, k, 1)
            flag = True
        elif status == IS_CLOSED and s.value > CLOSED.value:
            setlinkstatus(pr, k, 0)
            flag = True
        elif x != MISSING:
            var t = pr.net.link[k].type
            if t == PRV or t == PSV or t == PBV:
                x = x / pr.ucf[PRESSURE]
            elif t == FCV:
                x = x / pr.ucf[FLOW]
            if abs(x - v) > tol:
                setlinksetting(pr, k, x)
                flag = True
        if flag:
            n += 1
    return n
