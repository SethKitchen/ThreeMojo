# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Perfusion from dynamic contrast-enhanced MRI, by the Tofts models.

A DCE-MRI scan follows a contrast agent from the blood into a tissue. The
Tofts model gives the tissue concentration `Ct` from the plasma
concentration `Cp`:

    Ct(t) = Ktrans * integral of Cp(s) exp(-kep (t - s)) ds + vp Cp(t)

`Ktrans` is the transfer constant from the plasma to the tissue, `ve` is
the part of the tissue outside the cells and the vessels, and
`kep = Ktrans / ve`. The extended model adds `vp`, the part of the tissue
that is plasma. The standard model has no `vp`. Tumors often have a high
`Ktrans`, so oncology research maps it.

- `tofts_curve` gives `Ct`. The integral starts at the first time, and
  it is exact for a plasma curve that is linear between its samples, as
  in Flouri and others (2016).
- `fit_tofts` fits `Ktrans`, `ve` and `vp` to a tissue curve by least
  squares. For each `kep`, `Ktrans` and `vp` are the least squares of a
  linear problem, with neither below 0. The fit searches `kep` on a log
  grid of 81 values from 0.001 to 20 a minute, then by 80 steps of the
  golden section around the best.
- `tofts_maps` fits each voxel of a label in a series of volumes.
- `parker_aif` gives the population arterial input function of Parker
  and others (2006), in mM of blood. Divide it by `1 - Hct` for plasma.

