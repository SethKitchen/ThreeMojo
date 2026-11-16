# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Perfusion of CT and DSC-MRI by deconvolution: the blood flow, blood
volume, mean transit time and Tmax of a tissue.

A perfusion scan follows a bolus of contrast agent through the brain. The
tissue concentration is the arterial concentration convolved with
`k(t) = F R(t)`, the flow F times the residue function R:

    Ct(t) = integral of Ca(s) k(t - s) ds

`Deconvolution(arterial, step, threshold)` writes the convolution as the
lower triangular matrix `A[j, i] = step * Ca[j - i]` of Ostergaard and
others (1996). `Deconvolution.circular` pads both curves with zeros to
twice their length and takes the block-circulant matrix of Wu and others
(2003). A delay of the tissue curve then does not change its flow. Both
drop the singular values below `threshold` of the largest, which keeps
the noise from growing, and keep the pseudo-inverse of what is left.

The singular values are the square roots of the eigenvalues of `A^T A`,
by the Jacobi method. The pseudo-inverse is
`sum v_k (A v_k)^T / lambda_k` over the kept eigenvectors.

`fit(tissue)` gives:

- the flow, the largest value of k, as a rate a second;
- Tmax, the time of the largest value of k;
- the volume, the area of the tissue curve over that of the arterial
  curve;
- the mean transit time, the volume over the flow.

