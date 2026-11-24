# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from project.c of OWA EPANET 2.3.6. Copyright (c) 2023 the EPANET
# contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The lookups of a network: an object by name, a pump by link, and so on.

A name is case sensitive, as in EPANET. A lookup that finds nothing
gives 0, except `findpattern`, which gives -1 because pattern 0 is the
pattern of constant 1.
"""

from extensions.epanet.cmath import mul
from extensions.epanet.kinds import FCV, LinkType, PRV, PSV, TINY
from extensions.epanet.model import Demand, Network, Node


def findnode(net: Network, id: String) -> Int:
    """Return the index of the node with a name.

    Args:
        net: The network.
        id: The name.

    Returns:
        The node index, or 0 if there is no such node.
    """
    return net.node_index.get(id, 0)


def findlink(net: Network, id: String) -> Int:
    """Return the index of the link with a name.

    Args:
        net: The network.
        id: The name.

    Returns:
        The link index, or 0 if there is no such link.
    """
    return net.link_index.get(id, 0)


def findpump(net: Network, index: Int) -> Int:
    """Return the pump of a link.

    Args:
        net: The network.
        index: The link index of a pump.

    Returns:
        The pump index.
    """
    for i in range(1, net.npumps):
        if net.pump[i].link == index:
            return i
    return net.npumps


def findvalve(net: Network, index: Int) -> Int:
    """Return the valve of a link.

    Args:
        net: The network.
        index: The link index of a valve.

    Returns:
        The valve index.
    """
    for i in range(1, net.nvalves):
        if net.valve[i].link == index:
            return i
    return net.nvalves


def findpattern(net: Network, id: String) -> Int:
    """Return the index of the pattern with a name.

    Args:
        net: The network.
        id: The name. The empty name is pattern 0.

    Returns:
        The pattern index, or -1 if there is no such pattern.
    """
    for i in range(net.npats + 1):  # pragma: no branch
        if net.pattern[i].id == id:
            return i
    return -1


def findcurve(net: Network, id: String) -> Int:
    """Return the index of the curve with a name.

    Args:
        net: The network.
        id: The name.

    Returns:
        The curve index, or 0 if there is no such curve.
    """
    for i in range(1, net.ncurves + 1):
        if net.curve[i].id == id:
            return i
    return 0


def adddemand(mut node: Node, dbase: Float64, dpat: Int, dname: String):
    """Append a demand category to a node.

    Args:
        node: The node.
        dbase: The base demand.
        dpat: The pattern index.
        dname: The name of the category, or empty.
    """
    node.demands.append(Demand(dbase, dpat, dname))


def valvecheck(net: Network, type: LinkType, j1: Int, j2: Int) -> Int:
    """Check that a new valve does not make an illegal connection.

    Args:
        net: The network.
        type: The type of the valve.
        j1: The start node.
        j2: The end node.

    Returns:
        0, or error 219 for a valve at a tank or a reservoir, or 220 for
        a valve that conflicts with another valve.
    """
    if type == PRV or type == PSV or type == FCV:
        if j1 > net.njuncs or j2 > net.njuncs:
            return 219
        for k in range(1, net.nvalves + 1):
            ref link = net.link[net.valve[k].link]
            var vj1 = link.n1
            var vj2 = link.n2
            var vtype = link.type
            if vtype == PRV and type == PRV:
                if vj2 == j2 or vj2 == j1 or vj1 == j2:
                    return 220
            if vtype == PSV and type == PSV:
                if vj1 == j1 or vj1 == j2 or vj2 == j1:
                    return 220
            if vtype == PSV and type == PRV and vj1 == j2:
                return 220
            if vtype == PRV and type == PSV and vj2 == j1:
                return 220
            if vtype == FCV and type == PSV and vj2 == j1:
                return 220
            if vtype == FCV and type == PRV and vj1 == j2:
                return 220
            if vtype == PSV and type == FCV and vj1 == j2:
                return 220
            if vtype == PRV and type == FCV and vj2 == j1:
                return 220
    return 0


def interp(x: List[Float64], y: List[Float64], xx: Float64) -> Float64:
    """Interpolate a curve linearly. Beyond the ends, keep the end value.

    Args:
        x: The x values, increasing. There is at least one.
        y: The y values.
        xx: The x at which to interpolate.

    Returns:
        The interpolated y.
    """
    var m = len(x) - 1
    if xx <= x[0]:
        return y[0]
    for k in range(1, m + 1):
        if x[k] >= xx:
            var dx = x[k] - x[k - 1]
            var dy = y[k] - y[k - 1]
            if abs(dx) < TINY:
                return y[k]
            return y[k] - mul(x[k] - xx, dy) / dx
    return y[m]
