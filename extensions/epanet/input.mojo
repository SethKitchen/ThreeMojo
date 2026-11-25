# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from input2.c and input3.c of OWA EPANET 2.3.6. Copyright (c) 2023
# the EPANET contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The reader of an EPANET input file.

`netsize` counts the objects of each kind, `allocdata` makes the arrays,
and `readdata` reads each line into the network. A line with an error
does not stop the reader: it records the error and reads the next line,
as EPANET does. Then `readdata` returns error 200.

The reader keeps the data of the sections that change a result. It
reads the [COORDINATES], [VERTICES], [LABELS], [BACKDROP] and [TAGS]
sections without keeping their data, because no computation uses them.
"""

from extensions.epanet.cmath import mul
from extensions.epanet.kinds import (
    ACTIVE,
    AFD,
    CFS,
    CLOSED,
    CM,
    CMD,
    CMH,
    CMS,
    CONCEN,
    CVPIPE,
    ControlType,
    CurveType,
    DW,
    FCV,
    FLOWPACED,
    GPM,
    GPV,
    HILEVEL,
    HLOSS_CURVE,
    HW,
    IMGD,
    JUNCTION,
    LOWLEVEL,
    LPM,
    LPS,
    LinkType,
    MASS,
    MAXID,
    MGD,
    MISSING,
    MIX1,
    MLD,
    NOCURVE,
    CONST_HP,
    CUSTOM,
    OPEN,
    PBV,
    PCV,
    PI,
    PIPE,
    PRV,
    PSV,
    PUMP,
    RESERVOIR,
    SETPOINT,
    SEC_PER_DAY,
    SI,
    SourceType,
    StatusType,
    TANK,
    TCV,
    TIMEOFDAY,
    TIMER,
    US,
    VALVE_CURVE,
    VOLUME_CURVE,
)
from extensions.epanet.lookup import (
    adddemand,
    findcurve,
    findlink,
    findnode,
    findpattern,
    valvecheck,
)
from extensions.epanet.model import (
    Control,
    Curve,
    Link,
    Node,
    Pattern,
    Project,
    Rule,
    Pump,
    Source,
    Tank,
    Valve,
)
from extensions.epanet.options import (
    energydata,
    mixingdata,
    optiondata,
    reactdata,
    reportdata,
    statusdata,
    tagdata,
    timedata,
)
from extensions.epanet.ruleparse import addrule, deleterule, ruledata
from extensions.epanet.text import (
    CURVE_WORDS,
    S_BACKDROP,
    S_CONTROLS,
    S_COORDS,
    S_CURVES,
    S_DEMANDS,
    S_EMITTERS,
    S_END,
    S_ENERGY,
    S_JUNCTIONS,
    S_LABELS,
    S_LEAKAGE,
    S_MIXING,
    S_OPTIONS,
    S_PATTERNS,
    S_PIPES,
    S_PUMPS,
    S_QUALITY,
    S_REACTIONS,
    S_REPORT,
    S_RESERVOIRS,
    S_ROUGHNESS,
    S_RULES,
    S_SOURCES,
    S_STATUS,
    S_TAGS,
    S_TANKS,
    S_TIMES,
    S_TITLE,
    S_VALVES,
    S_VERTICES,
    SECTIONS,
    atol,
    findmatch,
    get_float,
    get_tokens,
    hour,
    matches,
    strcmp,
)


def error_text(code: Int) -> String:
    """Return the text of an EPANET error code, as `errors.dat` gives it.

    Args:
        code: The error code.

    Returns:
        The text, or "unknown error" for a code that has none.
    """
    var codes: List[Int] = [
        103,
        104,
        105,
        110,
        120,
        200,
        201,
        202,
        203,
        204,
        205,
        206,
        207,
        208,
        209,
        211,
        212,
        213,
        215,
        216,
        217,
        219,
        220,
        221,
        222,
        223,
        224,
        225,
        226,
        227,
        228,
        230,
        231,
        232,
        233,
        252,
        299,
        307,
    ]
    var texts: List[String] = [
        "hydraulic solver not opened",
        "no hydraulics for water quality analysis",
        "water quality solver not opened",
        "cannot solve network hydraulic equations",
        "cannot solve water quality transport equations",
        "one or more errors in input file",
        "syntax error",
        "illegal numeric value",
        "undefined node",
        "undefined link",
        "undefined time pattern",
        "undefined curve",
        "attempt to control CV/GPV link",
        "illegal PDA pressure limits",
        "illegal node property value",
        "illegal link property value",
        "undefined trace node",
        "invalid option value",
        "duplicate ID label",
        "reference to undefined pump",
        "invalid pump energy data",
        "illegal valve connection to tank node",
        "illegal valve connection to another valve",
        "mis-placed rule clause in rule-based control",
        "same start and end nodes for link",
        "not enough nodes in network",
        "no tanks or reservoirs in network",
        "invalid lower/upper levels for tank",
        "no head curve or power rating for pump",
        "invalid head curve for pump",
        "invalid volume curve for tank",
        "nonincreasing x-values for curve",
        "no data provided for curve",
        "no data provided for pattern",
        "network has unconnected nodes",
        "invalid ID name",
        "invalid section keyword",
        "cannot read hydraulics file",
    ]
    for i in range(len(codes)):  # pragma: no branch
        if codes[i] == code:
            return texts[i]
    return "unknown error"


def _strtok_first(line: String) -> String:
    """Return the first token of a line as `strtok` with " \\t\\n\\r" does.

    The count pass of EPANET reads the first token this way, without the
    quote and comment rules of `gettokens`.
    """
    var b = line.as_bytes()
    var s = 0
    # The text is split at each newline, so a line holds no newline.
    while s < len(b) and (b[s] == 32 or b[s] == 9 or b[s] == 13):
        s += 1
    var e = s
    while e < len(b) and not (b[e] == 32 or b[e] == 9 or b[e] == 13):
        e += 1
    return String(line[byte=s:e])


def addpattern(mut pr: Project, id: String) -> Int:
    """Add a pattern to the network, unless it exists.

    Args:
        pr: The project.
        id: The name of the pattern.

    Returns:
        0, or error 252 for a name longer than 31 characters.
    """
    var n = pr.net.npats
    if n > 0:
        if id == pr.net.pattern[n].id:
            return 0
        if findpattern(pr.net, id) > 0:
            return 0
    if id.byte_length() > MAXID:
        return 252
    pr.net.pattern.append(Pattern(id))
    pr.net.npats += 1
    return 0


def addcurve(mut pr: Project, id: String) -> Int:
    """Add a curve to the network, unless it exists.

    Args:
        pr: The project.
        id: The name of the curve.

    Returns:
        0, or error 252 for a name longer than 31 characters.
    """
    var n = pr.net.ncurves
    if n > 0:
        if id == pr.net.curve[n].id:
            return 0
        if findcurve(pr.net, id) > 0:
            return 0
    if id.byte_length() > MAXID:
        return 252
    pr.net.curve.append(Curve(id))
    pr.net.ncurves += 1
    return 0


def netsize(mut pr: Project, lines: List[String]) -> Int:
    """Count the objects of each kind in an input file.

    It also makes pattern 0, the pattern of constant 1, and adds the
    patterns and the curves of the file.

    Args:
        pr: The project.
        lines: The lines of the input file.

    Returns:
        0, or the error code of a pattern or a curve name.
    """
    pr.parser.max_juncs = 0
    pr.parser.max_tanks = 0
    pr.parser.max_pipes = 0
    pr.parser.max_pumps = 0
    pr.parser.max_valves = 0
    pr.parser.max_controls = 0
    pr.parser.max_rules = 0
    pr.parser.max_curves = 0
    var sect = -1
    var errcode = 0
    pr.net.npats = -1
    pr.net.pattern = List[Pattern]()
    pr.net.curve = List[Curve]()
    pr.net.curve.append(Curve(String()))
    _ = addpattern(pr, String())
    pr.net.pattern[0].f.append(1.0)
    pr.parser.max_pats = pr.net.npats
    for line in lines:  # pragma: no branch
        var tok = _strtok_first(line)
        if tok.byte_length() == 0:
            continue
        var first = tok.as_bytes()[0]
        if first == 59:
            continue
        if first == 91:
            var newsect = findmatch(tok, materialize[SECTIONS]())
            if newsect >= 0:
                sect = newsect
                if sect == S_END:
                    break
                continue
            sect = -1
            continue
        if sect == S_JUNCTIONS:
            pr.parser.max_juncs += 1
        elif sect == S_RESERVOIRS or sect == S_TANKS:
            pr.parser.max_tanks += 1
        elif sect == S_PIPES:
            pr.parser.max_pipes += 1
        elif sect == S_PUMPS:
            pr.parser.max_pumps += 1
        elif sect == S_VALVES:
            pr.parser.max_valves += 1
        elif sect == S_CONTROLS:
            pr.parser.max_controls += 1
        elif sect == S_RULES:
            addrule(pr, tok)
        elif sect == S_PATTERNS:
            errcode = addpattern(pr, tok)
            pr.parser.max_pats = pr.net.npats
        elif sect == S_CURVES:
            errcode = addcurve(pr, tok)
            pr.parser.max_curves = pr.net.ncurves
        if errcode != 0:
            break
    pr.parser.max_nodes = pr.parser.max_juncs + pr.parser.max_tanks
    pr.parser.max_links = (
        pr.parser.max_pipes + pr.parser.max_pumps + pr.parser.max_valves
    )
    if pr.parser.max_pats < 1:
        pr.parser.max_pats = 1
    return errcode


def allocdata(mut pr: Project):
    """Make the arrays of the network and of the solvers.

    Each array has one entry more than its count, because index 0 is
    not used.

    Args:
        pr: The project, after `netsize`.
    """
    var n = pr.parser.max_nodes + 1
    pr.net.node = List[Node]()
    for _ in range(n):  # pragma: no branch
        pr.net.node.append(Node())
    pr.hyd.node_demand = List[Float64](length=n, fill=0.0)
    pr.hyd.node_head = List[Float64](length=n, fill=0.0)
    pr.qual.node_qual = List[Float64](length=n, fill=0.0)
    pr.hyd.full_demand = List[Float64](length=n, fill=0.0)
    pr.hyd.demand_flow = List[Float64](length=n, fill=0.0)
    pr.hyd.emitter_flow = List[Float64](length=n, fill=0.0)
    pr.hyd.leakage_flow = List[Float64](length=n, fill=0.0)
    var m = pr.parser.max_links + 1
    pr.net.link = List[Link]()
    for _ in range(m):  # pragma: no branch
        pr.net.link.append(Link())
    pr.hyd.link_flow = List[Float64](length=m, fill=0.0)
    pr.hyd.link_setting = List[Float64](length=m, fill=0.0)
    pr.hyd.link_status = List[StatusType](length=m, fill=StatusType(0))
    pr.net.tank = List[Tank]()
    for _ in range(pr.parser.max_tanks + 1):  # pragma: no branch
        pr.net.tank.append(Tank())
    pr.net.pump = List[Pump]()
    for _ in range(pr.parser.max_pumps + 1):  # pragma: no branch
        pr.net.pump.append(Pump())
    pr.net.valve = List[Valve]()
    for _ in range(pr.parser.max_valves + 1):  # pragma: no branch
        pr.net.valve.append(Valve(0, 0))
    pr.net.control = List[Control]()
    for _ in range(pr.parser.max_controls + 1):  # pragma: no branch
        pr.net.control.append(
            Control(0, 0, 0, 0.0, 0.0, StatusType(0), ControlType(0), True)
        )
    pr.net.rule = List[Rule]()
    for _ in range(pr.parser.max_rules + 1):  # pragma: no branch
        pr.net.rule.append(Rule(String()))


def readdata(
    mut pr: Project, lines: List[String], mut errors: List[String]
) -> Int:
    """Read the lines of an input file into the network.

    Args:
        pr: The project, after `netsize` and `allocdata`.
        lines: The lines of the input file.
        errors: Receives a message for each line with an error.

    Returns:
        0, or 200 if one or more lines have an error.
    """
    pr.net.nnodes = 0
    pr.net.njuncs = 0
    pr.net.ntanks = 0
    pr.net.nlinks = 0
    pr.net.npipes = 0
    pr.net.npumps = 0
    pr.net.nvalves = 0
    pr.net.ncontrols = 0
    pr.net.nrules = 0
    pr.parser.max_pats = pr.net.npats
    pr.parser.max_curves = pr.net.ncurves
    pr.parser.prev_pat = 0
    pr.parser.prev_curve = 0
    var sect = -1
    var errsum = 0
    for i in range(len(lines)):  # pragma: no branch
        ref line = lines[i]
        pr.parser.line_number = i + 1
        # `fgets` keeps the line feed of each line but the last. It ends
        # a quoted last token, as in C.
        if i + 1 < len(lines):
            pr.parser.tok = get_tokens(line + "\n")
        else:
            pr.parser.tok = get_tokens(line)
        if len(pr.parser.tok) == 0:
            continue
        if pr.parser.tok[0].byte_length() > 0 and (
            pr.parser.tok[0].as_bytes()[0] == 91
        ):
            var newsect = findmatch(pr.parser.tok[0], materialize[SECTIONS]())
            if newsect >= 0:
                sect = newsect
                if sect == S_END:
                    break
                continue
            sect = -1
            errsum += 1
            errors.append(_message(299, i + 1, line))
            continue
        if sect >= 0:
            var inperr = newline(pr, sect, line)
            if inperr > 0:
                errsum += 1
                errors.append(_message(inperr, i + 1, line))
    if errsum > 0:
        return 200
    return 0


def _message(code: Int, number: Int, line: String) -> String:
    """Return the message of an input error."""
    return String(
        "Error ", code, ": ", error_text(code), " at line ", number, ": ", line
    )


def newline(mut pr: Project, sect: Int, line: String) -> Int:
    """Read one data line of a section.

    Args:
        pr: The project.
        sect: The section.
        line: The line, for a title line.

    Returns:
        0, or an error code.
    """
    if sect == S_TITLE:
        if len(pr.title) < 3:
            var text = line
            if text.byte_length() > 79:
                var cut = String(text[byte=0:79])
                text = cut
            pr.title.append(text)
        return 0
    if sect == S_JUNCTIONS:
        return juncdata(pr)
    if sect == S_RESERVOIRS or sect == S_TANKS:
        return tankdata(pr)
    if sect == S_PIPES:
        return pipedata(pr)
    if sect == S_PUMPS:
        return pumpdata(pr)
    if sect == S_VALVES:
        return valvedata(pr)
    if sect == S_PATTERNS:
        return patterndata(pr)
    if sect == S_CURVES:
        return curvedata(pr)
    if sect == S_DEMANDS:
        return demanddata(pr)
    if sect == S_CONTROLS:
        return controldata(pr)
    if sect == S_RULES:
        # The C code reports the code of the rule error, then returns 200.
        var err = ruledata(pr)
        if err > 0:
            deleterule(pr, pr.net.nrules)
        return err
    if sect == S_SOURCES:
        return sourcedata(pr)
    if sect == S_EMITTERS:
        return emitterdata(pr)
    if sect == S_LEAKAGE:
        return leakagedata(pr)
    if sect == S_QUALITY:
        return qualdata(pr)
    if sect == S_STATUS:
        return statusdata(pr)
    if sect == S_ENERGY:
        return energydata(pr)
    if sect == S_REACTIONS:
        return reactdata(pr)
    if sect == S_MIXING:
        return mixingdata(pr)
    if sect == S_REPORT:
        return reportdata(pr)
    if sect == S_TIMES:
        return timedata(pr)
    if sect == S_OPTIONS:
        return optiondata(pr)
    if sect == S_TAGS:
        return tagdata(pr)
    # [ROUGHNESS], [COORDINATES], [VERTICES], [LABELS] and
    # [BACKDROP]: no computation uses these data.
    return 0


def addnode_id(mut pr: Project, n: Int, id: String) -> Int:
    """Give a name to a node, as `addnodeID` does.

    Args:
        pr: The project.
        n: The node index.
        id: The name.

    Returns:
        0, error 215 for a name in use, or 252 for a name too long.
    """
    if findnode(pr.net, id) != 0:
        return 215
    if id.byte_length() > MAXID:
        return 252
    pr.net.node[n].id = id
    pr.net.node_index[id] = n
    return 0


def addlink_id(mut pr: Project, n: Int, id: String) -> Int:
    """Give a name to a link, as `addlinkID` does.

    Args:
        pr: The project.
        n: The link index.
        id: The name.

    Returns:
        0, error 215 for a name in use, or 252 for a name too long.
    """
    if findlink(pr.net, id) != 0:
        return 215
    if id.byte_length() > MAXID:
        return 252
    pr.net.link[n].id = id
    pr.net.link_index[id] = n
    return 0


def juncdata(mut pr: Project) -> Int:
    """Read a line of the [JUNCTIONS] section: id, elevation, demand, pattern.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var p = 0
    var el = 0.0
    var d = 0.0
    var x = 0.0
    var errcode: Int
    # `netsize` counted each line, so the arrays have room for this node.
    errcode = addnode_id(pr, pr.net.njuncs + 1, pr.parser.tok[0].copy())
    if errcode > 0:
        return errcode
    pr.net.njuncs += 1
    pr.net.nnodes += 1
    var n = len(pr.parser.tok)
    if n > 1:
        if not get_float(pr.parser.tok[1], x):
            errcode = 202
        else:
            el = x
    if errcode == 0 and n > 2:
        if not get_float(pr.parser.tok[2], x):
            errcode = 202
        else:
            d = x
    if errcode == 0 and n > 3:
        p = findpattern(pr.net, pr.parser.tok[3])
        if p < 0:
            errcode = 205
    var njuncs = pr.net.njuncs
    ref node = pr.net.node[njuncs]
    node.el = el
    node.c0 = 0.0
    node.has_source = False
    node.ke = 0.0
    node.type = JUNCTION
    adddemand(node, d, p, String())
    pr.hyd.node_demand[njuncs] = d
    return errcode


