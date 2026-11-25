# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from input2.c and input3.c of OWA EPANET 2.3.6. Copyright (c) 2023
# the EPANET contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The readers of the option sections of an EPANET input file.

These sections are [STATUS], [REACTIONS], [MIXING], [ENERGY], [REPORT],
[TIMES], [OPTIONS] and [TAGS]. The [REPORT] and [TAGS] readers check a
line and report its errors, but keep no data, because no computation
uses them.
"""

from extensions.epanet.cmath import mul
from extensions.epanet.kinds import (
    ACTIVE,
    AFD,
    AGE,
    BAR,
    CFS,
    CHEM,
    CLOSED,
    CM,
    CMD,
    CMH,
    CMS,
    CVPIPE,
    DW,
    DemandModel,
    EFFIC_CURVE,
    FEET,
    GPM,
    GPV,
    HW,
    IMGD,
    KPA,
    LPM,
    LPS,
    METERS,
    MGD,
    MINPDIFF,
    MIX2,
    MLD,
    MixType,
    NONE,
    OPEN,
    PIPE,
    PRV,
    PSI,
    PUMP,
    SEC_PER_DAY,
    SI,
    StatusType,
    TRACE,
    US,
)
from extensions.epanet.lookup import (
    findcurve,
    findlink,
    findnode,
    findpattern,
    findpump,
)
from extensions.epanet.model import Project
from extensions.epanet.text import (
    BACKFLOW_WORDS,
    DEMAND_MODEL_WORDS,
    MIX_WORDS,
    atol,
    findmatch,
    get_float,
    hour,
    matches,
    strcmp,
)

# The report field names of `Fldname`, for the [REPORT] checks.
comptime FIELD_WORDS: List[String] = [
    "Elevation",
    "Demand",
    "Head",
    "Pressure",
    "Quality",
    "Length",
    "Diameter",
    "Flow",
    "Velocity",
    "Headloss",
    "Quality",
    "State",
    "Setting",
    "Reaction",
    "F-Factor",
]
comptime _MAX_INT32 = 2147483647.0
# LONG_MAX / 7200 for a 64-bit long, the limit of a time in hours.
comptime _MAX_HOURS = 9223372036854775807.0 / 7200.0


def getunitsoption(mut pr: Project, units: String) -> Bool:
    """Set the flow units from a keyword.

    Args:
        pr: The project.
        units: The keyword, such as GPM or LPS.

    Returns:
        Whether the keyword names flow units.
    """
    if matches(units, "CFS"):
        pr.parser.flow_flag = CFS
    elif matches(units, "GPM"):
        pr.parser.flow_flag = GPM
    elif matches(units, "AFD"):
        pr.parser.flow_flag = AFD
    elif matches(units, "MGD"):
        pr.parser.flow_flag = MGD
    elif matches(units, "IMGD"):
        pr.parser.flow_flag = IMGD
    elif matches(units, "LPS"):
        pr.parser.flow_flag = LPS
    elif matches(units, "LPM"):
        pr.parser.flow_flag = LPM
    elif matches(units, "CMH"):
        pr.parser.flow_flag = CMH
    elif matches(units, "CMD"):
        pr.parser.flow_flag = CMD
    elif matches(units, "MLD"):
        pr.parser.flow_flag = MLD
    elif matches(units, "CMS"):
        pr.parser.flow_flag = CMS
    elif matches(units, "SI"):
        pr.parser.flow_flag = LPS
    else:
        return False
    if pr.parser.flow_flag.value >= LPS.value:
        pr.parser.units_flag = SI
    else:
        pr.parser.units_flag = US
    return True


def getheadlossoption(mut pr: Project, formula: String) -> Bool:
    """Set the head loss formula from a keyword.

    Args:
        pr: The project.
        formula: The keyword: H-W, D-W or C-M.

    Returns:
        Whether the keyword names a formula.
    """
    if matches(formula, "H-W"):
        pr.hyd.formflag = HW
    elif matches(formula, "D-W"):
        pr.hyd.formflag = DW
    elif matches(formula, "C-M"):
        pr.hyd.formflag = CM
    else:
        return False
    return True


def _in_range(pr: Project, id: String) -> Bool:
    """Return True if a name is in the range of tokens 1 and 2.

    A range of two positive numbers compares the numbers of the names.
    Any other range compares the names as text.
    """
    var i1 = atol(pr.parser.tok[1])
    var i2 = 0
    if i1 > 0:
        i2 = atol(pr.parser.tok[2])
    if i1 > 0 and i2 > 0:
        var i = atol(id)
        return i >= i1 and i <= i2
    return (
        strcmp(pr.parser.tok[1], id) <= 0 and strcmp(pr.parser.tok[2], id) >= 0
    )


def _set_tank_kb(mut pr: Project, j: Int, y: Float64):
    """Set the bulk rate of the tank of node `j`, as `Tank[j - Njuncs]`."""
    var t = j - pr.net.njuncs
    if t < len(pr.net.tank):
        pr.net.tank[t].kb = y


def reactdata(mut pr: Project) -> Int:
    """Read a line of the [REACTIONS] section.

    The forms are ORDER, GLOBAL, BULK, WALL, TANK, LIMITING and
    ROUGHNESS lines, each with a value last.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var y = 0.0
    var n = len(pr.parser.tok)
    if n < 3:
        return 0
    var t0 = pr.parser.tok[0]
    var t1 = pr.parser.tok[1]
    var last_ok = get_float(pr.parser.tok[n - 1], y)
    if matches(t0, "ORDER"):
        if not last_ok:
            return 202
        if matches(t1, "BULK"):
            pr.qual.bulk_order = y
        elif matches(t1, "Tank"):
            pr.qual.tank_order = y
        elif matches(t1, "WALL"):
            if y == 0.0:
                pr.qual.wall_order = 0.0
            elif y == 1.0:
                pr.qual.wall_order = 1.0
            else:
                return 213
        else:
            return 213
        return 0
    if matches(t0, "ROUG"):
        if not last_ok:
            return 202
        pr.qual.rfactor = y
        return 0
    if matches(t0, "LIMIT"):
        if not last_ok:
            return 202
        pr.qual.climit = y
        return 0
    if matches(t0, "GLOB"):
        if not last_ok:
            return 202
        if matches(t1, "BULK"):
            pr.qual.kbulk = y
        elif matches(t1, "WALL"):
            pr.qual.kwall = y
        else:
            return 213
        return 0
    var item: Int
    if matches(t0, "BULK"):
        item = 1
    elif matches(t0, "WALL"):
        item = 2
    elif matches(t0, "Tank"):
        item = 3
    else:
        return 213
    if not last_ok:
        return 202
    if item == 3:
        if n == 3:
            var j = findnode(pr.net, t1)
            if j <= pr.net.njuncs:
                return 0
            _set_tank_kb(pr, j, y)
        else:
            for j in range(pr.net.njuncs + 1, pr.net.nnodes + 1):
                if _in_range(pr, pr.net.node[j].id):
                    _set_tank_kb(pr, j, y)
        return 0
    if pr.net.nlinks == 0:
        return 0
    if n == 3:
        var j = findlink(pr.net, t1)
        if j == 0:
            return 0
        if item == 1:
            pr.net.link[j].kb = y
        else:
            pr.net.link[j].kw = y
        return 0
    for j in range(1, pr.net.nlinks + 1):  # pragma: no branch
        if _in_range(pr, pr.net.link[j].id):
            if item == 1:
                pr.net.link[j].kb = y
            else:
                pr.net.link[j].kw = y
    return 0