`blood_flow` and `blood_volume` give CBF in mL/100 g/min and CBV in
mL/100 g, from a tissue density and a hematocrit factor. Stroke research
reads an ischemic core where CBF is below 30 percent of normal, and a
tissue at risk where Tmax is above 6 s. `perfusion_mismatch` measures
both.
"""

from extensions.imaging.ids import BACKGROUND, LabelId, require_label
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, require_same_grid
from extensions.numerics.dense import DenseMatrix, symmetric_eigen
from std.math import isfinite, log, sqrt
from units.quantity import Quantity, Unit
from units.si import (
    CUBIC_METER,
    Density64,
    Duration64,
    Frequency64,
    GRAM_PER_CUBIC_CENTIMETER,
    KILOGRAM_PER_CUBIC_METER,
    PER_SECOND,
    SECOND,
    Volume64,
)

comptime BloodFlow64 = Quantity[3, -1, -1, 0, 0, DType.float64]
"""A blood flow for each mass of tissue, such as CBF."""
comptime BloodVolume64 = Quantity[3, -1, 0, 0, 0, DType.float64]
"""A blood volume for each mass of tissue, such as CBV."""
comptime MILLILITER_PER_100_GRAM_PER_MINUTE = Unit[
    3, -1, -1, 0, 0, DType.float64
](1.0e-6 / 0.1 / 60.0, "mL/100 g/min")
"""The unit of CBF."""
comptime MILLILITER_PER_100_GRAM = Unit[3, -1, 0, 0, 0, DType.float64](
    1.0e-5, "mL/100 g"
)
"""The unit of CBV."""
comptime CUBIC_METER_PER_KILOGRAM = Unit[3, -1, 0, 0, 0, DType.float64](
    1.0, "m^3/kg"
)
"""The SI unit of a volume for each mass."""
comptime BRAIN_DENSITY = 1.04
"""The density of brain tissue, in g/mL."""
comptime HEMATOCRIT_FACTOR = 0.55 / 0.75
"""`(1 - 0.45) / (1 - 0.25)`: the hematocrit of the large vessels over
that of the capillaries, as one less each."""
comptime MAX_FRAMES = 128
"""The most frames of a deconvolution."""


def _require_baseline(count: Int, baseline: Int) raises:
    """Refuse a baseline that is not from 1 frame to all of them."""
    if baseline < 1 or baseline > count:
        raise Error("A perfusion baseline is from 1 frame to all of them")


def ct_concentration(
    values: List[Float64], baseline: Int
) raises -> List[Float64]:
    """Return the enhancement of a CT curve over its baseline.

    The enhancement in HU is in proportion to the iodine concentration.

    Args:
        values: The value of each frame, in HU, finite.
        baseline: The first frames, before the contrast arrives, whose
            mean is the baseline. From 1 to all of them.

    Returns:
        Each value less the mean of the baseline frames.

    Raises:
        Error: If the baseline is out of range or a value is not finite.
    """
    _require_baseline(len(values), baseline)
    var mean = 0.0
    for at in range(len(values)):  # pragma: no branch
        if not isfinite(values[at]):
            raise Error("A perfusion curve needs finite values")
        if at < baseline:
            mean += values[at] / Float64(baseline)
    var out = List[Float64]()
    for v in values:  # pragma: no branch
        out.append(v - mean)
    return out^


def dsc_concentration(
    signals: List[Float64], baseline: Int, echo_time: Duration64
) raises -> List[Float64]:
    """Return the change of the relaxation rate R2* of a DSC-MRI curve.

    The change `-ln(S / S0) / TE` is in proportion to the concentration of
    the gadolinium.

    Args:
        signals: The signal of each frame, above 0 and finite.
        baseline: The first frames, before the contrast arrives, whose
            mean is S0. From 1 to all of them.
        echo_time: The echo time TE, positive and finite.

    Returns:
        The change of R2* of each frame, in 1/s.

    Raises:
        Error: If the baseline is out of range, a signal is not positive
            and finite, or the echo time is not positive and finite.
    """
    _require_baseline(len(signals), baseline)
    var te = echo_time.to(SECOND)
    if not (te > 0) or not isfinite(te):
        raise Error("A DSC echo time must be positive and finite")
    var s0 = 0.0
    for at in range(len(signals)):  # pragma: no branch
        if not (signals[at] > 0) or not isfinite(signals[at]):
            raise Error("A DSC signal must be positive and finite")
        if at < baseline:
            s0 += signals[at] / Float64(baseline)
    var out = List[Float64]()
    for s in signals:  # pragma: no branch
        out.append(-log(s / s0) / te)
    return out^


struct PerfusionFit(Copyable, Movable):
    """The perfusion of one tissue curve."""

    var flow: Frequency64
    """The flow F: the largest value of the residue `k = F R`."""
    var volume: Float64
    """The blood volume, as a share of the tissue: the area of the tissue
    curve over that of the arterial curve."""
    var tmax: Duration64
    """The time of the largest value of the residue."""

    def __init__(
        out self, flow: Frequency64, volume: Float64, tmax: Duration64
    ):
        """Create a fit.

        Args:
            flow: The flow.
            volume: The blood volume, as a share of the tissue.
            tmax: The time of the largest value of the residue.
        """
        self.flow = flow
        self.volume = volume
        self.tmax = tmax

    def mtt(self) raises -> Duration64:
        """Return the mean transit time.

        Returns:
            The volume over the flow, by the central volume theorem.

        Raises:
            Error: If the flow is not above 0.
        """
        var f = self.flow.to(PER_SECOND)
        if not (f > 0):
            raise Error("A mean transit time needs a flow above 0")
        return Duration64(self.volume / f, SECOND)

    def blood_flow(
        self, density: Density64, factor: Float64
    ) raises -> BloodFlow64:
        """Return the blood flow for each mass of tissue, CBF.

        Args:
            density: The density of the tissue, such as `BRAIN_DENSITY`
                g/mL. Positive and finite.
            factor: The hematocrit factor, such as `HEMATOCRIT_FACTOR`.
                Positive and finite.

        Returns:
            `factor F / density`.

        Raises:
            Error: If the density or the factor is not positive and finite.
        """
        _require_scales(density, factor)
        return (self.flow / density).scaled(factor)

    def blood_volume(
        self, density: Density64, factor: Float64
    ) raises -> BloodVolume64:
        """Return the blood volume for each mass of tissue, CBV.

        Args:
            density: The density of the tissue. Positive and finite.
            factor: The hematocrit factor. Positive and finite.

        Returns:
            `factor volume / density`.

        Raises:
            Error: If the density or the factor is not positive and finite.
        """
        _require_scales(density, factor)
        return BloodVolume64(
            factor * self.volume / density.to(KILOGRAM_PER_CUBIC_METER),
            CUBIC_METER_PER_KILOGRAM,
        )


def _require_scales(density: Density64, factor: Float64) raises:
    """Refuse a density or a hematocrit factor that is not positive and
    finite."""
    var rho = density.to(KILOGRAM_PER_CUBIC_METER)
    if not (rho > 0) or not isfinite(rho):
        raise Error("A tissue density must be positive and finite")
    if not (factor > 0) or not isfinite(factor):
        raise Error("A hematocrit factor must be positive and finite")


struct Deconvolution(Movable):
    """The truncated pseudo-inverse of the convolution with an arterial
    curve."""

    var frames: Int
    """The frames of each curve."""
    var size: Int
    """The frames of the residue: `frames`, or twice that when circular."""
    var step: Duration64
    """The time between two frames."""
    var inverse: DenseMatrix
    """The truncated pseudo-inverse, `size` by `size`."""
    var arterial_area: Float64
    """The sum of the arterial curve."""
    var kept: Int
    """The singular values kept."""

    def __init__(
        out self, arterial: List[Float64], step: Duration64, threshold: Float64
    ) raises:
        """Make the deconvolution of Ostergaard and others, by the lower
        triangular matrix.

        Args:
            arterial: The arterial concentration at each frame, from 2 to
                128 frames, finite, with a sum above 0.
            step: The time between two frames, positive and finite.
            threshold: The least singular value kept, as a share of the
                largest, above 0 and below 1. Often 0.2.

        Raises:
            Error: If a curve, the step or the threshold is not valid.
        """
        self = _deconvolution(arterial, step, threshold, False)

    @staticmethod
    def circular(
        arterial: List[Float64], step: Duration64, threshold: Float64
    ) raises -> Deconvolution:
        """Make the deconvolution of Wu and others, by the block-circulant
        matrix. A delay of a tissue curve does not change its flow.

        Args:
            arterial: The arterial concentration at each frame, from 2 to
                128 frames, finite, with a sum above 0.
            step: The time between two frames, positive and finite.
            threshold: The least singular value kept, as a share of the
                largest, above 0 and below 1. Often 0.1 to 0.2.

        Returns:
            The deconvolution, with residues of twice the frames.

        Raises:
            Error: If a curve, the step or the threshold is not valid.
        """
        return _deconvolution(arterial, step, threshold, True)

    def __init__(
        out self,
        frames: Int,
        size: Int,
        step: Duration64,
        var inverse: DenseMatrix,
        arterial_area: Float64,
        kept: Int,
    ):
        """Hold a deconvolution.

        Args:
            frames: The frames of each curve.
            size: The frames of the residue.
            step: The time between two frames.
            inverse: The truncated pseudo-inverse, `size` by `size`.
            arterial_area: The sum of the arterial curve.
            kept: The singular values kept.
        """
        self.frames = frames
        self.size = size
        self.step = step
        self.inverse = inverse^
        self.arterial_area = arterial_area
        self.kept = kept

    def residue(self, tissue: List[Float64]) raises -> List[Float64]:
        """Return the residue `k = F R(t)` of a tissue curve.

        Args:
            tissue: The tissue concentration at each frame, in the unit of
                the arterial curve, finite.

        Returns:
            The value of k at each frame of the residue, in 1/s. A circular
            deconvolution gives twice the frames.

        Raises:
            Error: If the curve does not have one finite value for each
                frame.
        """
        if len(tissue) != self.frames:
            raise Error("A tissue curve needs one value for each frame")
        for v in tissue:  # pragma: no branch
            if not isfinite(v):
                raise Error("A perfusion curve needs finite values")
        var n = self.size
        var out = List[Float64](length=n, fill=0.0)
        for r in range(n):  # pragma: no branch
            var total = 0.0
            for c in range(self.frames):  # pragma: no branch
                total += self.inverse.data[r * n + c] * tissue[c]
            out[r] = total
        return out^

    def fit(self, tissue: List[Float64]) raises -> PerfusionFit:
        """Return the flow, the volume and Tmax of a tissue curve.

        Args:
            tissue: The tissue concentration at each frame, in the unit of
                the arterial curve, finite.

        Returns:
            The fit. Tmax is the first frame of the largest value of k.

        Raises:
            Error: If the curve does not have one finite value for each
                frame.
        """
        var k = self.residue(tissue)
        var best = 0
        for at in range(1, len(k)):  # pragma: no branch
            if k[at] > k[best]:
                best = at
        var area = 0.0
        for v in tissue:  # pragma: no branch
            area += v
        return PerfusionFit(
            Frequency64(k[best], PER_SECOND),
            area / self.arterial_area,
            Duration64(Float64(best) * self.step.to(SECOND), SECOND),
        )


def _deconvolution(
    arterial: List[Float64],
    step: Duration64,
    threshold: Float64,
    circular: Bool,
) raises -> Deconvolution:
    """Check the curve, the step and the threshold, and make the truncated
    pseudo-inverse of the lower triangular or block-circulant matrix."""
    var frames = len(arterial)
    if frames < 2 or frames > MAX_FRAMES:
        raise Error("A perfusion curve has from 2 to 128 frames")
    var dt = step.to(SECOND)
    if not (dt > 0) or not isfinite(dt):
        raise Error("A perfusion step must be positive and finite")
    if not (threshold > 0) or not (threshold < 1):
        raise Error("A perfusion threshold is above 0 and below 1")
    var area = 0.0
    for v in arterial:  # pragma: no branch
        if not isfinite(v):
            raise Error("A perfusion curve needs finite values")
        area += v
    if not (area > 0):
        raise Error("An arterial curve needs a sum above 0")
    var n = frames * 2 if circular else frames
    var a = DenseMatrix(n, n)
    for j in range(n):  # pragma: no branch
        for i in range(n):  # pragma: no branch
            var lag = j - i
            if lag < 0 and circular:
                lag += n
            if lag >= 0 and lag < frames:
                a.data[j * n + i] = dt * arterial[lag]
    var gram = DenseMatrix(n, n)
    for r in range(n):  # pragma: no branch
        for c in range(n):  # pragma: no branch
            var total = 0.0
            for k in range(n):  # pragma: no branch
                total += a.data[k * n + r] * a.data[k * n + c]
            gram.data[r * n + c] = total
    var pairs = symmetric_eigen(gram)
    var least = threshold * threshold * pairs.values[n - 1]
    var inverse = DenseMatrix(n, n)
    var kept = 0
    for e in range(n):  # pragma: no branch
        var value = pairs.values[e]
        if value < least:
            continue
        kept += 1
        # The column u = A v of this eigenvector, over its eigenvalue.
        var u = List[Float64](length=n, fill=0.0)
        for r in range(n):  # pragma: no branch
            var total = 0.0
            for k in range(n):  # pragma: no branch
                total += a.data[r * n + k] * pairs.vectors.data[k * n + e]
            u[r] = total / value
        for r in range(n):  # pragma: no branch
            var v = pairs.vectors.data[r * n + e]
            for c in range(n):  # pragma: no branch
                inverse.data[r * n + c] += v * u[c]
    return Deconvolution(frames, n, step, inverse^, area, kept)


struct PerfusionMaps(Copyable, Movable):
    """The perfusion of each voxel of a label."""

    var cbf: ImageVolume
    """CBF, in mL/100 g/min. 0 outside the label."""
    var cbv: ImageVolume
    """CBV, in mL/100 g. 0 outside the label."""
    var mtt: ImageVolume
    """The mean transit time, in s. 0 outside the label and where the flow
    is not above 0."""
    var tmax: ImageVolume
    """Tmax, in s. 0 outside the label."""

    def __init__(out self, grid: ImageVolume):
        """Create maps of zeros on a grid.

        Args:
            grid: The volume whose grid and placement the maps take.
        """
        var zero = grid.copy()
        for v in range(zero.count()):  # pragma: no branch
            zero.values[v] = 0
        self.cbf = zero.copy()
        self.cbv = zero.copy()
        self.mtt = zero.copy()
        self.tmax = zero^


def ct_concentration_series(
    series: List[ImageVolume], baseline: Int
) raises -> List[ImageVolume]:
    """Return the enhancement of each voxel of a CT series over its
    baseline.

    Args:
        series: The volume of each frame, in HU, on one grid.
        baseline: The first frames whose mean is the baseline. From 1 to
            all of them.

    Returns:
        One volume for each frame, each voxel less its baseline mean.

    Raises:
        Error: If the baseline is out of range, or the volumes have
            different grids.
    """
    _require_baseline(len(series), baseline)
    var out = List[ImageVolume]()
    for volume in series:  # pragma: no branch
        if (
            volume.nx != series[0].nx
            or volume.ny != series[0].ny
            or volume.nz != series[0].nz
        ):
            raise Error(
                "The volumes of a perfusion series have different grids"
            )
        out.append(volume.copy())
    for at in range(series[0].count()):  # pragma: no branch
        var mean = 0.0
        for f in range(baseline):  # pragma: no branch
            mean += Float64(series[f].values[at]) / Float64(baseline)
        for f in range(len(series)):  # pragma: no branch
            out[f].values[at] = Float32(Float64(series[f].values[at]) - mean)
    return out^


def perfusion_maps(
    series: List[ImageVolume],
    deconvolution: Deconvolution,
    map: LabelMap,
    label: LabelId,
    density: Density64,
    factor: Float64,
) raises -> PerfusionMaps:
    """Fit the perfusion of each voxel of a label.

    Args:
        series: The tissue concentration of each frame, one volume each,
            on the grid of the label map.
        deconvolution: The deconvolution of the arterial curve.
        map: The label map.
        label: The label. Not the background.
        density: The density of the tissue. Positive and finite.
        factor: The hematocrit factor. Positive and finite.

    Returns:
        The maps of CBF, CBV, the mean transit time and Tmax.

    Raises:
        Error: If the label is not valid or is the background, there is not
            one volume for each frame, a volume is on another grid, a value
            is not finite, or the density or the factor is not valid.
    """
    require_label(label)
    if label == BACKGROUND:
        raise Error("A perfusion map needs a label, not the background")
    if len(series) != deconvolution.frames:
        raise Error("A perfusion series needs one volume for each frame")
    for volume in series:  # pragma: no branch
        require_same_grid(map, volume)
    _require_scales(density, factor)
    var out = PerfusionMaps(series[0])
    var mark = UInt8(label.value)
    for at in range(map.count()):  # pragma: no branch
        if map.labels[at] != mark:
            continue
        var tissue = List[Float64]()
        for volume in series:  # pragma: no branch
            tissue.append(Float64(volume.values[at]))
        var fit = deconvolution.fit(tissue)
        out.cbf.values[at] = Float32(
            fit.blood_flow(density, factor).to(
                MILLILITER_PER_100_GRAM_PER_MINUTE
            )
        )
        out.cbv.values[at] = Float32(
            fit.blood_volume(density, factor).to(MILLILITER_PER_100_GRAM)
        )
        out.tmax.values[at] = Float32(fit.tmax.to(SECOND))
        if fit.flow.to(PER_SECOND) > 0:
            out.mtt.values[at] = Float32(fit.mtt().to(SECOND))
    return out^


struct PerfusionMismatch(Copyable, Movable):
    """The ischemic core and the tissue at risk of a label."""

    var core: Volume64
    """The volume whose CBF is below a share of the reference."""
    var hypoperfused: Volume64
    """The volume whose Tmax is above the threshold."""

    def __init__(out self, core: Volume64, hypoperfused: Volume64):
        """Create a mismatch.

        Args:
            core: The core volume.
            hypoperfused: The hypoperfused volume.
        """
        self.core = core
        self.hypoperfused = hypoperfused

    def ratio(self) raises -> Float64:
        """Return the mismatch ratio.

        Returns:
            The hypoperfused volume over the core volume.

        Raises:
            Error: If the core volume is 0.
        """
        var c = self.core.to(CUBIC_METER)
        if not (c > 0):
            raise Error("A mismatch ratio needs a core above 0")
        return self.hypoperfused.to(CUBIC_METER) / c

    def difference(self) -> Volume64:
        """Return the mismatch volume.

        Returns:
            The hypoperfused volume less the core volume.
        """
        return self.hypoperfused - self.core


def perfusion_mismatch(
    maps: PerfusionMaps,
    map: LabelMap,
    label: LabelId,
    reference: BloodFlow64,
    share: Float64,
    tmax: Duration64,
) raises -> PerfusionMismatch:
    """Measure the ischemic core and the tissue at risk of a label.

    Args:
        maps: The perfusion maps.
        map: The label map, on the grid of the maps.
        label: The label, such as the brain. Not the background.
        reference: The CBF of normal tissue, such as the mean of the other
            hemisphere. Positive and finite.
        share: The share of the reference below which a voxel is core,
            such as 0.3. Above 0 and below 1.
        tmax: The Tmax above which a voxel is at risk, such as 6 s.
            Positive and finite.

    Returns:
        The core and the hypoperfused volumes.

    Raises:
        Error: If the label is not valid or is the background, the maps
            are on another grid, or a threshold is not valid.
    """
    require_label(label)
    if label == BACKGROUND:
        raise Error("A perfusion mismatch needs a label, not the background")
    require_same_grid(map, maps.cbf)
    var flow = reference.to(MILLILITER_PER_100_GRAM_PER_MINUTE)
    if not (flow > 0) or not isfinite(flow):
        raise Error("A reference CBF must be positive and finite")
    if not (share > 0) or not (share < 1):
        raise Error("A core share is above 0 and below 1")
    var limit = tmax.to(SECOND)
    if not (limit > 0) or not isfinite(limit):
        raise Error("A Tmax threshold must be positive and finite")
    var voxel = (
        maps.cbf.spacing_x * maps.cbf.spacing_y * maps.cbf.spacing_z
    ).to(CUBIC_METER)
    var core = 0
    var risk = 0
    var mark = UInt8(label.value)
    for at in range(map.count()):  # pragma: no branch
        if map.labels[at] != mark:
            continue
        if Float64(maps.cbf.values[at]) < share * flow:
            core += 1
        if Float64(maps.tmax.values[at]) > limit:
            risk += 1
    return PerfusionMismatch(
        Volume64(Float64(core) * voxel, CUBIC_METER),
        Volume64(Float64(risk) * voxel, CUBIC_METER),
    )