def _tokvalue(pr: Project, x: Float64, itok: Int, mut errcode: Int) -> Float64:
    """Read a token as a value of zero or more, as `gettokvalue` does."""
    if errcode != 0:
        return x
    var result = 0.0
    if not get_float(pr.parser.tok[itok], result):
        errcode = 202
    elif result < 0.0:
        errcode = 209
    if errcode > 0:
        result = x
    return result


def tankdata(mut pr: Project) -> Int:
    """Read a line of the [RESERVOIRS] or the [TANKS] section.

    A reservoir line is: id, elevation, head pattern. A tank line is: id,
    elevation, initial level, minimum level, maximum level, diameter,
    minimum volume, volume curve, overflow.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var pattern = 0
    var curve = 0
    var overflow = False
    var el = 0.0
    var initlevel = 0.0
    var minlevel = 0.0
    var maxlevel = 0.0
    var minvol = 0.0
    var diam = 0.0
    var errcode: Int
    var x = 0.0
    var i = pr.parser.max_juncs + pr.net.ntanks + 1
    errcode = addnode_id(pr, i, pr.parser.tok[0].copy())
    if errcode != 0:
        return errcode
    pr.net.ntanks += 1
    pr.net.nnodes += 1
    var n = len(pr.parser.tok)
    if n < 2:
        errcode = 201
    else:
        if not get_float(pr.parser.tok[1], x):
            errcode = 202
        else:
            el = x
    if n <= 3:
        if n == 3 and errcode == 0:
            pattern = findpattern(pr.net, pr.parser.tok[2])
            if pattern < 0:
                errcode = 205
    elif errcode == 0:
        if n < 6:
            errcode = 201
        else:
            initlevel = _tokvalue(pr, initlevel, 2, errcode)
            minlevel = _tokvalue(pr, minlevel, 3, errcode)
            maxlevel = _tokvalue(pr, maxlevel, 4, errcode)
            diam = _tokvalue(pr, diam, 5, errcode)
            if n >= 7:
                minvol = _tokvalue(pr, minvol, 6, errcode)
            if errcode == 0 and n >= 8:
                ref t7 = pr.parser.tok[7]
                if t7.byte_length() > 0 and t7.as_bytes()[0] != 42:
                    curve = findcurve(pr.net, t7)
                    if curve == 0:
                        errcode = 206
                    else:
                        pr.net.curve[curve].type = VOLUME_CURVE
            if errcode == 0 and n >= 9:
                if matches(pr.parser.tok[8], "YES"):
                    overflow = True
                elif matches(pr.parser.tok[8], "NO"):
                    overflow = False
                else:
                    errcode = 213
    ref node = pr.net.node[i]
    node.el = el
    node.c0 = 0.0
    node.has_source = False
    node.ke = 0.0
    node.type = RESERVOIR if diam == 0.0 else TANK
    ref tank = pr.net.tank[pr.net.ntanks]
    tank.node = i
    tank.h0 = initlevel
    tank.hmin = minlevel
    tank.hmax = maxlevel
    tank.a = diam
    tank.pat = pattern
    tank.kb = MISSING
    tank.can_overflow = overflow
    var area = mul(PI, mul(diam, diam)) / 4.0
    tank.vmin = mul(area, minlevel)
    if minvol > 0.0:
        tank.vmin = minvol
    tank.v0 = tank.vmin + mul(area, initlevel - minlevel)
    tank.vmax = tank.vmin + mul(area, maxlevel - minlevel)
    tank.vcurve = curve
    tank.mix_model = MIX1
    tank.v1frac = 1.0
    return errcode


def _link_ends(pr: Project, mut j1: Int, mut j2: Int) -> Int:
    """Find the end nodes of a link line. Return 0 or an error code."""
    j1 = findnode(pr.net, pr.parser.tok[1])
    if j1 == 0:
        return 203
    j2 = findnode(pr.net, pr.parser.tok[2])
    if j2 == 0:
        return 203
    if j1 == j2:
        return 222
    return 0


def pipedata(mut pr: Project) -> Int:
    """Read a line of the [PIPES] section.

    The line is: id, start node, end node, length, diameter, roughness,
    minor loss, status.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var x = 0.0
    var n = len(pr.parser.tok)
    if n < 3:
        return 201
    var j1 = 0
    var j2 = 0
    var e = _link_ends(pr, j1, j2)
    if e != 0:
        return e
    var errcode = addlink_id(pr, pr.net.nlinks + 1, pr.parser.tok[0].copy())
    if errcode != 0:
        return errcode
    pr.net.npipes += 1
    pr.net.nlinks += 1
    var si = pr.parser.units_flag == SI
    var formflag = pr.hyd.formflag
    ref link = pr.net.link[pr.net.nlinks]
    link.n1 = j1
    link.n2 = j2
    if si:
        link.len = 100.0
        link.diam = 254.0
    else:
        link.len = 330.0
        link.diam = 10.0
    if formflag == HW:
        link.kc = 130.0
    elif formflag == DW:
        link.kc = 0.0005
    else:
        link.kc = 0.01
    link.km = 0.0
    link.kb = MISSING
    link.kw = MISSING
    link.leak_area = 0.0
    link.leak_expan = 0.0
    link.type = PIPE
    link.init_status = OPEN
    link.init_setting = link.kc
    ref tok = pr.parser.tok
    if n > 3:
        if not get_float(tok[3], x) or x <= 0.0:
            return 202
        link.len = x
    if n > 4:
        if not get_float(tok[4], x) or x <= 0.0:
            return 202
        link.diam = x
    if n > 5:
        if not get_float(tok[5], x) or x <= 0.0:
            return 202
        link.kc = x
    if n > 6:
        if matches(tok[6], "CV"):
            link.type = CVPIPE
        elif matches(tok[6], "CLOSED"):
            link.init_status = CLOSED
        elif matches(tok[6], "OPEN"):
            link.init_status = OPEN
        else:
            if not get_float(tok[6], x) or x < 0.0:
                return 202
            link.km = x
    if n > 7:
        # The block above has checked a number in token 6 to be >= 0.
        if not get_float(tok[6], x):
            return 202
        link.km = x
        if matches(tok[7], "CV"):
            link.type = CVPIPE
        elif matches(tok[7], "CLOSED"):
            link.init_status = CLOSED
        elif matches(tok[7], "OPEN"):
            link.init_status = OPEN
        else:
            return 213
    return 0