def mixingdata(mut pr: Project) -> Int:
    """Read a line of the [MIXING] section: tank, model, volume fraction.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    if pr.net.nnodes == 0:
        return 203
    var n = len(pr.parser.tok)
    if n < 2:
        return 0
    var j = findnode(pr.net, pr.parser.tok[0])
    if j == 0:
        return 203
    if j <= pr.net.njuncs:
        return 0
    var m = findmatch(pr.parser.tok[1], materialize[MIX_WORDS]())
    if m < 0:
        return 213
    var v = 1.0
    if m == MIX2.value and n == 3 and not get_float(pr.parser.tok[2], v):
        return 202
    if v == 0.0:
        v = 1.0
    var i = j - pr.net.njuncs
    if i >= len(pr.net.tank) or pr.net.tank[i].a == 0.0:
        return 0
    pr.net.tank[i].mix_model = MixType(m)
    pr.net.tank[i].v1frac = v
    return 0


def changestatus(mut pr: Project, j: Int, status: StatusType, y: Float64):
    """Change the initial status or setting of a link.

    Args:
        pr: The project.
        j: The link index.
        status: OPEN, CLOSED, or ACTIVE when `y` is a setting.
        y: The setting: a pump speed or a valve setting.
    """
    ref link = pr.net.link[j]
    var s = status
    if link.type == PIPE or link.type == GPV:
        # `statusdata` refuses a setting for a pipe or a GPV.
        link.init_status = s
    elif link.type == PUMP:
        if s == ACTIVE:
            link.kc = y
            s = OPEN
            if y == 0.0:
                s = CLOSED
        elif s == OPEN:
            link.kc = 1.0
        else:
            link.kc = 0.0
        link.init_status = s
        link.init_setting = link.kc
    else:
        # A valve: `statusdata` refuses a check valve pipe.
        if s == ACTIVE:
            link.kc = y
        link.init_status = s
        link.init_setting = link.kc


def statusdata(mut pr: Project) -> Int:
    """Read a line of the [STATUS] section: a link or a range, and a value.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var y = 0.0
    var status = ACTIVE
    if pr.net.nlinks == 0:
        return 204
    var n = len(pr.parser.tok) - 1
    if n < 1:
        return 201
    ref last = pr.parser.tok[n]
    if matches(last, "OPEN"):
        status = OPEN
    elif matches(last, "CLOSED"):
        status = CLOSED
    else:
        if not get_float(last, y):
            return 202
        if y < 0.0:
            return 211
    if n == 1:
        var j = findlink(pr.net, pr.parser.tok[0])
        if j == 0:
            return 204
        if pr.net.link[j].type == CVPIPE:
            return 207
        if pr.net.link[j].type == GPV and status == ACTIVE:
            return 207
        changestatus(pr, j, status, y)
        return 0
    var i1 = atol(pr.parser.tok[0])
    var i2 = 0
    if i1 > 0:
        i2 = atol(pr.parser.tok[1])
    # `statusdata` returned 204 above when there are no links.
    for j in range(1, pr.net.nlinks + 1):  # pragma: no branch
        var hit: Bool
        if i1 > 0 and i2 > 0:
            var i = atol(pr.net.link[j].id)
            hit = i >= i1 and i <= i2
        else:
            hit = (
                strcmp(pr.parser.tok[0], pr.net.link[j].id) <= 0
                and strcmp(pr.parser.tok[1], pr.net.link[j].id) >= 0
            )
        if hit:
            changestatus(pr, j, status, y)
    return 0


