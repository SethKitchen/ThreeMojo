# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Intravoxel incoherent motion (IVIM): diffusion and perfusion from one
diffusion MRI series.

At low b-values, the blood in the capillaries adds a fast decay to the
signal of the water in the tissue. Le Bihan and others (1988) model it:

    S(b) = S0 (f exp(-b D*) + (1 - f) exp(-b D))

D is the diffusion of the tissue, D* the pseudo-diffusion of the blood,
and f the perfusion fraction. Research on the liver, the kidney and tumors
maps them.

`fit_ivim(b_values, signals, split)` fits the model in segments:

1. D and the intercept come from the line of `ln S` on b, over the
   b-values at or above `split`, often 200 s/mm^2, where the blood's decay
   has died away.
2. f is 1 less the intercept over the signal at b = 0.
3. D* gives the least sum of squares of the model over the b-values below
   `split`, with D, f and S0 held. A golden-section search over `ln D*`
   from 3e-3 to 0.5 mm^2/s finds it.

`ivim_maps(series, b_values, split, threshold)` fits each voxel.
"""

from extensions.imaging.diffusion import (
    BValue64,
    Diffusivity64,
    SECOND_PER_SQUARE_MILLIMETER,
    SQUARE_MICROMETER_PER_SECOND,
    SQUARE_MILLIMETER_PER_SECOND,
)
from extensions.imaging.image_volume import ImageVolume
from std.math import exp, expm1, isfinite, log
from extensions.numerics.elementary import precise_exp

# The search of ln D* in mm^2/s, and its steps.
comptime _LEAST_LOG_STAR = -5.809142990314028
comptime _MOST_LOG_STAR = -0.6931471805599453
comptime _GOLDEN = 0.6180339887498949
comptime _SEARCH_STEPS = 120


struct IvimFit(Copyable, Movable):
    """The segmented IVIM fit of one set of signals."""

    var diffusion: Diffusivity64
    """D: the diffusion of the water in the tissue."""
    var pseudo_diffusion: Diffusivity64
    """D*: the pseudo-diffusion of the blood in the capillaries."""
    var fraction: Float64
    """The perfusion fraction f: the share of the signal from the blood.
    Below 0 when noise puts
    the intercept above the signal at b = 0."""
    var s0: Float64
    """The signal at b = 0."""

    def __init__(
        out self,
        diffusion: Diffusivity64,
        pseudo_diffusion: Diffusivity64,
        fraction: Float64,
        s0: Float64,
    ):
        """Create a fit.

        Args:
            diffusion: D.
            pseudo_diffusion: D*.
            fraction: The perfusion fraction f.
            s0: The signal at b = 0.
        """
        self.diffusion = diffusion
        self.pseudo_diffusion = pseudo_diffusion
        self.fraction = fraction
        self.s0 = s0


struct _Plan(Movable):
    """The b-values in s/mm^2, split into the high and the low ones."""

    var b: List[Float64]
    var split: Float64
    var high: Int

    def __init__(out self, b_values: List[BValue64], split: BValue64) raises:
        """Check and keep the b-values.

        Args:
            b_values: The b-values.
            split: The least b-value of the fit of D.

        Raises:
            Error: If there are fewer than four b-values, the first is not
                0, they do not rise or are not finite, the split is not
                positive and finite, fewer than two are at or above it, or
                none is between 0 and it.
        """
        self.b = List[Float64]()
        self.high = 0
        self.split = split.to(SECOND_PER_SQUARE_MILLIMETER)
        if len(b_values) < 4:
            raise Error("An IVIM fit needs 4 b-values or more")
        if not (self.split > 0) or not isfinite(self.split):
            raise Error("The split of an IVIM fit must be positive and finite")
        var middle = 0
        for value in b_values:  # pragma: no branch
            var v = value.to(SECOND_PER_SQUARE_MILLIMETER)
            if not isfinite(v) or (
                len(self.b) > 0 and not (v > self.b[len(self.b) - 1])
            ):
                raise Error(
                    "The b-values of an IVIM fit must be finite and rise"
                )
            self.b.append(v)
            if v >= self.split:
                self.high += 1
            elif v > 0:
                middle += 1
        if self.b[0] != 0:
            raise Error("An IVIM fit needs a first b-value of 0")
        if self.high < 2 or middle < 1:
            raise Error(
                "An IVIM fit needs two b-values at or above the split, and one"
                " between 0 and it"
            )

    def fit(self, s: List[Float64]) -> IvimFit:
        """Fit the model to positive signals, one for each b-value."""
        var n = Float64(self.high)
        var mx = 0.0
        var my = 0.0
        for i in range(len(self.b)):  # pragma: no branch
            if self.b[i] >= self.split:
                mx += self.b[i] / n
                my += log(s[i]) / n
        var xx = 0.0
        var xy = 0.0
        for i in range(len(self.b)):  # pragma: no branch
            if self.b[i] >= self.split:
                xx += (self.b[i] - mx) * (self.b[i] - mx)
                xy += (self.b[i] - mx) * (log(s[i]) - my)
        var d = -xy / xx
        var f = 1.0 - precise_exp(my + d * mx) / s[0]
        var low = _LEAST_LOG_STAR
        var high = _MOST_LOG_STAR
        var c = high - _GOLDEN * (high - low)
        var e = low + _GOLDEN * (high - low)
        var fc = self._cost(s, d, f, c)
        var fe = self._cost(s, d, f, e)
        for _ in range(_SEARCH_STEPS):  # pragma: no branch
            if fc < fe:
                high = e
                e = c
                fe = fc
                c = high - _GOLDEN * (high - low)
                fc = self._cost(s, d, f, c)
            else:
                low = c
                c = e
                fc = fe
                e = low + _GOLDEN * (high - low)
                fe = self._cost(s, d, f, e)
        return IvimFit(
            Diffusivity64(d, SQUARE_MILLIMETER_PER_SECOND),
            Diffusivity64(
                precise_exp((low + high) / 2.0), SQUARE_MILLIMETER_PER_SECOND
            ),
            f,
            s[0],
        )

    def _cost(
        self, s: List[Float64], d: Float64, f: Float64, log_star: Float64
    ) -> Float64:
        """Return the sum of squares of the model below the split."""
        var star = precise_exp(log_star)
        var total = 0.0
        for i in range(len(self.b)):  # pragma: no branch
            if self.b[i] < self.split:
                var model = s[0] * (
                    f * precise_exp(-self.b[i] * star)
                    + (1.0 - f) * precise_exp(-self.b[i] * d)
                )
                total += (model - s[i]) * (model - s[i])
        return total


def fit_ivim(
    b_values: List[BValue64], signals: List[Float64], split: BValue64
) raises -> IvimFit:
    """Fit the IVIM model to the signals of one voxel, in segments.

    Args:
        b_values: The b-values, 0 first and rising, four or more.
        signals: The signal at each b-value, above 0.
        split: The least b-value of the fit of D, such as 200 s/mm^2. Two
            b-values or more must be at or above it, and one between 0 and
            it.

    Returns:
        D, D*, f and the signal at b = 0.

    Raises:
        Error: If the b-values or the split are not valid, or there is not
            one positive, finite signal for each b-value.
    """
    var plan = _Plan(b_values, split)
    if len(signals) != len(plan.b):
        raise Error("An IVIM fit needs one signal for each b-value")
    for s in signals:  # pragma: no branch
        if not (s > 0) or not isfinite(s):
            raise Error("An IVIM signal must be positive and finite")
    return plan.fit(signals)


struct IvimMaps(Copyable, Movable):
    """The IVIM parameters of each voxel of a series."""

    var diffusion: ImageVolume
    """D, in 10^-6 mm^2/s. 0 where a voxel has no fit."""
    var pseudo_diffusion: ImageVolume
    """D*, in 10^-6 mm^2/s. 0 where a voxel has no fit."""
    var fraction: ImageVolume
    """The perfusion fraction f. 0 where a voxel has no fit."""

    def __init__(
        out self,
        var diffusion: ImageVolume,
        var pseudo_diffusion: ImageVolume,
        var fraction: ImageVolume,
    ):
        """Create maps.

        Args:
            diffusion: The D map.
            pseudo_diffusion: The D* map.
            fraction: The f map.
        """
        self.diffusion = diffusion^
        self.pseudo_diffusion = pseudo_diffusion^
        self.fraction = fraction^


def ivim_maps(
    series: List[ImageVolume],
    b_values: List[BValue64],
    split: BValue64,
    threshold: Float64,
) raises -> IvimMaps:
    """Fit the IVIM model at each voxel of a series.

    A voxel has a fit when each of its signals is finite and above the
    threshold.

    Args:
        series: One volume for each b-value, on one grid.
        b_values: The b-values, as for `fit_ivim`.
        split: The least b-value of the fit of D.
        threshold: The signal that each signal of a voxel must be above. 0
            or more.

    Returns:
        The maps of D and D* in 10^-6 mm^2/s and of f, with the placement of
        the first volume and a window that fits each.

    Raises:
        Error: If the b-values or the split are not valid, there is not one
            volume for each b-value, the volumes have different grids, or
            the threshold is not finite or is below 0.
    """
    var plan = _Plan(b_values, split)
    if len(series) != len(plan.b):
        raise Error("An IVIM series needs one volume for each b-value")
    if not (threshold >= 0) or not isfinite(threshold):
        raise Error("An IVIM threshold must be finite and 0 or more")
    var diffusion = series[0].copy()
    for volume in series:  # pragma: no branch
        if (
            volume.nx != diffusion.nx
            or volume.ny != diffusion.ny
            or volume.nz != diffusion.nz
        ):
            raise Error("The volumes of an IVIM series have different grids")
    for at in range(diffusion.count()):  # pragma: no branch
        diffusion.values[at] = 0
    var star = diffusion.copy()
    var fraction = diffusion.copy()
    for at in range(diffusion.count()):  # pragma: no branch
        var s = List[Float64]()
        for volume in series:  # pragma: no branch
            var v = Float64(volume.values[at])
            if not (v > threshold) or not isfinite(v):
                break
            s.append(v)
        if len(s) != len(plan.b):
            continue
        var fit = plan.fit(s)
        diffusion.values[at] = Float32(
            fit.diffusion.to(SQUARE_MICROMETER_PER_SECOND)
        )
        star.values[at] = Float32(
            fit.pseudo_diffusion.to(SQUARE_MICROMETER_PER_SECOND)
        )
        fraction.values[at] = Float32(fit.fraction)
    diffusion.fit_window()
    star.fit_window()
    fraction.fit_window()
    return IvimMaps(diffusion^, star^, fraction^)
