# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from GwfConductanceUtils.f90 of MODFLOW 6.9.0.dev0, commit
# 59d89e9f, which is in the public domain (CC0). See THIRD-PARTY-NOTICES.md.

"""The conductance between two cells of a groundwater flow model.

`hcond` gives the conductance of a horizontal connection and `vcond` of
a vertical one. `condmean` averages the transmissivities of two cells by
one of four means.
"""

from extensions.groundwater.cmath import clog, mul
from extensions.groundwater.constants import (
    DHALF,
    DLNHIGH,
    DLNLOW,
    DONE,
    DZERO,
)

# The kinds of the mean of `condmean`.
comptime CCOND_HMEAN = 0
comptime CCOND_LMEAN = 1
comptime CCOND_AMTLMK = 2
comptime CCOND_AMTHMK = 3


def hcond(
    ibdn: Int,
    ibdm: Int,
    ictn: Int,
    ictm: Int,
    iupstream: Int,
    icellavg: Int,
    condsat: Float64,
    hn: Float64,
    hm: Float64,
    satn: Float64,
    satm: Float64,
    hkn: Float64,
    hkm: Float64,
    topn: Float64,
    topm: Float64,
    botn: Float64,
    botm: Float64,
    cln: Float64,
    clm: Float64,
    fawidth: Float64,
) -> Float64:
    """Return the conductance of a horizontal connection.

    Args:
        ibdn: The `ibound` of cell n.
        ibdm: The `ibound` of cell m.
        ictn: The cell type of n: 0 is confined.
        ictm: The cell type of m.
        iupstream: 1 to use the saturation of the upstream cell.
        icellavg: The kind of the mean.
        condsat: The saturated conductance.
        hn: The head of n.
        hm: The head of m.
        satn: The saturation of n.
        satm: The saturation of m.
        hkn: The conductivity of n.
        hkm: The conductivity of m.
        topn: The top of n.
        topm: The top of m.
        botn: The bottom of n.
        botm: The bottom of m.
        cln: The distance from the center of n to the face.
        clm: The distance from the center of m to the face.
        fawidth: The width of the face.

    Returns:
        The conductance.
    """
    if ibdn == 0 or ibdm == 0:
        return DZERO
    elif ictn == 0 and ictm == 0:
        return condsat
    elif iupstream == 1:
        var sat_up: Float64
        if hn > hm:
            sat_up = satn
        elif hm > hn:
            sat_up = satm
        else:
            sat_up = max(satn, satm)
        return mul(sat_up, condsat)
    # A DIS grid has no staggered connection, so the saturated thickness is
    # that of the whole cell.
    var thksatn = mul(satn, topn - botn)
    var thksatm = mul(satm, topm - botm)
    return condmean(hkn, hkm, thksatn, thksatm, cln, clm, fawidth, icellavg)


def vcond(
    ibdn: Int,
    ibdm: Int,
    ictn: Int,
    ictm: Int,
    inewton: Int,
    ivarcv: Int,
    idewatcv: Int,
    condsat: Float64,
    hn: Float64,
    hm: Float64,
    vkn: Float64,
    vkm: Float64,
    satn: Float64,
    satm: Float64,
    topn: Float64,
    topm: Float64,
    botn: Float64,
    botm: Float64,
    flowarea: Float64,
) -> Float64:
    """Return the conductance of a vertical connection.

    Args:
        ibdn: The `ibound` of cell n.
        ibdm: The `ibound` of cell m.
        ictn: The cell type of n: 0 is confined.
        ictm: The cell type of m.
        inewton: 1 for the Newton-Raphson formulation. It has no use here,
            as in MODFLOW 6.
        ivarcv: 1 if the vertical conductance varies with saturation.
        idewatcv: 1 if a dewatered cell conducts as if it were full.
        condsat: The saturated conductance.
        hn: The head of n.
        hm: The head of m.
        vkn: The vertical conductivity of n.
        vkm: The vertical conductivity of m.
        satn: The saturation of n.
        satm: The saturation of m.
        topn: The top of n.
        topm: The top of m.
        botn: The bottom of n.
        botm: The bottom of m.
        flowarea: The area of the face.

    Returns:
        The conductance.
    """
    _ = inewton
    if ibdn == 0 or ibdm == 0:
        return DZERO
    elif ivarcv == 0:
        return condsat
    elif ictn == 0 and ictm == 0:
        return condsat
    elif hn >= topn and hm >= topm:
        return condsat
    var satntmp = satn
    var satmtmp = satm
    if idewatcv == 0:
        if botn > botm:
            satmtmp = DONE
        else:
            satntmp = DONE
    else:
        if botn > botm:
            if satmtmp < DONE:
                satmtmp = DZERO
        else:
            if satntmp < DONE:
                satntmp = DZERO
    var bovk1 = mul(mul(satntmp, topn - botn), DHALF) / vkn
    var bovk2 = mul(mul(satmtmp, topm - botm), DHALF) / vkm
    var denom = bovk1 + bovk2
    if denom != DZERO:
        return flowarea / denom
    return DZERO


def condmean(
    k1: Float64,
    k2: Float64,
    thick1: Float64,
    thick2: Float64,
    cl1: Float64,
    cl2: Float64,
    width: Float64,
    iavgmeth: Int,
) -> Float64:
    """Return the conductance of two cells in series, by one mean.

    Args:
        k1: The conductivity of the first cell.
        k2: The conductivity of the second cell.
        thick1: The saturated thickness of the first cell.
        thick2: The saturated thickness of the second cell.
        cl1: The distance from the center of the first cell to the face.
        cl2: The distance from the center of the second cell to the face.
        width: The width of the face.
        iavgmeth: The kind of the mean.

    Returns:
        The conductance.
    """
    var t1 = mul(k1, thick1)
    var t2 = mul(k2, thick2)
    if iavgmeth == CCOND_HMEAN:
        if mul(t1, t2) > DZERO:
            return mul(mul(width, t1), t2) / (mul(t1, cl2) + mul(t2, cl1))
        return DZERO
    elif iavgmeth == CCOND_LMEAN:
        var tmean = DZERO
        if mul(t1, t2) > DZERO:
            tmean = logmean(t1, t2)
        return mul(tmean, width) / (cl1 + cl2)
    elif iavgmeth == CCOND_AMTLMK:
        var kmean = DZERO
        if mul(k1, k2) > DZERO:
            kmean = logmean(k1, k2)
        return mul(mul(mul(kmean, DHALF), thick1 + thick2), width) / (cl1 + cl2)
    var denom = mul(k1, cl2) + mul(k2, cl1)
    var kmean = DZERO
    if denom > DZERO:
        kmean = mul(k1, k2) / denom
    return mul(mul(mul(kmean, DHALF), thick1 + thick2), width)


def logmean(d1: Float64, d2: Float64) -> Float64:
    """Return the logarithmic mean of two positive numbers.

    Args:
        d1: The first number.
        d2: The second number.

    Returns:
        (d2 - d1) / ln(d2 / d1), or the arithmetic mean when the ratio
        is near 1.
    """
    var drat = d2 / d1
    if drat <= DLNLOW or drat >= DLNHIGH:
        return (d2 - d1) / clog(drat)
    return mul(DHALF, d1 + d2)