def energydata(mut pr: Project) -> Int:
    """Read a line of the [ENERGY] section.

    The forms are "GLOBAL PRICE|PATTERN|EFFIC value", "PUMP id
    PRICE|PATTERN|EFFIC value" and "DEMAND CHARGE value".

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var y = 0.0
    var n = len(pr.parser.tok)
    if n < 3:
        return 201
    ref tok = pr.parser.tok
    if matches(tok[0], "DEMAN"):
        if not get_float(tok[2], y):
            return 202
        if y < 0.0:
            return 213
        pr.hyd.dcost = y
        return 0
    var j: Int
    if matches(tok[0], "GLOB"):
        j = 0
    elif matches(tok[0], "Pump"):
        if n < 4:
            return 201
        var k = findlink(pr.net, tok[1])
        if k == 0:
            return 216
        if pr.net.link[k].type != PUMP:
            return 216
        j = findpump(pr.net, k)
    else:
        return 213
    if matches(tok[n - 2], "PRICE"):
        if not get_float(tok[n - 1], y):
            return 202
        if y < 0.0:
            return 217
        if j == 0:
            pr.hyd.ecost = y
        else:
            pr.net.pump[j].ecost = y
        return 0
    if matches(tok[n - 2], "PATT"):
        var p = findpattern(pr.net, tok[n - 1])
        if p < 0:
            return 205
        if j == 0:
            pr.hyd.epat = p
        else:
            pr.net.pump[j].epat = p
        return 0
    if matches(tok[n - 2], "EFFI"):
        if j == 0:
            if not get_float(tok[n - 1], y):
                return 202
            if y <= 0.0:
                return 217
            pr.hyd.epump = y
        else:
            var c = findcurve(pr.net, tok[n - 1])
            if c == 0:
                return 206
            pr.net.pump[j].ecurve = c
            pr.net.curve[c].type = EFFIC_CURVE
        return 0
    return 201


def _strcomp(a: String, upper: String) -> Bool:
    """Compare a text with an upper-case word without case, as `strcomp`."""
    var x = a.as_bytes()
    var w = upper.as_bytes()
    if len(x) != len(w):
        return False
    for i in range(len(x)):  # pragma: no branch
        var c1 = x[i]
        if c1 >= 97 and c1 <= 122:
            c1 -= 32
        if c1 != w[i]:
            return False
    return True


def reportdata(mut pr: Project) -> Int:
    """Check a line of the [REPORT] section.

    The report writer is not part of this port, so the reader keeps no
    report option. It still gives the errors that EPANET gives.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var y = 0.0
    var n = len(pr.parser.tok) - 1
    if n < 1:
        return 201
    ref tok = pr.parser.tok
    if matches(tok[0], "PAGE"):
        if not get_float(tok[n], y):
            return 202
        if y < 0.0 or y > 255.0:
            return 213
        return 0
    if (
        matches(tok[0], "STATUS")
        or matches(tok[0], "SUMM")
        or matches(tok[0], "MESS")
        or matches(tok[0], "ENER")
    ):
        return 0
    if matches(tok[0], "NODE"):
        if matches(tok[n], "NONE") or matches(tok[n], "ALL"):
            return 0
        if pr.net.nnodes == 0:
            return 203
        for i in range(1, n + 1):  # pragma: no branch
            if findnode(pr.net, tok[i]) == 0:
                return 203
        return 0
    if matches(tok[0], "LINK"):
        if matches(tok[n], "NONE") or matches(tok[n], "ALL"):
            return 0
        if pr.net.nlinks == 0:
            return 204
        for i in range(1, n + 1):  # pragma: no branch
            if findlink(pr.net, tok[i]) == 0:
                return 204
        return 0
    var i: Int
    if _strcomp(tok[0], "HEADLOSS"):
        i = 9
    else:
        i = findmatch(tok[0], materialize[FIELD_WORDS]())
    if i >= 0:
        if matches(tok[1], "YES") or matches(tok[1], "NO"):
            return 0
        if len(tok) < 3:
            return 201
        if not (
            matches(tok[1], "BELOW")
            or matches(tok[1], "ABOVE")
            or matches(tok[1], "PREC")
        ):
            return 213
        if not get_float(tok[2], y):
            return 202
        return 0
    if matches(tok[0], "FILE"):
        return 0
    return 201