def pumpdata(mut pr: Project) -> Int:
    """Read a line of the [PUMPS] section.

    The line is: id, start node, end node, then pairs of a keyword
    (POWER, HEAD, PATTERN or SPEED) and a value.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var y = 0.0
    var n = len(pr.parser.tok)
    if n < 3:
        return 201
    var j1 = 0
    var j2 = 0
    var e = _link_ends(pr, j1, j2)
    if e != 0:
        return e
    var errcode = addlink_id(pr, pr.net.nlinks + 1, pr.parser.tok[0].copy())
    if errcode != 0:
        return errcode
    pr.net.nlinks += 1
    pr.net.npumps += 1
    var k = pr.net.nlinks
    var pi = pr.net.npumps
    ref link = pr.net.link[k]
    link.n1 = j1
    link.n2 = j2
    link.diam = 0.0
    link.len = 0.0
    link.kc = 1.0
    link.km = 0.0
    link.kb = 0.0
    link.kw = 0.0
    link.leak_area = 0.0
    link.leak_expan = 0.0
    link.type = PUMP
    link.init_status = OPEN
    link.init_setting = 1.0
    ref pump = pr.net.pump[pi]
    pump.link = k
    pump.ptype = NOCURVE
    pump.hcurve = 0
    pump.ecurve = 0
    pump.upat = 0
    pump.ecost = 0.0
    pump.epat = 0
    if n < 4:
        return 0
    var m = 4
    while m < n:
        ref key = pr.parser.tok[m - 1]
        ref value = pr.parser.tok[m]
        if matches(key, "POWER"):
            if not get_float(value, y) or y <= 0.0:
                return 202
            pump.ptype = CONST_HP
            link.km = y
        elif matches(key, "HEAD"):
            var c = findcurve(pr.net, value)
            if c == 0:
                return 206
            pump.ptype = CUSTOM
            pump.hcurve = c
        elif matches(key, "PATT"):
            var p = findpattern(pr.net, value)
            if p < 0:
                return 205
            pump.upat = p
        elif matches(key, "SPEE"):
            if not get_float(value, y) or y < 0.0:
                return 202
            link.kc = y
        else:
            return 201
        m += 2
    link.init_setting = link.kc
    return 0


def valvedata(mut pr: Project) -> Int:
    """Read a line of the [VALVES] section.

    The line is: id, start node, end node, diameter, type, setting,
    minor loss, and the curve of a PCV.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var x = 0.0
    var n = len(pr.parser.tok)
    if n < 5:
        return 201
    var j1 = 0
    var j2 = 0
    var e = _link_ends(pr, j1, j2)
    if e != 0:
        return e
    var t4 = pr.parser.tok[4]
    var type: LinkType
    if matches(t4, "PRV"):
        type = PRV
    elif matches(t4, "PSV"):
        type = PSV
    elif matches(t4, "PBV"):
        type = PBV
    elif matches(t4, "FCV"):
        type = FCV
    elif matches(t4, "TCV"):
        type = TCV
    elif matches(t4, "GPV"):
        type = GPV
    elif matches(t4, "PCV"):
        type = PCV
    else:
        return 213
    var check = valvecheck(pr.net, type, j1, j2)
    if check != 0:
        return check
    var errcode = addlink_id(pr, pr.net.nlinks + 1, pr.parser.tok[0].copy())
    if errcode != 0:
        return errcode
    pr.net.nvalves += 1
    pr.net.nlinks += 1
    var k = pr.net.nlinks
    var v = pr.net.nvalves
    var si = pr.parser.units_flag == SI
    ref link = pr.net.link[k]
    link.n1 = j1
    link.n2 = j2
    link.diam = 254.0 if si else 10.0
    link.len = 0.0
    link.kc = 0.0
    link.km = 0.0
    link.kb = 0.0
    link.kw = 0.0
    link.leak_area = 0.0
    link.leak_expan = 0.0
    link.type = type
    link.init_status = ACTIVE
    link.init_setting = 0.0
    pr.net.valve[v].link = k
    pr.net.valve[v].curve = 0
    ref tok = pr.parser.tok
    if not get_float(tok[3], x) or x <= 0.0:
        return 202
    link.diam = x
    if n > 5:
        if type == GPV:
            var c = findcurve(pr.net, tok[5])
            if c == 0:
                return 206
            pr.net.valve[v].curve = c
            pr.net.curve[c].type = HLOSS_CURVE
            link.init_status = OPEN
        else:
            if not get_float(tok[5], x):
                return 202
            link.kc = x
    if n > 6:
        if not get_float(tok[6], x) or x < 0.0:
            return 202
        link.km = x
    if n > 7 and type == PCV:
        var c = findcurve(pr.net, tok[7])
        if c == 0:
            return 206
        pr.net.valve[v].curve = c
        pr.net.curve[c].type = VALVE_CURVE
        if link.kc > 100.0:
            link.kc = 100.0
    link.init_setting = link.kc
    return 0


