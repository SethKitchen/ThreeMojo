# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from epanet.c of OWA EPANET 2.3.6. Copyright (c) 2023 the EPANET
# contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The results of a node or a link, as the EPANET toolkit gives them.

`node_value` and `link_value` follow `EN_getnodevalue` and
`EN_getlinkvalue` for the properties of a simulation. A value is in the
units of the input file.
"""

from extensions.epanet.cmath import mul
from extensions.epanet.hydraul import getenergy
from extensions.epanet.kinds import (
    CLOSED,
    CVPIPE,
    DW,
    EN_DEMAND,
    EN_ENERGY,
    EN_FLOW,
    EN_HEAD,
    EN_PRESSURE,
    EN_QUALITY,
    EN_SETTING,
    EN_STATUS,
    FCV,
    LinkProperty,
    MISSING,
    NodeProperty,
    OPEN,
    PBV,
    PIPE,
    PRV,
    PSV,
    PUMP,
)
from extensions.epanet.model import (
    ELEV,
    FLOW,
    HEAD,
    LINKQUAL,
    PRESSURE,
    Project,
    QUALITY,
)
from extensions.epanet.quality import avgqual


def node_value(pr: Project, index: Int, prop: NodeProperty) raises -> Float64:
    """Return a result of a node.

    Args:
        pr: The project.
        index: The node index, from 1.
        prop: The property: demand, head, pressure or quality.

    Returns:
        The value in the units of the input file.

    Raises:
        Error: If the index or the property is not valid.
    """
    if not prop.is_valid():
        raise Error("EPANET error 251: invalid parameter code")
    if prop == EN_DEMAND:
        return mul(pr.hyd.node_demand[index], pr.ucf[FLOW])
    if prop == EN_HEAD:
        return mul(pr.hyd.node_head[index], pr.ucf[HEAD])
    if prop == EN_PRESSURE:
        return mul(
            pr.hyd.node_head[index] - pr.net.node[index].el, pr.ucf[PRESSURE]
        )
    return mul(pr.qual.node_qual[index], pr.ucf[QUALITY])


def link_value(pr: Project, index: Int, prop: LinkProperty) raises -> Float64:
    """Return a result of a link.

    Args:
        pr: The project.
        index: The link index, from 1.
        prop: The property: flow, status, setting, energy or quality.

    Returns:
        The value in the units of the input file. A status is 0 for
        closed, 1 for open and 2 for an active valve.

    Raises:
        Error: If the index or the property is not valid.
    """
    if not prop.is_valid():
        raise Error("EPANET error 251: invalid parameter code")
    ref link = pr.net.link[index]
    var status = pr.hyd.link_status[index]
    if prop == EN_FLOW:
        if status.value <= CLOSED.value:
            return 0.0
        return mul(pr.hyd.link_flow[index], pr.ucf[FLOW])
    if prop == EN_STATUS:
        var v = 0.0 if status.value <= CLOSED.value else 1.0
        if link.type.value > PUMP.value and status.value > OPEN.value:
            v = 2.0
        return v
    if prop == EN_SETTING:
        if link.type == PIPE or link.type == CVPIPE:
            if pr.hyd.formflag == DW:
                return mul(link.kc, mul(1000.0, pr.ucf[ELEV]))
            return link.kc
        var v = pr.hyd.link_setting[index]
        if v == MISSING:
            v = 0.0
        if link.type == PRV or link.type == PSV or link.type == PBV:
            v *= pr.ucf[PRESSURE]
        elif link.type == FCV:
            v *= pr.ucf[FLOW]
        return v
    if prop == EN_ENERGY:
        var kw = 0.0
        var eff = 0.0
        getenergy(pr, index, kw, eff)
        return kw
    return mul(avgqual(pr, index), pr.ucf[LINKQUAL])