def timedata(mut pr: Project) -> Int:
    """Read a line of the [TIMES] section.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var y = 0.0
    var n = len(pr.parser.tok) - 1
    if n < 1:
        return 201
    ref tok = pr.parser.tok
    if matches(tok[0], "STAT"):
        if (
            matches(tok[n], "NONE")
            or matches(tok[n], "NO")
            or matches(tok[n], "AVERAGE")
            or matches(tok[n], "MINIMUM")
            or matches(tok[n], "MAXIMUM")
            or matches(tok[n], "RANGE")
        ):
            return 0
        return 213
    if not get_float(tok[n], y):
        y = hour(tok[n], String())
        if y < 0.0:
            y = hour(tok[n - 1], tok[n])
            if y < 0.0:
                return 213
    if not (y >= 0.0 and y < _MAX_HOURS):
        return 213
    var t = Int(mul(3600.0, y) + 0.5)
    if matches(tok[0], "DURA"):
        pr.times.dur = t
    elif matches(tok[0], "HYDR"):
        pr.times.hstep = t
    elif matches(tok[0], "QUAL"):
        pr.times.qstep = t
    elif matches(tok[0], "RULE"):
        pr.times.rulestep = t
    elif matches(tok[0], "MINI"):
        return 0
    elif matches(tok[0], "PATT"):
        if matches(tok[1], "TIME"):
            pr.times.pstep = t
        elif matches(tok[1], "STAR"):
            pr.times.pstart = t
        else:
            return 213
    elif matches(tok[0], "REPO"):
        if matches(tok[1], "TIME"):
            pr.times.rstep = t
        elif matches(tok[1], "STAR"):
            pr.times.rstart = t
        else:
            return 213
    elif matches(tok[0], "STAR"):
        pr.times.tstart = t % SEC_PER_DAY
    else:
        return 213
    return 0


def optiondata(mut pr: Project) -> Int:
    """Read a line of the [OPTIONS] section.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var n = len(pr.parser.tok) - 1
    var i = optionchoice(pr, n)
    if i >= 0:
        return i
    return optionvalue(pr, n)