def patterndata(mut pr: Project) -> Int:
    """Read a line of the [PATTERNS] section: id, then multipliers.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var x = 0.0
    var n = len(pr.parser.tok) - 1
    if n < 1:
        return 201
    var i: Int
    if (
        pr.parser.prev_pat != 0
        and pr.parser.tok[0] == pr.net.pattern[pr.parser.prev_pat].id
    ):
        i = pr.parser.prev_pat
    else:
        i = findpattern(pr.net, pr.parser.tok[0])
        if i <= 0:
            return 205
    ref pattern = pr.net.pattern[i]
    var n1 = len(pattern.f)
    for _ in range(n):  # pragma: no branch
        pattern.f.append(1.0)
    for j in range(1, n + 1):  # pragma: no branch
        if not get_float(pr.parser.tok[j], x):
            return 202
        pattern.f[n1 + j - 1] = x
    pr.parser.prev_pat = i
    return 0


def curvedata(mut pr: Project) -> Int:
    """Read a line of the [CURVES] section: id, x, y and a curve type.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var x = 0.0
    var y = 0.0
    if len(pr.parser.tok) < 3:
        return 201
    if not get_float(pr.parser.tok[1], x):
        return 202
    if not get_float(pr.parser.tok[2], y):
        return 202
    var ctype = -1
    if len(pr.parser.tok) > 3:
        ctype = findmatch(pr.parser.tok[3], materialize[CURVE_WORDS]())
    var i: Int
    if (
        pr.parser.prev_curve != 0
        and pr.parser.tok[0] == pr.net.curve[pr.parser.prev_curve].id
    ):
        i = pr.parser.prev_curve
    else:
        i = findcurve(pr.net, pr.parser.tok[0])
        if i == 0:
            return 206
    ref curve = pr.net.curve[i]
    curve.x.append(x)
    curve.y.append(y)
    if ctype >= 0:
        curve.type = CurveType(ctype)
    pr.parser.prev_curve = i
    return 0


