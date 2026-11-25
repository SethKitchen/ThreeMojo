# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from GwfStorageUtils.f90 of MODFLOW 6.9.0.dev0, commit 59d89e9f,
# which is in the public domain (CC0). See THIRD-PARTY-NOTICES.md.

"""The terms of specific storage and of specific yield in a cell."""

from extensions.groundwater.cmath import mul
from extensions.groundwater.constants import DHALF, DONE, DZERO


@fieldwise_init
struct StorageTerms(ImplicitlyCopyable, Movable):
    """The matrix term, the right side and the rate of one storage kind."""

    var aterm: Float64
    """The term on the diagonal of the matrix."""
    var rhsterm: Float64
    """The term on the right side."""
    var rate: Float64
    """The flow out of storage."""


def ss_terms(
    iconvert: Int,
    iorig_ss: Int,
    iconf_ss: Int,
    top: Float64,
    bot: Float64,
    rho1: Float64,
    rho1old: Float64,
    snnew: Float64,
    snold: Float64,
    hnew: Float64,
    hold: Float64,
) -> StorageTerms:
    """Return the terms of specific storage.

    Args:
        iconvert: 1 if the cell can convert.
        iorig_ss: 1 for the storage formulation of MODFLOW 2005.
        iconf_ss: 1 to keep the confined storage when the cell is not full.
        top: The top of the cell.
        bot: The bottom of the cell.
        rho1: The storage capacity over the time step, now.
        rho1old: The storage capacity over the time step, before.
        snnew: The saturation now.
        snold: The saturation at the start of the step.
        hnew: The head now.
        hold: The head at the start of the step.

    Returns:
        The terms.
    """
    var aterm = -mul(rho1, snnew)
    var rhsterm = DZERO
    if iconvert != 0:
        if iorig_ss == 0:
            if iconf_ss == 0:
                var tthk = top - bot
                var zold = bot + mul(mul(DHALF, tthk), snold)
                var znew = bot + mul(mul(DHALF, tthk), snnew)
                rhsterm = mul(mul(-rho1old, snold), hold - zold) - mul(
                    mul(rho1, snnew), znew
                )
            else:
                if snold == DONE:
                    rhsterm = rhsterm - mul(rho1old, hold - top)
                if snnew == DONE:
                    rhsterm = rhsterm - mul(rho1, top)
                else:
                    aterm = DZERO
        else:
            rhsterm = mul(mul(-rho1old, snold), hold)
    else:
        rhsterm = mul(mul(-rho1old, snold), hold)
    return StorageTerms(aterm, rhsterm, mul(aterm, hnew) - rhsterm)


def sy_terms(
    top: Float64,
    bot: Float64,
    rho2: Float64,
    rho2old: Float64,
    snnew: Float64,
    snold: Float64,
) -> StorageTerms:
    """Return the terms of specific yield.

    Args:
        top: The top of the cell.
        bot: The bottom of the cell.
        rho2: The specific yield capacity over the time step, now.
        rho2old: The specific yield capacity over the time step, before.
        snnew: The saturation now.
        snold: The saturation at the start of the step.

    Returns:
        The terms.
    """
    var aterm = DZERO
    var rhsterm: Float64
    var tthk = top - bot
    if snnew < DONE:
        if snnew > DZERO:
            aterm = -rho2
            rhsterm = mul(mul(-rho2old, tthk), snold) - mul(rho2, bot)
        else:
            rhsterm = mul(tthk, DZERO - mul(rho2old, snold))
    else:
        rhsterm = mul(tthk, mul(rho2, snnew) - mul(rho2old, snold))
    var rate = mul(mul(rho2old, tthk), snold) - mul(mul(rho2, tthk), snnew)
    return StorageTerms(aterm, rhsterm, rate)


def ss_capacity(
    istor_coef: Int, top: Float64, bot: Float64, area: Float64, ss: Float64
) -> Float64:
    """Return the specific storage capacity of a cell.

    Args:
        istor_coef: 1 if `ss` is a storage coefficient, not a specific
            storage.
        top: The top of the cell.
        bot: The bottom of the cell.
        area: The area of the cell.
        ss: The specific storage, or the storage coefficient.

    Returns:
        The capacity, in volume per unit of head.
    """
    var thick = DONE
    if istor_coef == 0:
        thick = top - bot
    return mul(mul(ss, thick), area)


def sy_capacity(area: Float64, sy: Float64) -> Float64:
    """Return the specific yield capacity of a cell.

    Args:
        area: The area of the cell.
        sy: The specific yield.

    Returns:
        The capacity, in volume per unit of head.
    """
    return mul(sy, area)
