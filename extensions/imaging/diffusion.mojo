# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Diffusion MRI: the apparent diffusion coefficient (ADC), diffusion
kurtosis, and computed diffusion images.

A diffusion-weighted scan takes one image at each b-value. Water that
moves freely loses more signal at a high b-value than water that cells
hold in. The mono-exponential model gives the signal

    S(b) = S0 exp(-b ADC)

Many tumors have dense cells and a low ADC, so oncology research maps it.
The kurtosis model of Jensen and others (2005) adds the departure of the
water from free diffusion:

    S(b) = S0 exp(-b D + b^2 D^2 K / 6)

- `fit_adc` fits ln S to a line in b by least squares, for two b-values
  or more. Two b-values give `ln(S1 / S2) / (b2 - b1)`.
- `fit_kurtosis` fits ln S to a parabola in b by least squares, for three
  distinct b-values or more.
- `adc_maps` and `kurtosis_maps` fit each voxel of a series of volumes.
- `computed_dwi` makes the image at a b-value that was not scanned, from
  the ADC and S0 maps.

The b-values are a `BValue64`, in s/mm^2 as scanners give them. The
diffusivities are a `Diffusivity64`. The maps hold them in 10^-6 mm^2/s,
the unit that scanners store, so free water at 37 C is near 3000.
"""

from extensions.imaging.image_volume import ImageVolume
from std.math import expm1, isfinite, log
from units.quantity import Quantity, Unit

comptime Diffusivity64 = Quantity[2, 0, -1, 0, 0, DType.float64]
"""An area each second: a diffusion coefficient."""
comptime BValue64 = Quantity[-2, 0, 1, 0, 0, DType.float64]
"""A time over an area: the diffusion weighting of an image."""
comptime SQUARE_MILLIMETER_PER_SECOND = Unit[2, 0, -1, 0, 0, DType.float64](
    1.0e-6, "mm^2/s"
)
comptime SQUARE_MICROMETER_PER_SECOND = Unit[2, 0, -1, 0, 0, DType.float64](
    1.0e-12, "um^2/s"
)
comptime SECOND_PER_SQUARE_MILLIMETER = Unit[-2, 0, 1, 0, 0, DType.float64](
    1.0e6, "s/mm^2"
)
# The fits work in ms/um^2 and um^2/ms, where b and D are near 1.
comptime _MILLISECOND_PER_SQUARE_MICROMETER = Unit[
    -2, 0, 1, 0, 0, DType.float64
](1.0e9, "ms/um^2")
comptime _SQUARE_MICROMETER_PER_MILLISECOND = Unit[
    2, 0, -1, 0, 0, DType.float64
](1.0e-9, "um^2/ms")


def _exp(x: Float64) -> Float64:
    """Return `e^x` from `expm1`, to a few units in the last place."""
    if x >= -1.0:
        return 1.0 + expm1(x)
    return 1.0 / (1.0 + expm1(-x))


struct AdcFit(Copyable, Movable):
    """The mono-exponential fit of one set of signals."""

    var adc: Diffusivity64
    """The apparent diffusion coefficient. Below 0 when the signal rises
    with b."""
    var s0: Float64
    """The fitted signal at b = 0, in the unit of the signals."""

    def __init__(out self, adc: Diffusivity64, s0: Float64):
        """Create a fit.

        Args:
            adc: The apparent diffusion coefficient.
            s0: The signal at b = 0.
        """
        self.adc = adc
        self.s0 = s0


struct KurtosisFit(Copyable, Movable):
    """The kurtosis fit of one set of signals."""

    var diffusivity: Diffusivity64
    """The diffusion coefficient D, without the kurtosis."""
    var kurtosis: Float64
    """The kurtosis K. 0 for free diffusion."""
    var s0: Float64
    """The fitted signal at b = 0, in the unit of the signals."""

    def __init__(
        out self, diffusivity: Diffusivity64, kurtosis: Float64, s0: Float64
    ):
        """Create a fit.

        Args:
            diffusivity: The diffusion coefficient.
            kurtosis: The kurtosis.
            s0: The signal at b = 0.
        """
        self.diffusivity = diffusivity
        self.kurtosis = kurtosis
        self.s0 = s0


struct _Design(Movable):
    """The b-values of a fit, centered, with the sums of the least squares."""

    var count: Int
    """The number of b-values."""
    var mean: Float64
    """The mean b-value, in ms/um^2."""
    var linear: List[Float64]
    """Each b-value less the mean."""
    var square: List[Float64]
    """The square of each centered b-value, less the mean of the squares."""
    var spread: Float64
    """The mean of the squares of the centered b-values."""
    var cc: Float64
    """The sum of the squares of `linear`."""
    var cq: Float64
    """The sum of the products of `linear` and `square`."""
    var qq: Float64
    """The sum of the squares of `square`."""

    def __init__(out self, b_values: List[BValue64], least: Int) raises:
        """Center the b-values.

        Args:
            b_values: The b-values.
            least: The fewest b-values of the fit.

        Raises:
            Error: If there are fewer b-values than `least`, or a b-value
                is not finite or is below 0.
        """
        self.count = len(b_values)
        if self.count < least:
            raise Error(
                "A diffusion fit needs " + String(least) + " b-values or more"
            )
        var x = List[Float64]()
        var total = 0.0
        for b in b_values:  # pragma: no branch
            var value = b.to(_MILLISECOND_PER_SQUARE_MICROMETER)
            if not (value >= 0) or not isfinite(value):
                raise Error("A b-value must be finite and 0 or more")
            x.append(value)
            total += value
        var n = Float64(self.count)
        self.mean = total / n
        self.linear = List[Float64]()
        self.spread = 0.0
        self.cc = 0.0
        for value in x:  # pragma: no branch
            var c = value - self.mean
            self.linear.append(c)
            self.cc += c * c
        self.spread = self.cc / n
        self.square = List[Float64]()
        self.cq = 0.0
        self.qq = 0.0
        for c in self.linear:  # pragma: no branch
            var q = c * c - self.spread
            self.square.append(q)
            self.cq += c * q
            self.qq += q * q

    def require_line(self) raises:
        """Refuse b-values that are all equal.

        Raises:
            Error: If the b-values do not vary.
        """
        if not (self.cc > 0):
            raise Error("An ADC fit needs two distinct b-values or more")

    def require_parabola(self) raises:
        """Refuse b-values with fewer than three distinct values.

        Raises:
            Error: If the b-values do not fix a parabola.
        """
        if not (
            self.cc * self.qq - self.cq * self.cq > 1e-9 * self.cc * self.qq
        ):
            raise Error("A kurtosis fit needs three distinct b-values or more")

    def line(self, y: List[Float64]) -> Tuple[Float64, Float64]:
        """Fit a line to the log signals.

        Args:
            y: The log of each signal.

        Returns:
            D in um^2/ms, and ln S0.
        """
        var mean = 0.0
        for v in y:  # pragma: no branch
            mean += v
        mean /= Float64(self.count)
        var cy = 0.0
        for at in range(self.count):  # pragma: no branch
            cy += self.linear[at] * (y[at] - mean)
        var slope = cy / self.cc
        return (-slope, mean - slope * self.mean)

    def parabola(self, y: List[Float64]) -> Tuple[Float64, Float64, Float64]:
        """Fit a parabola to the log signals.

        Args:
            y: The log of each signal.

        Returns:
            The coefficients of b^0, b^1 and b^2, with b in ms/um^2.
        """
        var mean = 0.0
        for v in y:  # pragma: no branch
            mean += v
        mean /= Float64(self.count)
        var cy = 0.0
        var qy = 0.0
        for at in range(self.count):  # pragma: no branch
            cy += self.linear[at] * (y[at] - mean)
            qy += self.square[at] * (y[at] - mean)
        var det = self.cc * self.qq - self.cq * self.cq
        var first = (self.qq * cy - self.cq * qy) / det
        var second = (self.cc * qy - self.cq * cy) / det
        var x = self.mean
        return (
            mean - first * x + second * (x * x - self.spread),
            first - 2.0 * second * x,
            second,
        )


def _log_signals(signals: List[Float64], count: Int) raises -> List[Float64]:
    """Return the log of each signal, checked to be positive."""
    if len(signals) != count:
        raise Error("A diffusion fit needs one signal for each b-value")
    var out = List[Float64]()
    for s in signals:  # pragma: no branch
        if not (s > 0) or not isfinite(s):
            raise Error("A diffusion signal must be positive and finite")
        out.append(log(s))
    return out^


def _diffusivity(value: Float64) -> Diffusivity64:
    """Return a diffusivity in um^2/ms as a quantity."""
    return Diffusivity64(value, _SQUARE_MICROMETER_PER_MILLISECOND)


def fit_adc(b_values: List[BValue64], signals: List[Float64]) raises -> AdcFit:
    """Fit the mono-exponential model to the signals of one voxel.

    Args:
        b_values: The b-values.
        signals: The signal at each b-value.

    Returns:
        The ADC and S0 of the least squares line of ln S on b.

    Raises:
        Error: If there are fewer than two b-values, they are all equal, a
            b-value is not finite or is below 0, there is not one signal for
            each b-value, or a signal is not positive and finite.
    """
    var design = _Design(b_values, 2)
    design.require_line()
    var fit = design.line(_log_signals(signals, design.count))
    return AdcFit(_diffusivity(fit[0]), _exp(fit[1]))


def fit_kurtosis(
    b_values: List[BValue64], signals: List[Float64]
) raises -> KurtosisFit:
    """Fit the kurtosis model to the signals of one voxel.

    The model holds for b-values below about `3 / (D K)`, where the
    parabola turns.

    Args:
        b_values: The b-values.
        signals: The signal at each b-value.

    Returns:
        D, K and S0 of the least squares parabola of ln S on b.

    Raises:
        Error: If there are fewer than three distinct b-values, a b-value
            is not finite or is below 0, there is not one signal for each
            b-value, a signal is not positive and finite, or the fitted D
            is not positive.
    """
    var design = _Design(b_values, 3)
    design.require_parabola()
    var fit = design.parabola(_log_signals(signals, design.count))
    var d = -fit[1]
    if not (d > 0):
        raise Error("A kurtosis fit needs signals that fall with b")
    return KurtosisFit(_diffusivity(d), 6.0 * fit[2] / (d * d), _exp(fit[0]))


struct AdcMaps(Copyable, Movable):
    """The ADC and S0 of each voxel of a series."""

    var adc: ImageVolume
    """The ADC, in 10^-6 mm^2/s. 0 where a signal is at or below the
    threshold."""
    var s0: ImageVolume
    """The fitted signal at b = 0. 0 where a signal is at or below the
    threshold."""

    def __init__(out self, var adc: ImageVolume, var s0: ImageVolume):
        """Create maps.

        Args:
            adc: The ADC map.
            s0: The S0 map.
        """
        self.adc = adc^
        self.s0 = s0^


struct KurtosisMaps(Copyable, Movable):
    """The D, K and S0 of each voxel of a series."""

    var diffusivity: ImageVolume
    """D, in 10^-6 mm^2/s. 0 where a voxel has no fit."""
    var kurtosis: ImageVolume
    """K. 0 where a voxel has no fit."""
    var s0: ImageVolume
    """The fitted signal at b = 0. 0 where a voxel has no fit."""

    def __init__(
        out self,
        var diffusivity: ImageVolume,
        var kurtosis: ImageVolume,
        var s0: ImageVolume,
    ):
        """Create maps.

        Args:
            diffusivity: The D map.
            kurtosis: The K map.
            s0: The S0 map.
        """
        self.diffusivity = diffusivity^
        self.kurtosis = kurtosis^
        self.s0 = s0^


def _require_series(
    series: List[ImageVolume], design: _Design, threshold: Float64
) raises -> ImageVolume:
    """Refuse a series that does not match the b-values or shares no grid,
    or a threshold below 0. Return a volume of zeros on the grid."""
    if len(series) != design.count:
        raise Error("A diffusion series needs one volume for each b-value")
    if not (threshold >= 0) or not isfinite(threshold):
        raise Error("A diffusion threshold must be finite and 0 or more")
    var first = series[0].copy()
    for volume in series:  # pragma: no branch
        if (
            volume.nx != first.nx
            or volume.ny != first.ny
            or volume.nz != first.nz
        ):
            raise Error(
                "The volumes of a diffusion series have different grids"
            )
    for at in range(first.count()):  # pragma: no branch
        first.values[at] = 0
    return first^


def _voxel(
    series: List[ImageVolume], at: Int, threshold: Float64
) -> List[Float64]:
    """Return the log signals of a voxel, or no values when a signal is not
    finite or not above the threshold."""
    var out = List[Float64]()
    for volume in series:  # pragma: no branch
        var s = Float64(volume.values[at])
        if not (s > threshold) or not isfinite(s):
            return List[Float64]()
        out.append(log(s))
    return out^


def adc_maps(
    series: List[ImageVolume], b_values: List[BValue64], threshold: Float64
) raises -> AdcMaps:
    """Fit the mono-exponential model at each voxel of a series.

    Args:
        series: One volume for each b-value, on one grid.
        b_values: The b-values.
        threshold: The signal that each signal of a voxel must be above for
            a fit. 0 or more. Choose one above the noise of the background.

    Returns:
        The ADC map in 10^-6 mm^2/s and the S0 map, with the placement of
        the first volume and a window that fits their values.

    Raises:
        Error: If the b-values are not valid, as for `fit_adc`, there is not
            one volume for each b-value, the volumes have different grids,
            or the threshold is not finite or is below 0.
    """
    var design = _Design(b_values, 2)
    design.require_line()
    var adc = _require_series(series, design, threshold)
    var s0 = adc.copy()
    for at in range(adc.count()):  # pragma: no branch
        var y = _voxel(series, at, threshold)
        if len(y) == 0:
            continue
        var fit = design.line(y)
        adc.values[at] = Float32(
            _diffusivity(fit[0]).to(SQUARE_MICROMETER_PER_SECOND)
        )
        s0.values[at] = Float32(_exp(fit[1]))
    adc.fit_window()
    s0.fit_window()
    return AdcMaps(adc^, s0^)


def kurtosis_maps(
    series: List[ImageVolume], b_values: List[BValue64], threshold: Float64
) raises -> KurtosisMaps:
    """Fit the kurtosis model at each voxel of a series.

    A voxel has no fit when a signal is not above the threshold or its
    fitted D is not positive.

    Args:
        series: One volume for each b-value, on one grid.
        b_values: The b-values.
        threshold: The signal that each signal of a voxel must be above for
            a fit. 0 or more.

    Returns:
        The D map in 10^-6 mm^2/s, the K map and the S0 map, with the
        placement of the first volume and a window that fits their values.

    Raises:
        Error: If the b-values are not valid, as for `fit_kurtosis`, there
            is not one volume for each b-value, the volumes have different
            grids, or the threshold is not finite or is below 0.
    """
    var design = _Design(b_values, 3)
    design.require_parabola()
    var diffusivity = _require_series(series, design, threshold)
    var kurtosis = diffusivity.copy()
    var s0 = diffusivity.copy()
    for at in range(diffusivity.count()):  # pragma: no branch
        var y = _voxel(series, at, threshold)
        if len(y) == 0:
            continue
        var fit = design.parabola(y)
        var d = -fit[1]
        if not (d > 0):
            continue
        diffusivity.values[at] = Float32(
            _diffusivity(d).to(SQUARE_MICROMETER_PER_SECOND)
        )
        kurtosis.values[at] = Float32(6.0 * fit[2] / (d * d))
        s0.values[at] = Float32(_exp(fit[0]))
    diffusivity.fit_window()
    kurtosis.fit_window()
    s0.fit_window()
    return KurtosisMaps(diffusivity^, kurtosis^, s0^)


def computed_dwi(maps: AdcMaps, b_value: BValue64) raises -> ImageVolume:
    """Make the image at a b-value from the ADC and S0 maps.

    A computed image at a high b-value, such as 1500 s/mm^2, can show a
    lesion of low ADC with less noise than a scan at that b-value.

    Args:
        maps: The ADC and S0 maps, from `adc_maps`.
        b_value: The b-value of the image. Finite and 0 or more.

    Returns:
        `S0 exp(-b ADC)` at each voxel, on the grid of the maps, with a
        window that fits its values. 0 where S0 is 0.

    Raises:
        Error: If the b-value is not finite or is below 0, or the two maps
            have different grids.
    """
    var b = b_value.to(SECOND_PER_SQUARE_MILLIMETER)
    if not (b >= 0) or not isfinite(b):
        raise Error("A b-value must be finite and 0 or more")
    if (
        maps.adc.nx != maps.s0.nx
        or maps.adc.ny != maps.s0.ny
        or maps.adc.nz != maps.s0.nz
    ):
        raise Error("The ADC and S0 maps have different grids")
    var out = maps.s0.copy()
    for at in range(out.count()):  # pragma: no branch
        var s0 = Float64(maps.s0.values[at])
        if s0 == 0:
            continue
        var adc = Diffusivity64(
            Float64(maps.adc.values[at]), SQUARE_MICROMETER_PER_SECOND
        ).to(SQUARE_MILLIMETER_PER_SECOND)
        out.values[at] = Float32(s0 * _exp(-b * adc))
    out.fit_window()
    return out^