def demanddata(mut pr: Project) -> Int:
    """Read a line of the [DEMANDS] section: node, base demand, pattern.

    The first demand of a junction in this section replaces the demand of
    the [JUNCTIONS] section. Each later one adds a demand category.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var y = 0.0
    var p = 0
    var n = len(pr.parser.tok)
    if n < 2:
        return 201
    if not get_float(pr.parser.tok[1], y):
        return 202
    var j = findnode(pr.net, pr.parser.tok[0])
    if j == 0:
        return 203
    if j > pr.net.njuncs:
        return 0
    if n >= 3:
        p = findpattern(pr.net, pr.parser.tok[2])
        if p < 0:
            return 205
    ref node = pr.net.node[j]
    # `juncdata` gives each junction a demand.
    if pr.hyd.node_demand[j] != MISSING:
        node.demands[0].base = y
        node.demands[0].pat = p
        pr.hyd.node_demand[j] = MISSING
    else:
        adddemand(node, y, p, String())
    return 0


def controldata(mut pr: Project) -> Int:
    """Read a line of the [CONTROLS] section.

    The forms are "LINK id setting IF NODE id BELOW|ABOVE level",
    "LINK id setting AT TIME t" and "LINK id setting AT CLOCKTIME t",
    each with an optional DISABLED at the end.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var i = 0
    var is_enabled = True
    var setting = MISSING
    var time = 0.0
    var level = 0.0
    var status = ACTIVE
    var n = len(pr.parser.tok)
    if n < 6:
        return 201
    ref tok = pr.parser.tok
    if matches(tok[n - 1], "DISABLED"):
        is_enabled = False
        n -= 1
    var k = findlink(pr.net, tok[1])
    if k == 0:
        return 204
    var linktype = pr.net.link[k].type
    if linktype == CVPIPE:
        return 207
    if matches(tok[2], "OPEN"):
        status = OPEN
        if linktype == PUMP:
            setting = 1.0
    elif matches(tok[2], "CLOSED"):
        status = CLOSED
        if linktype == PUMP:
            setting = 0.0
    elif linktype == GPV:
        return 207
    elif not get_float(tok[2], setting):
        return 202
    if linktype == PUMP or linktype == PIPE:
        if setting != MISSING:
            if setting < 0.0:
                return 211
            elif setting == 0.0:
                status = CLOSED
            else:
                status = OPEN
    var ctltype: ControlType
    if matches(tok[4], "TIME"):
        ctltype = TIMER
    elif matches(tok[4], "CLOCKTIME"):
        ctltype = TIMEOFDAY
    else:
        if n < 8:
            return 201
        i = findnode(pr.net, tok[5])
        if i == 0:
            return 203
        if matches(tok[6], "BELOW"):
            ctltype = LOWLEVEL
        elif matches(tok[6], "ABOVE"):
            ctltype = HILEVEL
        else:
            return 213
    if ctltype == TIMER or ctltype == TIMEOFDAY:
        if n == 6:
            time = hour(tok[5], String())
        if n >= 7:
            time = hour(tok[5], tok[6])
        if time < 0.0:
            return 213
    else:
        if not get_float(tok[7], level):
            return 202
    pr.net.ncontrols += 1
    ref control = pr.net.control[pr.net.ncontrols]
    control.link = k
    control.node = i
    control.type = ctltype
    control.status = status
    control.setting = setting
    control.time = Int(mul(3600.0, time) + 0.5)
    if ctltype == TIMEOFDAY:
        control.time = control.time % SEC_PER_DAY
    control.grade = level
    control.is_enabled = is_enabled
    return 0