def optionchoice(mut pr: Project, n: Int) -> Int:
    """Read an option that is a choice of keywords.

    Args:
        pr: The project.
        n: The index of the last token.

    Returns:
        0, an error code, or -1 if the option is not a choice.
    """
    # `readdata` skips a line with no tokens, so `n >= 0`.
    var t0 = pr.parser.tok[0]
    if matches(t0, "UNIT"):
        if n < 1:
            return 0
        if not getunitsoption(pr, pr.parser.tok[1].copy()):
            return 213
    elif matches(t0, "PRESSURE"):
        if n < 1:
            return 0
        ref t1 = pr.parser.tok[1]
        if matches(t1, "EXP"):
            return -1
        elif matches(t1, "PSI"):
            pr.parser.press_flag = PSI
        elif matches(t1, "KPA"):
            pr.parser.press_flag = KPA
        elif matches(t1, "METERS"):
            pr.parser.press_flag = METERS
        elif matches(t1, "BAR"):
            pr.parser.press_flag = BAR
        elif matches(t1, "FEET"):
            pr.parser.press_flag = FEET
        else:
            return 213
    elif matches(t0, "HEADL"):
        if n < 1:
            return 0
        if not getheadlossoption(pr, pr.parser.tok[1].copy()):
            return 213
    elif matches(t0, "HYDR"):
        if n < 2:
            return 0
        if not (
            matches(pr.parser.tok[1], "USE")
            or matches(pr.parser.tok[1], "SAVE")
        ):
            return 213
    elif matches(t0, "QUAL"):
        if n < 1:
            return 0
        ref t1 = pr.parser.tok[1]
        if matches(t1, "NONE"):
            pr.qual.qualflag = NONE
        elif matches(t1, "CHEM"):
            pr.qual.qualflag = CHEM
        elif matches(t1, "AGE"):
            pr.qual.qualflag = AGE
        elif matches(t1, "TRACE"):
            pr.qual.qualflag = TRACE
        else:
            pr.qual.qualflag = CHEM
            pr.qual.chem_name = t1
            if n >= 2:
                pr.qual.chem_units = pr.parser.tok[2]
        if pr.qual.qualflag == TRACE:
            if n < 2:
                return 201
            pr.qual.trace_node = findnode(pr.net, pr.parser.tok[2])
            if pr.qual.trace_node == 0:
                return 212
            pr.qual.chem_name = "% from"
            pr.qual.chem_units = pr.parser.tok[2]
        if pr.qual.qualflag == AGE:
            pr.qual.chem_name = "AGE"
            pr.qual.chem_units = "hrs"
    elif matches(t0, "MAP") or matches(t0, "VERI"):
        return 0
    elif matches(t0, "UNBA"):
        if n < 1:
            return 0
        if matches(pr.parser.tok[1], "STOP"):
            pr.hyd.extra_iter = -1
        elif matches(pr.parser.tok[1], "CONT"):
            if n >= 2:
                pr.hyd.extra_iter = atol(pr.parser.tok[2])
            else:
                pr.hyd.extra_iter = 0
        else:
            return 213
    elif matches(t0, "PATT"):
        if n < 1:
            return 0
        pr.parser.def_pat_id = pr.parser.tok[1]
    elif matches(t0, "DEMAND"):
        if n < 2:
            return 0
        if not matches(pr.parser.tok[1], "MODEL"):
            return -1
        var choice = findmatch(
            pr.parser.tok[2], materialize[DEMAND_MODEL_WORDS]()
        )
        if choice < 0:
            return 213
        pr.hyd.demand_model = DemandModel(choice)
    elif matches(t0, "BACK"):
        if n < 2:
            return 0
        if not matches(pr.parser.tok[1], "ALLOW"):
            return -1
        var choice = findmatch(pr.parser.tok[2], materialize[BACKFLOW_WORDS]())
        if choice < 0:
            return 213
        pr.hyd.emit_back_flag = choice == 1
    else:
        return -1
    return 0


