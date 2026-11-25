# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from SmoothingFunctions.f90 of MODFLOW 6.9.0.dev0, commit
# 59d89e9f, which is in the public domain (CC0). See THIRD-PARTY-NOTICES.md.

"""The saturation of a cell, smoothed near its top and its bottom.

The Newton-Raphson formulation needs a saturation with a continuous
derivative. `squadratic_saturation` is linear between the bottom and the
top of a cell, with a quadratic piece of width `eps` at each end.
"""

from extensions.groundwater.cmath import mul
from extensions.groundwater.constants import DEM6, DHALF, DONE, DZERO


def squadratic_saturation(
    top: Float64, bot: Float64, x: Float64, eps: Float64 = DEM6
) -> Float64:
    """Return the smoothed saturation of a cell at a head.

    Args:
        top: The top of the cell.
        bot: The bottom of the cell.
        x: The head.
        eps: The width of each quadratic piece, as a fraction of the
            thickness.

    Returns:
        The saturation, from 0 to 1.
    """
    var b = top - bot
    if b > DZERO:
        var br: Float64
        if x < bot:
            br = DZERO
        elif x > top:
            br = DONE
        else:
            br = (x - bot) / b
        var av = DONE / (DONE - eps)
        var bri = DONE - br
        if br < eps:
            return mul(mul(av, DHALF), mul(br, br)) / eps
        elif br < (DONE - eps):
            return mul(av, br) + mul(DHALF, DONE - av)
        elif br < DONE:
            return DONE - (mul(mul(av, DHALF), mul(bri, bri)) / eps)
        return DONE
    if x < bot:
        return DZERO
    return DONE


def squadratic_saturation_derivative(
    top: Float64, bot: Float64, x: Float64, eps: Float64 = DEM6
) -> Float64:
    """Return the derivative of `squadratic_saturation` with the head.

    Args:
        top: The top of the cell.
        bot: The bottom of the cell.
        x: The head.
        eps: The width of each quadratic piece, as a fraction of the
            thickness.

    Returns:
        The derivative, per unit of head.
    """
    var b = top - bot
    var br: Float64
    if x < bot:
        br = DZERO
    elif x > top:
        br = DONE
    else:
        br = (x - bot) / b
    var av = DONE / (DONE - eps)
    var bri = DONE - br
    var y: Float64
    if br < eps:
        y = mul(av, br) / eps
    elif br < (DONE - eps):
        y = av
    elif br < DONE:
        y = mul(av, bri) / eps
    else:
        y = DZERO
    return y / b
