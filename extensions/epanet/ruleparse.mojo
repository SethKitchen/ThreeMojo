# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from rules.c of OWA EPANET 2.3.6. Copyright (c) 2023 the EPANET
# contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The reader of the [RULES] section of an EPANET input file.

A rule is a RULE line, IF, AND and OR premises, THEN and ELSE actions,
and an optional PRIORITY and DISABLED line. A line with an error ends
the rule: the reader deletes it and skips the lines up to the next RULE.
"""

from std.math import floor

from extensions.epanet.cmath import mul
from extensions.epanet.kinds import CVPIPE, GPV, MISSING, PIPE
from extensions.epanet.lookup import findlink, findnode
from extensions.epanet.model import Action, Premise, Project, Rule
from extensions.epanet.text import findmatch, get_float, hour, matches

# The rule keywords, in the order of the Rulewords enumeration.
comptime RULE_WORDS: List[String] = [
    "RULE",
    "IF",
    "AND",
    "OR",
    "THEN",
    "ELSE",
    "PRIO",
    "DISABLED",
]
comptime R_RULE = 0
comptime R_IF = 1
comptime R_AND = 2
comptime R_OR = 3
comptime R_THEN = 4
comptime R_ELSE = 5
comptime R_PRIORITY = 6
comptime R_DISABLED = 7
comptime R_ERROR = 8

# The premise variables, in the order of the Varwords enumeration.
comptime VAR_WORDS: List[String] = [
    "DEMAND",
    "HEAD",
    "GRADE",
    "LEVEL",
    "PRESSURE",
    "FLOW",
    "STATUS",
    "SETTING",
    "POWER",
    "TIME",
    "CLOCKTIME",
    "FILLTIME",
    "DRAINTIME",
]
comptime R_DEMAND = 0
comptime R_HEAD = 1
comptime R_GRADE = 2
comptime R_LEVEL = 3
comptime R_PRESSURE = 4
comptime R_FLOW = 5
comptime R_STATUS = 6
comptime R_SETTING = 7
comptime R_POWER = 8
comptime R_TIME = 9
comptime R_CLOCKTIME = 10
comptime R_FILLTIME = 11
comptime R_DRAINTIME = 12

# The premise objects, in the order of the Objects enumeration.
comptime OBJECT_WORDS: List[String] = [
    "Junc",
    "Reser",
    "Tank",
    "Pipe",
    "Pump",
    "Valve",
    "NODE",
    "LINK",
    "SYSTEM",
]
comptime R_JUNC = 0
comptime R_RESERV = 1
comptime R_TANK = 2
comptime R_PIPE = 3
comptime R_PUMP = 4
comptime R_VALVE = 5
comptime R_NODE = 6
comptime R_LINK = 7
comptime R_SYSTEM = 8

# The relational operators. "<=" and ">=" come before "<" and ">", so
# that the first match is the right one.
comptime OPERATOR_WORDS: List[String] = [
    "=",
    "<>",
    "<=",
    ">=",
    "<",
    ">",
    "IS",
    "NOT",
    "BELOW",
    "ABOVE",
]
comptime EQ = 0
comptime NE = 1
comptime LE = 2
comptime GE = 3
comptime LT = 4
comptime GT = 5
comptime IS = 6
comptime NOT = 7
comptime BELOW = 8
comptime ABOVE = 9

# The status values of a premise or an action.
comptime VALUE_WORDS: List[String] = ["XXXX", "OPEN", "CLOSED", "ACTIVE"]
comptime IS_NUMBER = 0
comptime IS_OPEN = 1
comptime IS_CLOSED = 2
comptime IS_ACTIVE = 3


def addrule(mut pr: Project, tok: String):
    """Count a rule if a line of the [RULES] section starts with RULE.

    Args:
        pr: The project.
        tok: The first token of the line.
    """
    if matches(tok, "RULE"):
        pr.parser.max_rules += 1


def deleterule(mut pr: Project, index: Int):
    """Delete a rule and move the later rules down by one.

    Args:
        pr: The project.
        index: The rule index, or 0 for no rule, which does nothing.
    """
    if index < 1:
        return
    _ = pr.net.rule.pop(index)
    pr.net.rule.append(Rule(String()))
    pr.net.nrules -= 1


def adjusttankrules(mut pr: Project, ndiff: Int):
    """Move the tank indices of rule premises by `ndiff`.

    Args:
        pr: The project.
        ndiff: The change of each tank node index.
    """
    var njuncs = pr.net.njuncs
    for i in range(1, pr.net.nrules + 1):
        for ref p in pr.net.rule[i].premises:
            if p.object == R_NODE and p.index > njuncs:
                p.index += ndiff


def ruledata(mut pr: Project) -> Int:
    """Read a line of the [RULES] section.

    Args:
        pr: The project.

    Returns:
        0, or the error code of the line. On an error the rule state
        becomes an error state until the next RULE line.
    """
    var err = 0
    var key = findmatch(pr.parser.tok[0], materialize[RULE_WORDS]())
    var state = pr.rules.rule_state
    if state == R_ERROR and key != R_RULE:
        return 0
    if key == R_RULE:
        pr.net.nrules += 1
        newrule(pr)
        pr.rules.rule_state = R_RULE
        pr.rules.errcode = 0
        if len(pr.parser.tok) != 2:
            err = 201
    elif key == R_IF:
        if state != R_RULE:
            err = 221
        else:
            pr.rules.rule_state = R_IF
            err = newpremise(pr, R_AND)
    elif key == R_AND:
        if state == R_IF:
            err = newpremise(pr, R_AND)
        elif state == R_THEN or state == R_ELSE:
            err = newaction(pr)
        else:
            err = 221
    elif key == R_OR:
        if state == R_IF:
            err = newpremise(pr, R_OR)
        else:
            err = 221
    elif key == R_THEN:
        if state != R_IF:
            err = 221
        else:
            pr.rules.rule_state = R_THEN
            err = newaction(pr)
    elif key == R_ELSE:
        if state != R_THEN:
            err = 221
        else:
            pr.rules.rule_state = R_ELSE
            err = newaction(pr)
    elif key == R_PRIORITY:
        if state != R_THEN and state != R_ELSE:
            err = 221
        else:
            pr.rules.rule_state = R_PRIORITY
            err = newpriority(pr)
    elif key == R_DISABLED:
        if state != R_THEN and state != R_ELSE and state != R_PRIORITY:
            err = 221
        else:
            pr.net.rule[pr.net.nrules].is_enabled = False
    else:
        err = 201
    if err != 0:
        pr.rules.rule_state = R_ERROR
        pr.rules.errcode = err
    return err


def newrule(mut pr: Project):
    """Start the rule `nrules` with the label of the line.

    Args:
        pr: The project.
    """
    var label = String()
    if len(pr.parser.tok) > 1:
        label = pr.parser.tok[1]
    pr.net.rule[pr.net.nrules] = Rule(label)


def newpremise(mut pr: Project, logop: Int) -> Int:
    """Add a premise to the current rule.

    The forms are "IF|AND|OR object id variable operator value" and
    "IF|AND|OR SYSTEM variable operator value units".

    Args:
        pr: The project.
        logop: R_AND or R_OR.

    Returns:
        0, or an error code.
    """
    var ntok = len(pr.parser.tok)
    if ntok != 5 and ntok != 6:
        return 201
    ref tok = pr.parser.tok
    var i = findmatch(tok[1], materialize[OBJECT_WORDS]())
    var j = 0
    var v: Int
    if i == R_SYSTEM:
        v = findmatch(tok[2], materialize[VAR_WORDS]())
        if v != R_DEMAND and v != R_TIME and v != R_CLOCKTIME:
            return 201
    else:
        v = findmatch(tok[3], materialize[VAR_WORDS]())
        if v < 0:
            return 201
        if i == R_NODE or i == R_JUNC or i == R_RESERV or i == R_TANK:
            i = R_NODE
        elif i == R_LINK or i == R_PIPE or i == R_PUMP or i == R_VALVE:
            i = R_LINK
        else:
            return 201
        if i == R_NODE:
            j = findnode(pr.net, tok[2])
            if j == 0:
                return 203
            if v == R_FILLTIME or v == R_DRAINTIME:
                if j <= pr.net.njuncs:
                    return 201
            elif v > R_PRESSURE:
                return 201
        else:
            j = findlink(pr.net, tok[2])
            if j == 0:
                return 204
            if v != R_FLOW and v != R_STATUS and v != R_SETTING:
                return 201
    var m = 3 if i == R_SYSTEM else 4
    var k = findmatch(tok[m], materialize[OPERATOR_WORDS]())
    if k < 0:
        return 201
    var r = k
    if k == IS:
        r = EQ
    elif k == NOT:
        r = NE
    elif k == BELOW:
        r = LT
    elif k == ABOVE:
        r = GT
    var s = 0
    var x = MISSING
    if v == R_TIME or v == R_CLOCKTIME:
        if ntok == 6:
            x = mul(hour(tok[4], tok[5]), 3600.0)
        else:
            x = mul(hour(tok[4], String()), 3600.0)
        if x < 0.0:
            return 202
        x = floor(x + 0.5)
    else:
        var kv = findmatch(tok[ntok - 1], materialize[VALUE_WORDS]())
        if kv > IS_NUMBER:
            s = kv
        else:
            if not get_float(tok[ntok - 1], x):
                return 202
            if v == R_FILLTIME or v == R_DRAINTIME:
                x = mul(x, 3600.0)
    if s > IS_NUMBER and i != R_LINK:
        return 202
    pr.net.rule[pr.net.nrules].premises.append(Premise(logop, i, j, v, r, s, x))
    return 0


def newaction(mut pr: Project) -> Int:
    """Add an action to the current rule.

    The form is "THEN|ELSE|AND LINK id variable IS value".

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    if len(pr.parser.tok) != 6:
        return 201
    ref tok = pr.parser.tok
    var j = findlink(pr.net, tok[2])
    if j == 0:
        return 204
    var type = pr.net.link[j].type
    if type == CVPIPE:
        return 207
    var s = -1
    var x = MISSING
    var k = findmatch(tok[5], materialize[VALUE_WORDS]())
    if k > IS_NUMBER:
        s = k
    else:
        if not get_float(tok[5], x):
            return 202
        if x < 0.0:
            return 202
    if x != MISSING and type == GPV:
        return 202
    if x != MISSING and type == PIPE:
        s = IS_CLOSED if x == 0.0 else IS_OPEN
        x = MISSING
    if pr.rules.rule_state == R_THEN:
        pr.net.rule[pr.net.nrules].then_actions.append(Action(j, s, x))
    else:
        pr.net.rule[pr.net.nrules].else_actions.append(Action(j, s, x))
    return 0


def newpriority(mut pr: Project) -> Int:
    """Set the priority of the current rule.

    Args:
        pr: The project.

    Returns:
        0, or an error code.
    """
    var x = 0.0
    if len(pr.parser.tok) < 2:
        return 201
    if not get_float(pr.parser.tok[1], x):
        return 202
    pr.net.rule[pr.net.nrules].priority = x
    return 0
