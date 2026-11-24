# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from hydraul.c, flowbalance.c and the hydraulics file functions
# of output.c of OWA EPANET 2.3.6. Copyright (c) 2023 the EPANET
# contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The extended period hydraulic engine of EPANET (hydraul.c).

`openhyd` checks the network and builds the sparse matrix. `inithyd`
sets the starting state. Each `runhyd` applies the demands and the
controls and solves the network at the current time. `nexthyd` finds
the next time step, moves the tanks and the clock, and adds the pump
energy and the flow balance.
"""

from extensions.epanet.cmath import cpow, mul
from extensions.epanet.coeffs import pcvlosscoeff, resistcoeff
from extensions.epanet.hydbase import (
    QZERO,
    initlinkflow,
    resetpumpflow,
    round_c,
    setlinksetting,
    tankgrade,
    tanklevels,
    tankvolume,
)
from extensions.epanet.hydsolver import hydsolve
from extensions.epanet.kinds import (
    ACTIVE,
    CLOSED,
    FCV,
    GPV,
    HILEVEL,
    KW_PER_HP,
    LOWLEVEL,
    MISSING,
    OPEN,
    PCV,
    PDA,
    PIPE,
    PRV,
    PSV,
    PUMP,
    SEC_PER_DAY,
    StatusType,
    TEMPCLOSED,
    TIMEOFDAY,
    TIMER,
)
from extensions.epanet.leakage import openleakage
from extensions.epanet.lookup import findpump, interp
from extensions.epanet.model import (
    FLOW,
    Project,
    SavedHydraulics,
    zero_flow_balance,
)
from extensions.epanet.rules import checkrules
from extensions.epanet.smatrix import createsparse, unlinked
from extensions.epanet.validate import validateproject


def openhyd(mut pr: Project, mut errors: List[String]) -> Int:
    """Check the network and make the hydraulic solver.

    Args:
        pr: The project, after `openproject`.
        errors: Receives a message for each object with an error.

    Returns:
        0, or an error code.
    """
    pr.hyd.open_hflag = False
    var errcode = validateproject(pr, errors)
    if errcode > 0:
        return errcode
    createsparse(pr)
    var nnodes = pr.net.nnodes
    var nlinks = pr.net.nlinks
    pr.hyd.p = List[Float64](length=nlinks + 1, fill=0.0)
    pr.hyd.y = List[Float64](length=nlinks + 1, fill=0.0)
    pr.hyd.xflow = List[Float64](length=max(nnodes + 1, nlinks + 1), fill=0.0)
    pr.hyd.old_status = List[StatusType](
        length=nlinks + pr.net.ntanks + 1, fill=StatusType(0)
    )
    errcode = unlinked(pr.net, errors)
    if errcode != 0:
        return errcode
    for i in range(1, nlinks + 1):
        var s = pr.net.link[i].init_status
        var kc = pr.net.link[i].kc
        initlinkflow(pr, i, s, kc)
    pr.hyd.open_hflag = True
    return 0


def inithyd(mut pr: Project, initflag: Int, saveflag: Bool):
    """Set the starting state of a hydraulic run.

    Args:
        pr: The project, after `openhyd`.
        initflag: 1 to set every starting flow again, 0 to keep the
            flows of the last run.
        saveflag: Whether to save the results for the quality solver.
    """
    openleakage(pr)
    pr.saveflag = saveflag
    pr.save_hflag = False
    pr.hyd_file = List[SavedHydraulics]()
    var nlinks = pr.net.nlinks
    for i in range(1, pr.net.ntanks + 1):  # pragma: no branch
        ref tank = pr.net.tank[i]
        tank.v = tank.v0
        pr.hyd.node_head[tank.node] = tank.h0
        pr.hyd.node_demand[tank.node] = 0.0
        pr.hyd.old_status[nlinks + i] = TEMPCLOSED
    for i in range(len(pr.hyd.demand_flow)):  # pragma: no branch
        pr.hyd.demand_flow[i] = 0.0
        pr.hyd.emitter_flow[i] = 0.0
        pr.hyd.leakage_flow[i] = 0.0
    for i in range(1, pr.net.nnodes + 1):  # pragma: no branch
        if pr.net.node[i].ke > 0.0:
            pr.hyd.emitter_flow[i] = 1.0
    for i in range(1, nlinks + 1):
        var t = pr.net.link[i].type
        var init_status = pr.net.link[i].init_status
        pr.hyd.link_status[i] = init_status
        pr.hyd.link_setting[i] = pr.net.link[i].init_setting
        if t.value > PUMP.value and t != GPV and init_status != ACTIVE:
            pr.hyd.link_setting[i] = MISSING
        resistcoeff(pr, i)
        if (t == PRV or t == PSV or t == FCV) and pr.hyd.link_setting[
            i
        ] != MISSING:
            pr.hyd.link_status[i] = ACTIVE
        if pr.hyd.link_status[i].value <= CLOSED.value:
            pr.hyd.link_flow[i] = QZERO
        elif abs(pr.hyd.link_flow[i]) <= QZERO or initflag > 0:
            var s = pr.hyd.link_status[i]
            var k = pr.hyd.link_setting[i]
            initlinkflow(pr, i, s, k)
        pr.hyd.old_status[i] = pr.hyd.link_status[i]
    for i in range(1, pr.net.npumps + 1):
        ref e = pr.net.pump[i].energy
        e.efficiency = 0.0
        e.time_on_line = 0.0
        e.kw_hrs = 0.0
        e.kw_hrs_per_flow = 0.0
        e.max_kwatts = 0.0
        e.total_cost = 0.0
        e.current_power = 0.0
        e.current_effic = 0.0
    pr.hyd.emax = 0.0
    pr.hyd.flow_balance = zero_flow_balance()
    pr.hyd.halt_flag = False
    pr.times.htime = 0
    pr.times.hydstep = 0
    pr.times.rtime = pr.times.rstart % pr.times.rstep
    if pr.times.rtime == 0:
        pr.times.rtime = pr.times.rstep


def runhyd(mut pr: Project, mut t: Int) -> Int:
    """Solve the network at the current time.

    Args:
        pr: The project.
        t: Receives the current time, in seconds.

    Returns:
        0, or error 110 if the equations cannot be solved.
    """
    t = pr.times.htime
    demands(pr)
    _ = controls(pr)
    var iter = 0
    var relerr = 0.0
    var errcode = hydsolve(pr, iter, relerr)
    if errcode == 0:
        if relerr > pr.hyd.hacc and pr.hyd.extra_iter == -1:
            pr.hyd.halt_flag = True
    return errcode


def nexthyd(mut pr: Project, mut tstep: Int) -> Int:
    """Find the next time step and move the clock to it.

    Args:
        pr: The project.
        tstep: Receives the time step, in seconds. It is 0 at the end of
            the run.

    Returns:
        0.
    """
    var tnow = pr.times.htime
    _getallpumpsenergy(pr)
    if pr.saveflag:
        _savehyd(pr)
    if pr.hyd.halt_flag:
        pr.times.htime = pr.times.dur
    tstep = 0
    var hydstep = 0
    if pr.times.htime < pr.times.dur:
        hydstep = timestep(pr)
    if pr.saveflag:
        pr.hyd_file[len(pr.hyd_file) - 1].step = hydstep
    if pr.times.dur == 0:
        _addenergy(pr, 0)
    elif pr.times.htime < pr.times.dur:
        _addenergy(pr, hydstep)
    _updateflowbalance(pr, hydstep)
    if pr.times.htime < pr.times.dur:
        pr.times.htime += hydstep
        if not pr.qual.open_qflag:
            if pr.times.htime >= pr.times.rtime:
                pr.times.rtime += pr.times.rstep
    else:
        _endflowbalance(pr, tnow)
        pr.times.htime += 1
        if pr.qual.open_qflag:
            pr.times.qtime += 1
    tstep = hydstep
    if pr.saveflag and tstep == 0:
        pr.save_hflag = True
    return 0


def _savehyd(mut pr: Project):
    """Save the results of the current time in single precision."""
    var rec = SavedHydraulics(pr.times.htime)
    for i in range(1, pr.net.nnodes + 1):  # pragma: no branch
        rec.demand.append(Float32(pr.hyd.node_demand[i]))
    for i in range(1, pr.net.nnodes + 1):  # pragma: no branch
        rec.head.append(Float32(pr.hyd.node_head[i]))
    for i in range(1, pr.net.nlinks + 1):
        if pr.hyd.link_status[i].value <= CLOSED.value:
            rec.flow.append(Float32(0.0))
        else:
            rec.flow.append(Float32(pr.hyd.link_flow[i]))
    for i in range(1, pr.net.nlinks + 1):
        rec.status.append(Float32(pr.hyd.link_status[i].value))
    for i in range(1, pr.net.nlinks + 1):
        rec.setting.append(Float32(pr.hyd.link_setting[i]))
    pr.hyd_file.append(rec^)


def _pattern_factor(pr: Project, j: Int, p: Int) -> Float64:
    """Return the factor of pattern j for the pattern period p."""
    ref f = pr.net.pattern[j].f
    return f[p % len(f)]


def demands(mut pr: Project):
    """Set the demands, the reservoir heads and the pump speeds.

    Args:
        pr: The project.
    """
    var p = (pr.times.htime + pr.times.pstart) // pr.times.pstep
    pr.hyd.dsystem = 0.0
    for i in range(1, pr.net.njuncs + 1):
        var total = 0.0
        for d in pr.net.node[i].demands:  # pragma: no branch
            var j = d.pat
            if j == 0:
                j = pr.hyd.def_pat
            var djunc = mul(
                mul(d.base, _pattern_factor(pr, j, p)), pr.hyd.dmult
            )
            if djunc > 0.0:
                pr.hyd.dsystem += djunc
            total += djunc
        pr.hyd.full_demand[i] = total
        pr.hyd.demand_flow[i] = total
    for n in range(1, pr.net.ntanks + 1):  # pragma: no branch
        if pr.net.tank[n].a == 0.0:
            var j = pr.net.tank[n].pat
            if j > 0:
                var i = pr.net.tank[n].node
                pr.hyd.node_head[i] = mul(
                    pr.net.node[i].el, _pattern_factor(pr, j, p)
                )
    for n in range(1, pr.net.npumps + 1):
        var j = pr.net.pump[n].upat
        if j > 0:
            var i = pr.net.pump[n].link
            setlinksetting(pr, i, _pattern_factor(pr, j, p))


def controls(mut pr: Project) -> Int:
    """Apply the simple controls that hold at the current time.

    Args:
        pr: The project.

    Returns:
        The number of links that the controls changed.
    """
    var setsum = 0
    var njuncs = pr.net.njuncs
    for i in range(1, pr.net.ncontrols + 1):
        var control = pr.net.control[i].copy()
        if not control.is_enabled:
            continue
        var k = control.link
        var reset = False
        var n = control.node
        if n > 0 and n > njuncs:
            var h = pr.hyd.node_head[n]
            var vplus: Float64
            var v1: Float64
            var v2: Float64
            if pr.net.tank[n - njuncs].a == 0.0:
                vplus = 0.0
                v1 = h
                v2 = control.grade
            else:
                vplus = abs(pr.hyd.node_demand[n])
                v1 = tankvolume(pr, n - njuncs, h)
                v2 = tankvolume(pr, n - njuncs, control.grade)
            if control.type == LOWLEVEL and v1 <= v2 + vplus:
                reset = True
            if control.type == HILEVEL and v1 >= v2 - vplus:
                reset = True
        if control.type == TIMER:
            if control.time == pr.times.htime:
                reset = True
        if control.type == TIMEOFDAY:
            if (pr.times.htime + pr.times.tstart) % SEC_PER_DAY == control.time:
                reset = True
        if reset:
            var t = pr.net.link[k].type
            var s1 = (
                CLOSED if pr.hyd.link_status[k].value <= CLOSED.value else OPEN
            )
            var s2 = control.status
            var k1 = pr.hyd.link_setting[k]
            var k2 = k1
            if t.value > PIPE.value:
                k2 = control.setting
            if t == PUMP and s1 == CLOSED and s2 == OPEN:
                resetpumpflow(pr, k)
            if s1 != s2 or k1 != k2:
                pr.hyd.link_status[k] = s2
                pr.hyd.link_setting[k] = k2
                if t == PCV:
                    pr.net.link[k].r = pcvlosscoeff(pr, k, k2)
                setsum += 1
    return setsum


def timestep(mut pr: Project) -> Int:
    """Find the time to the next event of the run.

    Args:
        pr: The project.

    Returns:
        The time step, in seconds.
    """
    ref tm = pr.times
    var tstep = tm.hstep
    var n = ((tm.htime + tm.pstart) // tm.pstep) + 1
    # n is the next pattern period, so t > 0.
    var t = n * tm.pstep - (tm.htime + tm.pstart)
    if t < tstep:
        tstep = t
    # While the quality is open, `runqual` moves the report time, so a
    # caller that skips it can leave t == 0.
    t = tm.rtime - tm.htime
    if t > 0 and t < tstep:
        tstep = t
    # `nexthyd` asks for a step only before the end, so t > 0.
    t = tm.dur - tm.htime
    if t < tstep:
        tstep = t
    _ = tanktimestep(pr, tstep)
    _ = controltimestep(pr, tstep)
    if pr.net.nrules > 0:
        _ruletimestep(pr, tstep)
    else:
        tanklevels(pr, tstep)
    return tstep


def tanktimestep(pr: Project, mut tstep: Int) -> Int:
    """Shorten a time step so that no tank passes a full or empty level.

    Args:
        pr: The project.
        tstep: The time step, in seconds. It is shortened in place.

    Returns:
        The node index of the tank that sets the step, or 0.
    """
    var tank_idx = 0
    for i in range(1, pr.net.ntanks + 1):  # pragma: no branch
        ref tank = pr.net.tank[i]
        if tank.a == 0.0:
            continue
        var n = tank.node
        var h = pr.hyd.node_head[n]
        var q = pr.hyd.node_demand[n]
        if abs(q) <= QZERO:
            continue
        var v: Float64
        if q > 0.0 and h < tank.hmax:
            v = tank.vmax - tank.v
        elif q < 0.0 and h > tank.hmin:
            v = tank.vmin - tank.v
        else:
            continue
        var xt = v / q
        if abs(xt) > Float64(tstep + 1):
            continue
        var t = round_c(xt)
        if t > 0 and t < tstep:
            tstep = t
            tank_idx = n
    return tank_idx


def controltimestep(pr: Project, mut tstep: Int) -> Int:
    """Shorten a time step to the next time a simple control acts.

    Args:
        pr: The project.
        tstep: The time step, in seconds. It is shortened in place.

    Returns:
        The index of the control that sets the step, or 0.
    """
    var control_index = 0
    var njuncs = pr.net.njuncs
    for i in range(1, pr.net.ncontrols + 1):
        ref control = pr.net.control[i]
        if not control.is_enabled:
            continue
        var t = 0
        var n = control.node
        if n > 0:
            var j = n - njuncs
            if j <= 0:
                continue
            var h = pr.hyd.node_head[n]
            var q = pr.hyd.node_demand[n]
            if abs(q) <= QZERO:
                continue
            if (h < control.grade and control.type == HILEVEL and q > 0.0) or (
                h > control.grade and control.type == LOWLEVEL and q < 0.0
            ):
                var v = tankvolume(pr, j, control.grade) - pr.net.tank[j].v
                t = round_c(v / q)
        if control.type == TIMER:
            if control.time > pr.times.htime:
                t = control.time - pr.times.htime
        if control.type == TIMEOFDAY:
            var t1 = (pr.times.htime + pr.times.tstart) % SEC_PER_DAY
            var t2 = control.time
            if t2 >= t1:
                t = t2 - t1
            else:
                t = SEC_PER_DAY - t1 + t2
        if t > 0 and t < tstep:
            var k = control.link
            if (
                pr.net.link[k].type.value > PIPE.value
                and pr.hyd.link_setting[k] != control.setting
            ) or (pr.hyd.link_status[k] != control.status):
                tstep = t
                control_index = i
    return control_index


def _ruletimestep(mut pr: Project, mut tstep: Int):
    """Step through the rule time steps until a rule acts."""
    var tnow = pr.times.htime
    var tmax = tnow + tstep
    # `adjustdata` makes the rule step at least 1 s, and `timestep`
    # gives a step of at least 1 s, so dt1 > 0.
    var dt = min(pr.times.rulestep, tstep)
    var dt1 = min(pr.times.rulestep - (tnow % pr.times.rulestep), tstep)
    while True:
        pr.times.htime += dt1
        tanklevels(pr, dt1)
        if checkrules(pr, dt1) > 0:
            break
        dt = min(dt, tmax - pr.times.htime)
        dt1 = dt
        if dt <= 0:
            break
    tstep = pr.times.htime - tnow
    pr.times.htime = tnow


def _addenergy(mut pr: Project, hstep: Int):
    """Add the energy of each pump over a time step."""
    # `nexthyd` calls this for a run of no duration or before the end.
    var dt: Float64
    if pr.times.dur == 0:
        dt = 1.0
    else:
        dt = Float64(hstep) / 3600.0
    var n = (pr.times.htime + pr.times.pstart) // pr.times.pstep
    var c0 = pr.hyd.ecost
    var f0 = 1.0
    if pr.hyd.epat > 0:
        f0 = _pattern_factor(pr, pr.hyd.epat, n)
    var psum = 0.0
    for j in range(1, pr.net.npumps + 1):
        var k = pr.net.pump[j].link
        if pr.net.pump[j].energy.current_effic == 0.0:
            continue
        var q = max(QZERO, abs(pr.hyd.link_flow[k]))
        var c = pr.net.pump[j].ecost if pr.net.pump[j].ecost > 0.0 else c0
        var i = pr.net.pump[j].epat
        if i > 0:
            c *= _pattern_factor(pr, i, n)
        else:
            c *= f0
        ref e = pr.net.pump[j].energy
        var p = e.current_power
        psum += p
        e.time_on_line += dt
        e.efficiency += mul(e.current_effic, dt)
        e.kw_hrs_per_flow += mul(p / q, dt)
        e.kw_hrs += mul(p, dt)
        e.max_kwatts = max(e.max_kwatts, p)
        e.total_cost += mul(mul(c, p), dt)
    pr.hyd.emax = max(pr.hyd.emax, psum)


def getenergy(pr: Project, k: Int, mut kw: Float64, mut eff: Float64):
    """Find the power use and the efficiency of a link.

    Args:
        pr: The project.
        k: The link index.
        kw: Receives the power, in kilowatts.
        eff: Receives the efficiency, as a fraction.
    """
    if pr.hyd.link_status[k].value <= CLOSED.value:
        kw = 0.0
        eff = 0.0
        return
    ref link = pr.net.link[k]
    var q = abs(pr.hyd.link_flow[k])
    var dh = abs(pr.hyd.node_head[link.n1] - pr.hyd.node_head[link.n2])
    var e: Float64
    if link.type == PUMP:
        var j = findpump(pr.net, k)
        e = pr.hyd.epump
        var speed = pr.hyd.link_setting[k]
        var i = pr.net.pump[j].ecurve
        if i > 0:
            var q4eff = mul(q / speed, pr.ucf[FLOW])
            e = interp(pr.net.curve[i].x, pr.net.curve[i].y, q4eff)
            e = 100.0 - mul(100.0 - e, cpow(1.0 / speed, 0.1))
        e = min(e, 100.0)
        e = max(e, 1.0)
        e /= 100.0
    else:
        e = 1.0
    kw = mul(mul(mul(dh, q), pr.hyd.sp_grav) / 8.814 / e, KW_PER_HP)
    eff = e


def _getallpumpsenergy(mut pr: Project):
    """Find the current power and efficiency of each pump."""
    for j in range(1, pr.net.npumps + 1):
        var kw = 0.0
        var eff = 0.0
        getenergy(pr, pr.net.pump[j].link, kw, eff)
        pr.net.pump[j].energy.current_power = kw
        pr.net.pump[j].energy.current_effic = eff


def _updateflowbalance(mut pr: Project, hstep: Int):
    """Add the flows of a time step to the flow balance."""
    var dt: Float64
    if pr.times.dur == 0:
        dt = 1.0
    elif pr.times.htime < pr.times.dur:
        dt = Float64(hstep)
    else:
        return
    var fb = zero_flow_balance()
    pr.hyd.leakage_loss = 0.0
    for i in range(1, pr.net.njuncs + 1):
        var v = pr.hyd.demand_flow[i]
        if v < 0.0:
            fb.total_inflow += -v
        else:
            fb.consumer_demand += v
            fb.total_outflow += v
        v = pr.hyd.emitter_flow[i]
        fb.emitter_demand += v
        fb.total_outflow += v
        v = pr.hyd.leakage_flow[i]
        fb.leakage_demand += v
        fb.total_outflow += v
        if pr.hyd.demand_model == PDA and pr.hyd.full_demand[i] > 0.0:
            var deficit = pr.hyd.full_demand[i] - pr.hyd.demand_flow[i]
            if deficit > 0.0:
                fb.deficit_demand += deficit
    for j in range(1, pr.net.ntanks + 1):  # pragma: no branch
        var i = pr.net.tank[j].node
        var v = pr.hyd.node_demand[i]
        if pr.net.tank[j].a == 0.0:
            if v >= 0.0:
                fb.total_outflow += v
            else:
                fb.total_inflow += -v
        else:
            fb.storage_demand += v
    var v = fb.total_inflow
    if fb.storage_demand < 0.0:
        v += -fb.storage_demand
    if v > 0.0:
        pr.hyd.leakage_loss = mul(fb.leakage_demand / v, 100.0)
    ref t = pr.hyd.flow_balance
    t.total_inflow += mul(fb.total_inflow, dt)
    t.total_outflow += mul(fb.total_outflow, dt)
    t.consumer_demand += mul(fb.consumer_demand, dt)
    t.emitter_demand += mul(fb.emitter_demand, dt)
    t.leakage_demand += mul(fb.leakage_demand, dt)
    t.deficit_demand += mul(fb.deficit_demand, dt)
    t.storage_demand += mul(fb.storage_demand, dt)


def _endflowbalance(mut pr: Project, tfinal: Int):
    """Turn the flow balance totals into average flows and a ratio."""
    var seconds = Float64(tfinal) if tfinal > 0 else 1.0
    ref t = pr.hyd.flow_balance
    t.total_inflow /= seconds
    t.total_outflow /= seconds
    t.consumer_demand /= seconds
    t.emitter_demand /= seconds
    t.leakage_demand /= seconds
    t.deficit_demand /= seconds
    t.storage_demand /= seconds
    var qin = t.total_inflow
    var qout = t.total_outflow
    var qstor = t.storage_demand
    if qstor > 0.0:
        qout += qstor
    else:
        qin -= qstor
    var r: Float64
    if qin == qout:
        r = 1.0
    elif qin > 0.0:
        r = qout / qin
    else:
        r = 0.0
    t.ratio = r