def sourcedata(mut pr: Project) -> Int:
    """Read a line of the [SOURCES] section: node, type, strength, pattern.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var p = 0
    var type = CONCEN
    var c0 = 0.0
    var n = len(pr.parser.tok)
    if n < 2:
        return 201
    ref tok = pr.parser.tok
    var j = findnode(pr.net, tok[0])
    if j == 0:
        return 203
    var i = 2
    if matches(tok[1], "CONCEN"):
        type = CONCEN
    elif matches(tok[1], "MASS"):
        type = MASS
    elif matches(tok[1], "SETPOINT"):
        type = SETPOINT
    elif matches(tok[1], "FLOWPACED"):
        type = FLOWPACED
    else:
        i = 1
    if i >= n or not get_float(tok[i], c0):
        if i == 1:
            return 213
        return 202
    if n > i + 1 and tok[i + 1].byte_length() > 0 and tok[i + 1] != "*":
        p = findpattern(pr.net, tok[i + 1])
        if p < 0:
            return 205
    pr.net.node[j].has_source = True
    pr.net.node[j].source = Source(c0, p, 0.0, type)
    return 0


def emitterdata(mut pr: Project) -> Int:
    """Read a line of the [EMITTERS] section: junction, coefficient.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var k = 0.0
    if len(pr.parser.tok) < 2:
        return 201
    var j = findnode(pr.net, pr.parser.tok[0])
    if j == 0:
        return 203
    if j > pr.net.njuncs:
        return 0
    if not get_float(pr.parser.tok[1], k):
        return 202
    if k < 0.0:
        return 209
    pr.net.node[j].ke = k
    return 0