Concentrations are plain values in one unit, such as mM. The model is
linear in concentration, so the unit cancels.
"""

from extensions.imaging.ids import (
    BACKGROUND,
    EXTENDED_TOFTS,
    LabelId,
    ToftsModel,
    require_label,
    require_tofts_model,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, require_same_grid
from std.math import exp, expm1, isfinite, log, max, min, pi, sqrt
from units.quantity import Unit
from units.si import Duration64, Frequency64
from extensions.numerics.elementary import precise_exp

# The minute, and one each minute, for 64-bit times and rates.
comptime MINUTE64 = Unit[0, 0, 1, 0, 0, DType.float64](60.0, "min")
comptime PER_MINUTE64 = Unit[0, 0, -1, 0, 0, DType.float64](1.0 / 60.0, "1/min")
# Below this `kep` times a step, the convolution takes a series.
comptime SMALL = 1.0e-3
# The search of `kep`, a minute.
comptime LEAST_KEP = 0.001
comptime MOST_KEP = 20.0
comptime GRID = 81
comptime GOLDEN_STEPS = 80


def _minutes(times: List[Duration64], least: Int) raises -> List[Float64]:
    """Return times in minutes, checked to rise."""
    if len(times) < least:
        raise Error("A DCE curve needs " + String(least) + " times or more")
    var out = List[Float64]()
    for t in times:  # pragma: no branch
        var m = t.to(MINUTE64)
        if not isfinite(m):
            raise Error("A DCE time must be finite")
        if len(out) > 0 and not (m > out[len(out) - 1]):
            raise Error("DCE times must rise")
        out.append(m)
    return out^


def _require_curve(values: List[Float64], count: Int, name: String) raises:
    """Refuse a curve of another length, or with a value that is not
    finite."""
    if len(values) != count:
        raise Error("A " + name + " curve needs one value for each time")
    for v in values:  # pragma: no branch
        if not isfinite(v):
            raise Error("A " + name + " curve needs finite values")


def _convolve(
    t: List[Float64], f: List[Float64], kep: Float64
) -> List[Float64]:
    """Return the integral of `f(s) kep exp(-kep (t - s))` from the first
    time, for `f` linear between its samples."""
    var g = List[Float64](length=len(t), fill=0.0)
    for i in range(len(t) - 1):  # pragma: no branch
        var x = kep * (t[i + 1] - t[i])
        var e0 = -expm1(-x)
        # x - (1 - exp(-x)), which loses its digits for a small x.
        var e1: Float64
        if x < SMALL:
            e1 = x * x * (0.5 - x * (1.0 / 6.0 - x * (1.0 / 24.0 - x / 120.0)))
        else:
            e1 = x - e0
        g[i + 1] = (1.0 - e0) * g[i] + f[i] * e0 + (f[i + 1] - f[i]) / x * e1
    return g^


def tofts_curve(
    times: List[Duration64],
    plasma: List[Float64],
    ktrans: Frequency64,
    ve: Float64,
    vp: Float64,
) raises -> List[Float64]:
    """Return the tissue concentration of the Tofts model.

    Args:
        times: The times of the samples, two or more, rising.
        plasma: The plasma concentration at each time.
        ktrans: The transfer constant, 0 or more.
        ve: The part of the tissue outside the cells and vessels, above 0
            and at most 1.
        vp: The part of the tissue that is plasma, from 0 to 1. 0 for the
            standard model.

    Returns:
        The tissue concentration at each time, in the plasma's unit.

    Raises:
        Error: If the times do not rise, a curve does not fit the times,
            or a parameter is out of range.
    """
    var t = _minutes(times, 2)
    _require_curve(plasma, len(t), "plasma")
    var k = ktrans.to(PER_MINUTE64)
    if not (k >= 0) or not isfinite(k):
        raise Error("A Ktrans must be 0 or more, and finite")
    if not (ve > 0) or ve > 1:
        raise Error("A ve must be above 0 and at most 1")
    if not (vp >= 0) or vp > 1:
        raise Error("A vp must be from 0 to 1")
    var out = List[Float64]()
    if k == 0:
        for p in plasma:  # pragma: no branch
            out.append(vp * p)
        return out^
    var g = _convolve(t, plasma, k / ve)
    for i in range(len(t)):  # pragma: no branch
        out.append(ve * g[i] + vp * plasma[i])
    return out^


struct ToftsFit(Copyable, Movable):
    """The parameters of a Tofts model fitted to a tissue curve."""

    var ktrans: Frequency64
    """The transfer constant. 0 when the tissue takes up nothing."""
    var kep: Frequency64
    """`Ktrans / ve`, the rate back to the plasma."""
    var ve: Float64
    """The part outside the cells and vessels. 0 when `ktrans` is 0. A
    value above 1 means that the model does not fit the tissue."""
    var vp: Float64
    """The part that is plasma. 0 in the standard model."""
    var rms: Float64
    """The root mean square of the misfit, in the curves' unit."""

    def __init__(
        out self,
        ktrans: Frequency64,
        kep: Frequency64,
        ve: Float64,
        vp: Float64,
        rms: Float64,
    ):
        """Create a fit.

        Args:
            ktrans: The transfer constant.
            kep: The rate back to the plasma.
            ve: The part outside the cells and vessels.
            vp: The part that is plasma.
            rms: The root mean square of the misfit.
        """
        self.ktrans = ktrans
        self.kep = kep
        self.ve = ve
        self.vp = vp
        self.rms = rms


def _misfit(
    tissue: List[Float64],
    c1: List[Float64],
    plasma: List[Float64],
    k: Float64,
    v: Float64,
) -> Float64:
    """Return the sum of the squared misfits of `k c1 + v plasma`."""
    var sum = 0.0
    for i in range(len(tissue)):  # pragma: no branch
        var d = tissue[i] - k * c1[i] - v * plasma[i]
        sum += d * d
    return sum


def _linear(
    tissue: List[Float64],
    c1: List[Float64],
    plasma: List[Float64],
    extended: Bool,
) -> Tuple[Float64, Float64, Float64]:
    """Return `Ktrans`, `vp` and the misfit of the least squares with
    neither below 0, for one `kep`."""
    var a11 = 0.0
    var a12 = 0.0
    var a22 = 0.0
    var b1 = 0.0
    var b2 = 0.0
    for i in range(len(tissue)):  # pragma: no branch
        a11 += c1[i] * c1[i]
        a12 += c1[i] * plasma[i]
        a22 += plasma[i] * plasma[i]
        b1 += c1[i] * tissue[i]
        b2 += plasma[i] * tissue[i]
    # Ktrans alone; the plasma has a value above 0, so a11 is above 0.
    var k = max(0.0, b1 / a11)
    var v = 0.0
    var best = _misfit(tissue, c1, plasma, k, 0.0)
    if not extended:
        return (k, v, best)
    var only = max(0.0, b2 / a22)
    var alone = _misfit(tissue, c1, plasma, 0.0, only)
    if alone < best:
        k = 0.0
        v = only
        best = alone
    var det = a11 * a22 - a12 * a12
    if det > 0:
        var both_k = (b1 * a22 - b2 * a12) / det
        var both_v = (b2 * a11 - b1 * a12) / det
        if both_k >= 0 and both_v >= 0:
            var both = _misfit(tissue, c1, plasma, both_k, both_v)
            if both < best:
                k = both_k
                v = both_v
                best = both
    return (k, v, best)


