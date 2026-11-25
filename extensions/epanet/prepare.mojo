# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from input1.c and project.c of OWA EPANET 2.3.6. Copyright (c)
# 2023 the EPANET contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""Open a project: read an input file and convert its data to internal units.

`openproject` reads the text of an input file. It sets the defaults,
reads the data, and converts each value to feet, cubic feet per second
and seconds, as `EN_open` does.
"""

from std.math import sqrt

from extensions.epanet.cmath import clog, cpow, mul
from extensions.epanet.input import allocdata, netsize, readdata
from extensions.epanet.kinds import (
    AFD,
    AFD_PER_CFS,
    AGE,
    BAR,
    BAR_PER_PSI,
    CHEM,
    CM,
    CMD,
    CMD_PER_CFS,
    CMH,
    CMH_PER_CFS,
    CMS,
    CMS_PER_CFS,
    DDA,
    DEFAULTUNIT,
    DIFFUS,
    DW,
    FCV,
    FEET,
    GPM,
    GPM_PER_CFS,
    HW,
    IMGD,
    IMGD_PER_CFS,
    KPA,
    KPA_PER_PSI,
    KW_PER_HP,
    L_PER_FT3,
    LPM,
    LPM_PER_CFS,
    LPS,
    LPS_PER_CFS,
    METERS,
    MGD,
    MGD_PER_CFS,
    MINPDIFF,
    MISSING,
    MLD,
    MLD_PER_CFS,
    M_PER_FT,
    NONE,
    PBV,
    PI,
    PIPE,
    PRV,
    PSI,
    PSI_PER_FT,
    PSV,
    PUMP,
    SEC_PER_DAY,
    SI,
    US,
    VISCOS,
)
from extensions.epanet.lookup import findpattern, interp
from extensions.epanet.model import (
    DEMAND,
    DIAM,
    ELEV,
    FLOW,
    FRICTION,
    HEAD,
    HEADLOSS,
    LENGTH,
    LINKQUAL,
    POWER,
    PRESSURE,
    Project,
    QUALITY,
    REACTRATE,
    TIME,
    VELOCITY,
    VOLUME,
)
from extensions.epanet.validate import reindextanks, validtankcurve


def setdefaults(mut pr: Project):
    """Set the default options of a project.

    Args:
        pr: The project.
    """
    pr.title = List[String]()
    pr.qual.chem_name = "Chemical"
    pr.qual.chem_units = "mg/L"
    pr.parser.def_pat_id = "1"
    pr.warnflag = 0
    pr.parser.units_flag = US
    pr.parser.flow_flag = GPM
    pr.parser.press_flag = DEFAULTUNIT
    pr.hyd.formflag = HW
    pr.hyd.htol = 0.0005
    pr.hyd.qtol = 0.0001
    pr.hyd.hacc = 0.001
    pr.hyd.flow_change_limit = 0.0
    pr.hyd.head_error_limit = 0.0
    pr.hyd.demand_model = DDA
    pr.hyd.pmin = 0.0
    pr.hyd.preq = MINPDIFF
    pr.hyd.pexp = 0.5
    pr.hyd.max_iter = 200
    pr.hyd.extra_iter = -1
    pr.hyd.viscos = MISSING
    pr.hyd.sp_grav = 1.0
    pr.hyd.epat = 0
    pr.hyd.ecost = 0.0
    pr.hyd.dcost = 0.0
    pr.hyd.epump = 75.0
    pr.hyd.emax = 0.0
    pr.hyd.qexp = 2.0
    pr.hyd.emit_back_flag = True
    pr.hyd.def_pat = 0
    pr.hyd.dmult = 1.0
    pr.hyd.rqtol = 1.0e-7
    pr.hyd.check_freq = 2
    pr.hyd.max_check = 10
    pr.hyd.damp_limit = 0.0
    pr.qual.qualflag = NONE
    pr.qual.ctol = MISSING
    pr.qual.trace_node = 0
    pr.qual.bulk_order = 1.0
    pr.qual.wall_order = 1.0
    pr.qual.tank_order = 1.0
    pr.qual.kbulk = 0.0
    pr.qual.kwall = 0.0
    pr.qual.climit = 0.0
    pr.qual.diffus = MISSING
    pr.qual.rfactor = 0.0
    pr.qual.mass_balance.ratio = 0.0
    pr.times.dur = 0
    pr.times.tstart = 0
    pr.times.pstart = 0
    pr.times.hstep = 3600
    pr.times.qstep = 0
    pr.times.pstep = 3600
    pr.times.rstep = 3600
    pr.times.rulestep = 0
    pr.times.rstart = 0


def adjustdata(mut pr: Project):
    """Fill the options that the input file left unset.

    Args:
        pr: The project, after `readdata`.
    """
    ref t = pr.times
    if t.pstep <= 0:
        t.pstep = 3600
    if t.rstep == 0:
        t.rstep = t.pstep
    if t.hstep <= 0:
        t.hstep = 3600
    if t.hstep > t.pstep:
        t.hstep = t.pstep
    if t.hstep > t.rstep:
        t.hstep = t.rstep
    if t.rstart > t.dur:
        t.rstart = 0
    if t.qstep == 0:
        t.qstep = max(1, t.hstep // 10)
    if t.rulestep == 0:
        t.rulestep = max(1, t.hstep // 10)
    t.rulestep = min(t.rulestep, t.hstep)
    t.qstep = min(t.qstep, t.hstep)
    if pr.qual.ctol == MISSING:
        pr.qual.ctol = 0.01
    var ff = pr.parser.flow_flag.value
    if ff >= LPS.value:
        pr.parser.units_flag = SI
    else:
        pr.parser.units_flag = US
    if pr.parser.press_flag == DEFAULTUNIT:
        if pr.parser.units_flag == SI:
            pr.parser.press_flag = METERS
        else:
            pr.parser.press_flag = PSI
    var ucf = 1.0
    if pr.parser.units_flag == SI:
        ucf = mul(M_PER_FT, M_PER_FT)
    if pr.hyd.viscos == MISSING:
        pr.hyd.viscos = VISCOS
    elif pr.hyd.viscos > 1.0e-3:
        pr.hyd.viscos = mul(pr.hyd.viscos, VISCOS)
    else:
        pr.hyd.viscos = pr.hyd.viscos / ucf
    if pr.qual.diffus == MISSING:
        pr.qual.diffus = DIFFUS
    elif pr.qual.diffus > 1.0e-4:
        pr.qual.diffus = mul(pr.qual.diffus, DIFFUS)
    else:
        pr.qual.diffus = pr.qual.diffus / ucf
    if pr.hyd.formflag == HW:
        pr.hyd.hexp = 1.852
    else:
        pr.hyd.hexp = 2.0
    for i in range(1, pr.net.nlinks + 1):
        ref link = pr.net.link[i]
        if link.type.value > PIPE.value:
            continue
        if link.kb == MISSING:
            link.kb = pr.qual.kbulk
        if link.kw == MISSING:
            if pr.qual.rfactor == 0.0:
                link.kw = pr.qual.kwall
            else:
                # `pipedata` refuses a roughness or a diameter <= 0.
                if pr.hyd.formflag == HW:
                    link.kw = pr.qual.rfactor / link.kc
                if pr.hyd.formflag == DW:
                    link.kw = pr.qual.rfactor / abs(clog(link.kc / link.diam))
                if pr.hyd.formflag == CM:
                    link.kw = mul(pr.qual.rfactor, link.kc)
    for i in range(1, pr.net.ntanks + 1):
        if pr.net.tank[i].kb == MISSING:
            pr.net.tank[i].kb = pr.qual.kbulk
    var i = findpattern(pr.net, pr.parser.def_pat_id)
    if i > 0:
        pr.hyd.def_pat = i


def inittanks(mut pr: Project):
    """Find the volumes of the tanks that have a volume curve.

    Args:
        pr: The project.
    """
    for j in range(1, pr.net.ntanks + 1):
        if pr.net.tank[j].a == 0.0:
            continue
        var i = pr.net.tank[j].vcurve
        if i > 0:
            ref curve = pr.net.curve[i]
            if not validtankcurve(curve):
                continue
            ref tank = pr.net.tank[j]
            var n = curve.npts() - 1
            tank.vmin = interp(curve.x, curve.y, tank.hmin)
            tank.vmax = interp(curve.x, curve.y, tank.hmax)
            tank.v0 = interp(curve.x, curve.y, tank.h0)
            var a = (curve.y[n] - curve.y[0]) / (curve.x[n] - curve.x[0])
            tank.a = sqrt(mul(4.0, a) / PI)


def initunits(mut pr: Project):
    """Find the unit conversion factors.

    Args:
        pr: The project.
    """
    var dcf: Float64
    var qcf: Float64
    var hcf: Float64
    var wcf: Float64
    var ff = pr.parser.flow_flag
    if pr.parser.units_flag == SI:
        dcf = mul(1000.0, M_PER_FT)
        qcf = LPS_PER_CFS
        if ff == LPM:
            qcf = LPM_PER_CFS
        if ff == MLD:
            qcf = MLD_PER_CFS
        if ff == CMH:
            qcf = CMH_PER_CFS
        if ff == CMD:
            qcf = CMD_PER_CFS
        if ff == CMS:
            qcf = CMS_PER_CFS
        hcf = M_PER_FT
        wcf = KW_PER_HP
    else:
        dcf = 12.0
        qcf = 1.0
        if ff == GPM:
            qcf = GPM_PER_CFS
        if ff == MGD:
            qcf = MGD_PER_CFS
        if ff == IMGD:
            qcf = IMGD_PER_CFS
        if ff == AFD:
            qcf = AFD_PER_CFS
        hcf = 1.0
        wcf = 1.0
    var pf = pr.parser.press_flag
    var pcf = mul(PSI_PER_FT, pr.hyd.sp_grav)
    if pf == METERS:
        pcf = M_PER_FT
    if pf == KPA:
        pcf = mul(mul(KPA_PER_PSI, PSI_PER_FT), pr.hyd.sp_grav)
    if pf == BAR:
        pcf = mul(mul(BAR_PER_PSI, PSI_PER_FT), pr.hyd.sp_grav)
    if pf == FEET:
        pcf = 1.0
    var ccf = 1.0
    if pr.qual.qualflag == CHEM:
        ccf = 1.0 / L_PER_FT3
    pr.ucf[DEMAND] = qcf
    pr.ucf[ELEV] = hcf
    pr.ucf[HEAD] = hcf
    pr.ucf[PRESSURE] = pcf
    pr.ucf[QUALITY] = ccf
    pr.ucf[LENGTH] = hcf
    pr.ucf[DIAM] = dcf
    pr.ucf[FLOW] = qcf
    pr.ucf[VELOCITY] = hcf
    pr.ucf[HEADLOSS] = hcf
    pr.ucf[LINKQUAL] = ccf
    pr.ucf[REACTRATE] = ccf
    pr.ucf[FRICTION] = 1.0
    pr.ucf[POWER] = wcf
    pr.ucf[VOLUME] = mul(mul(hcf, hcf), hcf)
    if pr.times.hstep < 1800:
        pr.ucf[TIME] = 1.0 / 60.0
    else:
        pr.ucf[TIME] = 1.0 / 3600.0


def convertunits(mut pr: Project):
    """Convert the input data to internal units.

    Args:
        pr: The project, after `initunits`.
    """
    var ucf_elev = pr.ucf[ELEV]
    for i in range(1, pr.net.nnodes + 1):
        pr.net.node[i].el /= ucf_elev
        pr.net.node[i].c0 /= pr.ucf[QUALITY]
    for i in range(1, pr.net.njuncs + 1):
        for ref d in pr.net.node[i].demands:  # pragma: no branch
            d.base /= pr.ucf[DEMAND]
        pr.hyd.node_demand[i] = 0.0
    pr.hyd.pmin /= pr.ucf[PRESSURE]
    pr.hyd.preq /= pr.ucf[PRESSURE]
    var ecf = M_PER_FT
    if pr.parser.units_flag == US:
        ecf = mul(PSI_PER_FT, pr.hyd.sp_grav)
    for i in range(1, pr.net.njuncs + 1):
        ref node = pr.net.node[i]
        if node.ke > 0.0:
            node.ke = cpow(pr.ucf[FLOW] / node.ke, pr.hyd.qexp) / ecf
    for j in range(1, pr.net.ntanks + 1):
        var i = pr.net.tank[j].node
        var el = pr.net.node[i].el
        var c0 = pr.net.node[i].c0
        ref tank = pr.net.tank[j]
        tank.h0 = el + tank.h0 / ucf_elev
        tank.hmin = el + tank.hmin / ucf_elev
        tank.hmax = el + tank.hmax / ucf_elev
        var d = tank.a / ucf_elev
        tank.a = mul(PI, mul(d, d)) / 4.0
        tank.v0 /= pr.ucf[VOLUME]
        tank.vmin /= pr.ucf[VOLUME]
        tank.vmax /= pr.ucf[VOLUME]
        tank.kb /= Float64(SEC_PER_DAY)
        tank.v = tank.v0
        tank.c = c0
        pr.hyd.node_head[i] = tank.h0
    pr.hyd.flow_change_limit /= pr.ucf[FLOW]
    pr.hyd.head_error_limit /= pr.ucf[HEAD]
    pr.qual.climit /= pr.ucf[QUALITY]
    pr.qual.ctol /= pr.ucf[QUALITY]
    pr.qual.kbulk /= Float64(SEC_PER_DAY)
    pr.qual.kwall /= Float64(SEC_PER_DAY)
    for k in range(1, pr.net.nlinks + 1):
        ref link = pr.net.link[k]
        if link.type.value <= PIPE.value:
            if pr.hyd.formflag == DW:
                link.kc /= mul(1000.0, ucf_elev)
            link.diam /= pr.ucf[DIAM]
            link.len /= pr.ucf[LENGTH]
            link.km = (
                mul(0.02517, link.km)
                / mul(link.diam, link.diam)
                / mul(link.diam, link.diam)
            )
            link.kb /= Float64(SEC_PER_DAY)
            link.kw /= Float64(SEC_PER_DAY)
            link.leak_area *= pr.ucf[LENGTH]
            link.leak_expan *= pr.ucf[LENGTH]
        elif link.type == PUMP:
            link.km /= pr.ucf[POWER]
        else:
            link.diam /= pr.ucf[DIAM]
            link.km = (
                mul(0.02517, link.km)
                / mul(link.diam, link.diam)
                / mul(link.diam, link.diam)
            )
            if link.type == FCV:
                link.kc /= pr.ucf[FLOW]
            elif link.type == PRV or link.type == PSV or link.type == PBV:
                link.kc /= pr.ucf[PRESSURE]
        link.init_setting = link.kc
        pr.hyd.link_status[k] = link.init_status
        pr.hyd.link_setting[k] = link.init_setting
    for i in range(1, pr.net.ncontrols + 1):
        var k = pr.net.control[i].link
        var j = pr.net.control[i].node
        ref control = pr.net.control[i]
        if j > 0:
            var el = pr.net.node[j].el
            if j > pr.net.njuncs:
                control.grade = el + control.grade / ucf_elev
            else:
                control.grade = el + control.grade / pr.ucf[PRESSURE]
        if control.setting != MISSING:
            var type = pr.net.link[k].type
            if type == PRV or type == PSV or type == PBV:
                control.setting /= pr.ucf[PRESSURE]
            elif type == FCV:
                control.setting /= pr.ucf[FLOW]


def openproject(mut pr: Project, text: String) raises:
    """Read the text of an input file into a project, as `EN_open` does.

    Args:
        pr: A new project.
        text: The text of an EPANET input file.

    Raises:
        Error: The text has an error. The message lists each line or
            object with an error.
    """
    var lines = List[String]()
    for line in text.split("\n"):  # pragma: no branch
        lines.append(String(line))
    var errcode = netsize(pr, lines)
    if errcode != 0:
        raise Error("EPANET error ", errcode, ": invalid ID name")
    allocdata(pr)
    setdefaults(pr)
    var errors = List[String]()
    errcode = readdata(pr, lines, errors)
    reindextanks(pr)
    adjustdata(pr)
    inittanks(pr)
    initunits(pr)
    convertunits(pr)
    if errcode != 0:
        var message = String("EPANET error 200: one or more errors in input")
        for e in errors:  # pragma: no branch
            message += "\n" + e
        raise Error(message)
    pr.openflag = True