def optionvalue(mut pr: Project, n: Int) -> Int:
    """Read an option that is a number.

    Args:
        pr: The project.
        n: The index of the last token.

    Returns:
        0, or an error code.
    """
    var y = 0.0
    var nvalue = 1
    var t0 = pr.parser.tok[0]
    if matches(t0, "SEGM"):
        return 0
    if (
        matches(t0, "SPEC")
        or matches(t0, "EMIT")
        or matches(t0, "DEMAND")
        or matches(t0, "MINI")
        or matches(t0, "REQ")
        or matches(t0, "PRESSURE")
        or matches(t0, "PREC")
    ):
        nvalue = 2
    if n < nvalue:
        return 0
    if not get_float(pr.parser.tok[nvalue], y):
        return 202
    if y < 0.0:
        return 213
    if matches(t0, "TOLER"):
        pr.qual.ctol = y
        return 0
    if matches(t0, "DIFF"):
        pr.qual.diffus = y
        return 0
    if matches(t0, "CHECKFREQ"):
        pr.hyd.check_freq = _to_int(y)
        return 0
    if matches(t0, "MAXCHECK"):
        pr.hyd.max_check = _to_int(y)
        return 0
    if matches(t0, "DAMPLIMIT"):
        pr.hyd.damp_limit = y
        return 0
    if matches(t0, "FLOWCHANGE"):
        pr.hyd.flow_change_limit = y
        return 0
    if matches(t0, "HEADERROR"):
        pr.hyd.head_error_limit = y
        return 0
    if matches(t0, "MINI"):
        if pr.hyd.preq == MINPDIFF:
            pr.hyd.preq = y + MINPDIFF
        elif pr.hyd.preq - y < MINPDIFF:
            return 208
        pr.hyd.pmin = y
        return 0
    if matches(t0, "REQ"):
        if y - pr.hyd.pmin < MINPDIFF:
            return 208
        pr.hyd.preq = y
        return 0
    if matches(t0, "PRESSURE"):
        if y <= 0.0:
            return 213
        pr.hyd.pexp = y
        return 0
    if y <= 0.0:
        return 213
    # CHECKFREQ and MAXCHECK have returned above.
    if matches(t0, "TRIAL") and not (y <= _MAX_INT32):
        return 213
    if matches(t0, "VISC"):
        pr.hyd.viscos = y
    elif matches(t0, "SPEC"):
        pr.hyd.sp_grav = y
    elif matches(t0, "TRIAL"):
        if y < 1.0:
            return 213
        pr.hyd.max_iter = Int(y)
    elif matches(t0, "ACCU"):
        pr.hyd.hacc = min(max(y, 1.0e-5), 1.0e-1)
    elif matches(t0, "HTOL"):
        pr.hyd.htol = y
    elif matches(t0, "QTOL"):
        pr.hyd.qtol = y
    elif matches(t0, "RQTOL"):
        if y >= 1.0:
            return 213
        pr.hyd.rqtol = y
    elif matches(t0, "EMIT"):
        pr.hyd.qexp = 1.0 / y
    elif matches(t0, "DEMAND"):
        pr.hyd.dmult = y
    else:
        return 201
    return 0


def _to_int(y: Float64) -> Int:
    """Convert to an int as a C cast to a 32-bit int does in range."""
    if y > _MAX_INT32:
        return 2147483647
    return Int(y)


def tagdata(pr: Project) -> Int:
    """Check a line of the [TAGS] section. Tags are not kept.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    if len(pr.parser.tok) < 3:
        return 201
    if matches(pr.parser.tok[0], "NODE"):
        if findnode(pr.net, pr.parser.tok[1]) == 0:
            return 203
    elif matches(pr.parser.tok[0], "LINK"):
        if findlink(pr.net, pr.parser.tok[1]) == 0:
            return 203
    return 0