def _at(
    t: List[Float64],
    plasma: List[Float64],
    tissue: List[Float64],
    u: Float64,
    extended: Bool,
) -> Tuple[Float64, Float64, Float64]:
    """Return the least squares at `kep = exp(u)` a minute."""
    var kep = precise_exp(u)
    var g = _convolve(t, plasma, kep)
    # The integral of Cp exp(-kep (t - s)), which Ktrans multiplies.
    var c1 = List[Float64]()
    for x in g:  # pragma: no branch
        c1.append(x / kep)
    return _linear(tissue, c1, plasma, extended)


def fit_tofts(
    times: List[Duration64],
    plasma: List[Float64],
    tissue: List[Float64],
    model: ToftsModel,
) raises -> ToftsFit:
    """Fit a Tofts model to a tissue curve by least squares.

    Args:
        times: The times of the samples, three or more, rising.
        plasma: The plasma concentration at each time, 0 or more, with
            one value above 0.
        tissue: The tissue concentration at each time.
        model: `STANDARD_TOFTS` or `EXTENDED_TOFTS`.

    Returns:
        The parameters with the least misfit.

    Raises:
        Error: If the model is not valid, the times do not rise, a curve
            does not fit the times, or the plasma has a value below 0 or
            none above 0.
    """
    require_tofts_model(model)
    var t = _minutes(times, 3)
    _require_curve(plasma, len(t), "plasma")
    _require_curve(tissue, len(t), "tissue")
    var top = 0.0
    for p in plasma:  # pragma: no branch
        if p < 0:
            raise Error("A plasma curve needs values of 0 or more")
        top = max(top, p)
    if not (top > 0):
        raise Error("A plasma curve needs a value above 0")
    var extended = model == EXTENDED_TOFTS
    var low = log(LEAST_KEP)
    var step = (log(MOST_KEP) - low) / Float64(GRID - 1)
    var best = 0
    var least = _at(t, plasma, tissue, low, extended)[2]
    for n in range(1, GRID):  # pragma: no branch
        var cost = _at(t, plasma, tissue, low + step * Float64(n), extended)[2]
        if cost < least:
            least = cost
            best = n
    # The golden section between the grid's neighbors of the best.
    var a = low + step * Float64(max(best - 1, 0))
    var b = low + step * Float64(min(best + 1, GRID - 1))
    var r = (sqrt(5.0) - 1.0) / 2.0
    var x1 = b - r * (b - a)
    var x2 = a + r * (b - a)
    var f1 = _at(t, plasma, tissue, x1, extended)[2]
    var f2 = _at(t, plasma, tissue, x2, extended)[2]
    for _ in range(GOLDEN_STEPS):  # pragma: no branch
        if f1 < f2:
            b = x2
            x2 = x1
            f2 = f1
            x1 = b - r * (b - a)
            f1 = _at(t, plasma, tissue, x1, extended)[2]
        else:
            a = x1
            x1 = x2
            f1 = f2
            x2 = a + r * (b - a)
            f2 = _at(t, plasma, tissue, x2, extended)[2]
    var u = 0.5 * (a + b)
    var found = _at(t, plasma, tissue, u, extended)
    var kep = precise_exp(u)
    var k = found[0]
    var ve = k / kep
    var rate = kep
    if not (k > 0):
        ve = 0.0
        rate = 0.0
    return ToftsFit(
        Frequency64(k, PER_MINUTE64),
        Frequency64(rate, PER_MINUTE64),
        ve,
        found[1],
        sqrt(found[2] / Float64(len(t))),
    )