def leakagedata(mut pr: Project) -> Int:
    """Read a line of the [LEAKAGE] section: pipe, area and expansion.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var c1 = 0.0
    var c2 = 0.0
    if len(pr.parser.tok) < 3:
        return 201
    var j = findlink(pr.net, pr.parser.tok[0])
    if j == 0:
        return 203
    if pr.net.link[j].type.value > PIPE.value:
        return 0
    if not get_float(pr.parser.tok[1], c1):
        return 202
    if c1 < 0.0:
        return 209
    if not get_float(pr.parser.tok[2], c2):
        return 202
    if c2 < 0.0:
        return 209
    pr.net.link[j].leak_area = c1
    pr.net.link[j].leak_expan = c2
    return 0


def qualdata(mut pr: Project) -> Int:
    """Read a line of the [QUALITY] section.

    The line is a node and its initial quality, or a range of nodes and
    their initial quality.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var c0 = 0.0
    if pr.net.nnodes == 0:
        return 203
    var n = len(pr.parser.tok)
    if n < 2:
        return 0
    ref tok = pr.parser.tok
    if n == 2:
        var j = findnode(pr.net, tok[0])
        if j == 0:
            return 203
        if not get_float(tok[1], c0):
            return 202
        if c0 < 0.0:
            return 209
        pr.net.node[j].c0 = c0
        return 0
    if not get_float(tok[2], c0):
        return 202
    if c0 < 0.0:
        return 209
    var i1 = atol(tok[0])
    var i2 = 0
    if i1 > 0:
        i2 = atol(tok[1])
    # `qualdata` returned 203 above when there are no nodes.
    if i1 > 0 and i2 > 0:
        for j in range(1, pr.net.nnodes + 1):  # pragma: no branch
            var i = atol(pr.net.node[j].id)
            if i >= i1 and i <= i2:
                pr.net.node[j].c0 = c0
    else:
        for j in range(1, pr.net.nnodes + 1):  # pragma: no branch
            if (
                strcmp(tok[0], pr.net.node[j].id) <= 0
                and strcmp(tok[1], pr.net.node[j].id) >= 0
            ):
                pr.net.node[j].c0 = c0
    return 0
