# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fit NASA seven-coefficient polynomials to tabulated data.

Some data comes only as tables of heat capacity, enthalpy and entropy, as
the JANAF tables give them. `fit_nasa7` turns such a table into a
`ThermoFit` with two segments that meet at a common temperature:

1. The heat capacity of each segment is a quartic in T. The two quartics
   are fitted together by least squares, with their values equal at the
   common temperature. The fit works in T / 1000 to keep the equations
   well scaled.
2. The low segment's enthalpy and entropy constants are the mean offsets
   of the table's values from the integrated quartic.
3. The high segment's constants make the enthalpy and the entropy
   continuous at the common temperature.

Each segment needs at least five points. The fit is as good as the table
and the quartic: check the residuals the result gives.
"""

from std.math import isfinite, log
from extensions.chemistry.quantities import (
    GAS_CONSTANT,
    MolarEnergy64,
    MolarEntropy64,
)
from extensions.chemistry.thermo import ThermoFit, nasa7
from extensions.numerics.dense import DenseMatrix, solve
from units.temperature import Temperature64

# The fit's temperature scale.
comptime _SCALE = 1000.0


@fieldwise_init
struct ThermoPoint(ImplicitlyCopyable):
    """One row of a thermochemical table."""

    var temperature: Temperature64
    var heat_capacity: MolarEntropy64
    # The enthalpy on the formation scale: the enthalpy of formation at
    # 298.15 K plus H(T) - H(298.15).
    var enthalpy: MolarEnergy64
    var entropy: MolarEntropy64


def _poly_h(a: List[Float64], k: Int, t: Float64) -> Float64:
    """Return H/R of five coefficients from index k, without the constant."""
    return t * (
        a[k]
        + t
        * (
            a[k + 1] / 2
            + t * (a[k + 2] / 3 + t * (a[k + 3] / 4 + t * a[k + 4] / 5))
        )
    )


def _poly_s(a: List[Float64], k: Int, t: Float64) -> Float64:
    """Return S/R of five coefficients from index k, without the constant."""
    return a[k] * log(t) + t * (
        a[k + 1] + t * (a[k + 2] / 2 + t * (a[k + 3] / 3 + t * a[k + 4] / 4))
    )


def fit_nasa7(
    points: List[ThermoPoint],
    low: Temperature64,
    common: Temperature64,
    high: Temperature64,
) raises -> ThermoFit:
    """Return NASA-7 polynomials fitted to a table.

    Args:
        points: The table. Points at the common temperature count in the
            low segment.
        low: The lowest temperature of the fit.
        common: Where the two segments meet.
        high: The highest temperature of the fit.

    Returns:
        The fit, with segments from `low` to `common` and on to `high`.

    Raises:
        Error: If the temperatures do not ascend, a point is not finite or
            outside the range, or a segment has fewer than five points.
    """
    if not (
        low.is_valid()
        and low.kelvin > 0
        and low.kelvin < common.kelvin
        and common.kelvin < high.kelvin
        and high.is_valid()
    ):
        raise Error("A fit's temperatures must be positive and ascend")
    var r = GAS_CONSTANT.value
    var counts: List[Int] = [0, 0]
    for p in points:
        var t = p.temperature.kelvin
        var values: List[Float64] = [
            p.heat_capacity.value,
            p.enthalpy.value,
            p.entropy.value,
        ]
        for v in values:  # pragma: no branch
            if not isfinite(v):
                raise Error("A table value must be finite")
        if not (t >= low.kelvin and t <= high.kelvin):
            raise Error("A table point lies outside the fit's range")
        if t <= common.kelvin:
            counts[0] += 1
        else:
            counts[1] += 1
    if counts[0] < 5 or counts[1] < 5:
        raise Error("Each segment of a fit needs five points")
    # Least squares for ten scaled quartic coefficients, with one Lagrange
    # multiplier for cp's continuity at the common temperature.
    var m = DenseMatrix(11, 11)
    var rhs = List[Float64]()
    for _ in range(11):  # pragma: no branch
        rhs.append(0)
    for p in points:  # pragma: no branch
        var tau = p.temperature.kelvin / _SCALE
        var base = 0
        if p.temperature.kelvin > common.kelvin:
            base = 5
        var powers = List[Float64]()
        var x = Float64(1)
        for _ in range(5):  # pragma: no branch
            powers.append(x)
            x *= tau
        var y = p.heat_capacity.value / r
        for i in range(5):  # pragma: no branch
            rhs[base + i] += powers[i] * y
            for j in range(5):  # pragma: no branch
                m.add(base + i, base + j, powers[i] * powers[j])
    var tc = common.kelvin / _SCALE
    var x = Float64(1)
    for i in range(5):  # pragma: no branch
        m.set(i, 10, x)
        m.set(10, i, x)
        m.set(5 + i, 10, -x)
        m.set(10, 5 + i, -x)
        x *= tc
    var c = solve(m, rhs)
    # Unscale: a_k = c_k / 1000^k.
    var a = List[Float64]()
    for s in range(2):  # pragma: no branch
        var scale = Float64(1)
        for i in range(5):  # pragma: no branch
            a.append(c[5 * s + i] / scale)
            scale *= _SCALE
    # The low segment's constants: mean offsets of H/R and S/R.
    var h_sum = Float64(0)
    var s_sum = Float64(0)
    for p in points:  # pragma: no branch
        var t = p.temperature.kelvin
        if t <= common.kelvin:
            h_sum += p.enthalpy.value / r - _poly_h(a, 0, t)
            s_sum += p.entropy.value / r - _poly_s(a, 0, t)
    var a6 = h_sum / Float64(counts[0])
    var a7 = s_sum / Float64(counts[0])
    # The high segment's constants: continuous H and S.
    var t0 = common.kelvin
    var b6 = _poly_h(a, 0, t0) + a6 - _poly_h(a, 5, t0)
    var b7 = _poly_s(a, 0, t0) + a7 - _poly_s(a, 5, t0)
    var coefficients: List[Float64] = [
        a[0],
        a[1],
        a[2],
        a[3],
        a[4],
        a6,
        a7,
        a[5],
        a[6],
        a[7],
        a[8],
        a[9],
        b6,
        b7,
    ]
    return nasa7([low.kelvin, common.kelvin, high.kelvin], coefficients^)