struct ToftsMaps(Copyable, Movable):
    """The fitted parameters of each voxel of a label."""

    var ktrans: ImageVolume
    """Ktrans, a minute. 0 outside the label."""
    var ve: ImageVolume
    """The part outside the cells and vessels, ve. 0 outside the label."""
    var vp: ImageVolume
    """The part that is plasma, vp. 0 outside the label and in the standard
    model."""
    var rms: ImageVolume
    """The root mean square of each voxel's misfit."""

    def __init__(out self, grid: ImageVolume) raises:
        """Create maps of zeros on a grid.

        Args:
            grid: The volume whose grid and placement the maps take.

        Raises:
            Error: If the grid cannot be made.
        """
        var zero = grid.copy()
        for v in range(zero.count()):  # pragma: no branch
            zero.values[v] = 0
        self.ktrans = zero.copy()
        self.ve = zero.copy()
        self.vp = zero.copy()
        self.rms = zero^


def tofts_maps(
    series: List[ImageVolume],
    times: List[Duration64],
    plasma: List[Float64],
    map: LabelMap,
    label: LabelId,
    model: ToftsModel,
) raises -> ToftsMaps:
    """Fit a Tofts model at each voxel of a label.

    Args:
        series: The tissue concentration at each time, one volume each,
            on one grid.
        times: The times of the volumes.
        plasma: The plasma concentration at each time.
        map: The label map, on the grid of the volumes.
        label: The label. Not the background.
        model: `STANDARD_TOFTS` or `EXTENDED_TOFTS`.

    Returns:
        Maps of Ktrans a minute, ve, vp and the misfit.

    Raises:
        Error: If the label is not valid or is the background, a volume
            is on another grid, there is not one volume for each time, or
            `fit_tofts` refuses a voxel.
    """
    require_label(label)
    if label == BACKGROUND:
        raise Error("A DCE map needs a label, not the background")
    if len(series) != len(times):
        raise Error("A DCE series needs one volume for each time")
    for volume in series:  # pragma: no branch
        require_same_grid(map, volume)
    var out = ToftsMaps(series[0])
    var mark = UInt8(label.value)
    for at in range(map.count()):  # pragma: no branch
        if map.labels[at] != mark:
            continue
        var tissue = List[Float64]()
        for volume in series:  # pragma: no branch
            tissue.append(Float64(volume.values[at]))
        var fit = fit_tofts(times, plasma, tissue, model)
        out.ktrans.values[at] = Float32(fit.ktrans.to(PER_MINUTE64))
        out.ve.values[at] = Float32(fit.ve)
        out.vp.values[at] = Float32(fit.vp)
        out.rms.values[at] = Float32(fit.rms)
    return out^


def parker_aif(times: List[Duration64]) raises -> List[Float64]:
    """Return the population arterial input function of Parker and others.

    Two Gaussians and a falling sigmoid, with the parameters of Parker and
    others (2006): A of 0.809 and 0.330 mM min, T of 0.17046 and 0.365
    min, sigma of 0.0563 and 0.132 min, alpha of 1.050 mM, beta of 0.1685
    a minute, s of 38.078 a minute and tau of 0.483 min.

    Args:
        times: The times from the arrival of the bolus.

    Returns:
        The blood concentration at each time, in mM.

    Raises:
        Error: If a time is not finite.
    """
    var root = sqrt(2.0 * pi)
    var out = List[Float64]()
    for time in times:
        var t = time.to(MINUTE64)
        if not isfinite(t):
            raise Error("A DCE time must be finite")
        var d1 = (t - 0.17046) / 0.0563
        var d2 = (t - 0.365) / 0.132
        out.append(
            0.809 / (0.0563 * root) * precise_exp(-0.5 * d1 * d1)
            + 0.330 / (0.132 * root) * precise_exp(-0.5 * d2 * d2)
            + 1.050
            * precise_exp(-0.1685 * t)
            / (1.0 + precise_exp(-38.078 * (t - 0.483)))
        )
    return out^
