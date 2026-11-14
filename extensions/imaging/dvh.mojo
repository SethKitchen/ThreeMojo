# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Dose-volume histograms of a region, and the doses and volumes from them.

Radiotherapy research reports the dose of a tumor or an organ by its
dose-volume histogram (DVH): for each dose, the part of the region that
gets that dose or more. `dose_volume_histogram(dose, map, label)` takes
the dose of each voxel of a label, in grays, as `read_rt_dose` gives it.
It keeps each voxel's dose, so it has no bins:

| Measure | Method | Meaning |
|---|---|---|
| D98, D95, D50 and D2 | `dose_at_fraction` | the least dose of the hottest 98, 95, 50 or 2 percent |
| D for 0.03 cm^3 | `dose_at_volume` | the least dose of the hottest 0.03 cm^3 |
| V20 | `volume_at_dose` | the volume that gets 20 Gy or more |
| V20 as a part | `fraction_at_dose` | that volume over the volume of the region |
| The mean, least and largest dose | `mean`, `minimum` and `maximum` | of the doses of the voxels |
| gEUD | `equivalent_uniform_dose` | `(mean(d^a))^(1/a)`, after Niemierko |
| The curve | `curve` | the part that gets each step of dose or more |

The hottest voxels that reach a fraction or a volume are counted up, to
1e-9 of a voxel. Each voxel counts whole, with the dose at its center.
"""

from extensions.imaging.ids import BACKGROUND, LabelId, require_label
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, require_same_grid
from extensions.imaging.rtdose import AbsorbedDose64, GRAY
from std.math import ceil, floor, isfinite, isinf, log, max
from units.quantity import Unit
from units.si import CUBIC_METER, METER, Volume64

# The cubic centimeter, or milliliter, of 64-bit volumes. The
# `CUBIC_CENTIMETER` of `units.si` is 32-bit, so its scale is 1e-6 to 3e-9
# only.
comptime CUBIC_CENTIMETER64 = Unit[3, 0, 0, 0, 0, DType.float64](1.0e-6, "cm^3")

# A count of voxels is rounded up past this part of a voxel only.
comptime ROUNDING = 1.0e-9
# The most points of a curve.
comptime MOST_POINTS = 100000


def _power(x: Float64, y: Float64) -> Float64:
    """Return `x^y` for an `x` of 0 or more, to about 1e-15.

    The Float64 `exp` of Mojo 1.2 is off by up to about 1e-11, and so is a
    fractional power. One Newton step on `log`, which is exact, refines
    the power.
    """
    var t = x**y
    if not (t > 0) or isinf(t):
        return t
    return t * (1.0 + (y * log(x) - log(t)))


struct DoseVolumeHistogram(Copyable, Movable):
    """The doses of the voxels of a region, from the highest."""

    var doses: List[Float64]
    """The dose of each voxel, in grays, from the highest to the least."""
    var voxel_volume: Volume64
    """The volume of one voxel."""

    def __init__(
        out self, var doses: List[Float64], voxel_volume: Volume64
    ) raises:
        """Create a histogram from the doses of the voxels of a region.

        Args:
            doses: The dose of each voxel, in grays, in any order.
            voxel_volume: The volume of one voxel. Positive and finite.

        Raises:
            Error: If there is no dose, a dose is not finite, or the voxel
                volume is not positive and finite.
        """
        if len(doses) == 0:
            raise Error("A dose-volume histogram needs one dose or more")
        var v = voxel_volume.to(CUBIC_METER)
        if not (v > 0) or not isfinite(v):
            raise Error("A voxel volume must be positive and finite")
        for d in doses:  # pragma: no branch
            if not isfinite(d):
                raise Error("A dose-volume histogram needs finite doses")
        sort(doses)
        doses.reverse()
        self.doses = doses^
        self.voxel_volume = voxel_volume

    def count(self) -> Int:
        """Return the number of voxels.

        Returns:
            The number of voxels of the region.
        """
        return len(self.doses)

    def volume(self) -> Volume64:
        """Return the volume of the region.

        Returns:
            The number of voxels times the volume of one.
        """
        return Volume64(
            Float64(len(self.doses)) * self.voxel_volume.to(CUBIC_METER),
            CUBIC_METER,
        )

    def minimum(self) -> AbsorbedDose64:
        """Return the least dose.

        Returns:
            The least dose of a voxel.
        """
        return AbsorbedDose64(self.doses[len(self.doses) - 1], GRAY)

    def maximum(self) -> AbsorbedDose64:
        """Return the largest dose.

        Returns:
            The largest dose of a voxel.
        """
        return AbsorbedDose64(self.doses[0], GRAY)

    def mean(self) -> AbsorbedDose64:
        """Return the mean dose.

        Returns:
            The mean of the doses of the voxels.
        """
        var sum = 0.0
        # A histogram holds one dose or more.
        for d in self.doses:  # pragma: no branch
            sum += d
        return AbsorbedDose64(sum / Float64(len(self.doses)), GRAY)

    def _at_count(self, count: Int) -> AbsorbedDose64:
        """Return the least dose of the hottest `count` voxels, one or more."""
        return AbsorbedDose64(self.doses[max(count, 1) - 1], GRAY)

    def _count_at(self, dose: Float64) -> Int:
        """Return how many voxels get a dose, in grays, or more."""
        var low = 0
        var high = len(self.doses)
        while low < high:
            var middle = (low + high) // 2
            if self.doses[middle] >= dose:
                low = middle + 1
            else:
                high = middle
        return low

    def dose_at_fraction(self, fraction: Float64) raises -> AbsorbedDose64:
        """Return the least dose of the hottest part of the region.

        D95 is `dose_at_fraction(0.95)`, and D2 is `dose_at_fraction(0.02)`.

        Args:
            fraction: The part of the region, above 0 and at most 1.

        Returns:
            The least dose of the hottest voxels that make up the part.

        Raises:
            Error: If the fraction is not above 0 and at most 1.
        """
        if not (fraction > 0) or not (fraction <= 1):
            raise Error("A dose-volume fraction is above 0 and at most 1")
        var n = ceil(fraction * Float64(len(self.doses)) - ROUNDING)
        return self._at_count(Int(n))

    def dose_at_volume(self, volume: Volume64) raises -> AbsorbedDose64:
        """Return the least dose of the hottest volume of the region.

        Args:
            volume: The volume, such as `Volume64(0.03,
                CUBIC_CENTIMETER64)`. Positive, and at most the volume of
                the region.

        Returns:
            The least dose of the hottest voxels that make up the volume.

        Raises:
            Error: If the volume is not positive and finite, or is larger
                than the region.
        """
        var v = volume.to(CUBIC_METER)
        if not (v > 0) or not isfinite(v):
            raise Error("A dose-volume volume must be positive and finite")
        var n = Int(ceil(v / self.voxel_volume.to(CUBIC_METER) - ROUNDING))
        if n > len(self.doses):
            raise Error("The volume is larger than the region")
        return self._at_count(n)

    def volume_at_dose(self, dose: AbsorbedDose64) raises -> Volume64:
        """Return the volume of the region that gets a dose or more.

        V20 is `volume_at_dose(AbsorbedDose64(20, GRAY))`.

        Args:
            dose: The dose. Finite.

        Returns:
            The volume of the voxels whose dose is the dose or more.

        Raises:
            Error: If the dose is not finite.
        """
        var d = dose.to(GRAY)
        if not isfinite(d):
            raise Error("A dose-volume dose must be finite")
        return Volume64(
            Float64(self._count_at(d)) * self.voxel_volume.to(CUBIC_METER),
            CUBIC_METER,
        )

    def fraction_at_dose(self, dose: AbsorbedDose64) raises -> Float64:
        """Return the part of the region that gets a dose or more.

        Args:
            dose: The dose. Finite.

        Returns:
            The part, from 0 to 1.

        Raises:
            Error: If the dose is not finite.
        """
        var d = dose.to(GRAY)
        if not isfinite(d):
            raise Error("A dose-volume dose must be finite")
        return Float64(self._count_at(d)) / Float64(len(self.doses))

    def equivalent_uniform_dose(self, a: Float64) raises -> AbsorbedDose64:
        """Return the generalized equivalent uniform dose of Niemierko.

        It is `(mean(d^a))^(1/a)`. A negative `a`, such as -10, weighs the
        cold voxels, as for a tumor. A large `a`, such as 8, weighs the
        hot voxels, as for a serial organ. With `a` of 1, it is the mean.
        With a negative `a`, one voxel of no dose makes it 0.

        Args:
            a: The volume parameter. Finite and not 0.

        Returns:
            The uniform dose that `a` makes equal to the region's doses.

        Raises:
            Error: If `a` is 0 or not finite, or a dose is negative.
        """
        if not isfinite(a) or a == 0:
            raise Error("A gEUD parameter must be finite and not 0")
        if self.doses[len(self.doses) - 1] < 0:
            raise Error("A gEUD needs doses that are not negative")
        var sum = 0.0
        for d in self.doses:  # pragma: no branch
            sum += _power(d, a)
        return AbsorbedDose64(
            _power(sum / Float64(len(self.doses)), 1.0 / a), GRAY
        )

    def curve(self, step: AbsorbedDose64) raises -> List[Float64]:
        """Return the cumulative curve at even steps of dose.

        Point `k` is the part of the region that gets `k` steps of dose
        or more. The curve starts at a dose of 0. It ends at the first
        step past the largest dose, where the part is 0.

        Args:
            step: The step of dose, such as 0.1 Gy. Positive and finite,
                with no more than 100000 steps to the largest dose.

        Returns:
            The part at each step, from 0 to 1.

        Raises:
            Error: If the step is not positive and finite, or makes too
                many points.
        """
        var s = step.to(GRAY)
        if not (s > 0) or not isfinite(s):
            raise Error("A dose step must be positive and finite")
        var top = self.doses[0] / s
        if top >= Float64(MOST_POINTS):
            raise Error("A dose-volume curve has at most 100000 steps")
        var last = max(0, Int(floor(top))) + 1
        var n = len(self.doses)
        var out = List[Float64]()
        for k in range(last + 1):  # pragma: no branch
            var d = Float64(k) * s
            while n > 0 and self.doses[n - 1] < d:
                n -= 1
            out.append(Float64(n) / Float64(len(self.doses)))
        return out^


def dose_volume_histogram(
    dose: ImageVolume, map: LabelMap, label: LabelId
) raises -> DoseVolumeHistogram:
    """Return the dose-volume histogram of a label.

    Args:
        dose: The dose of each voxel, in grays, as `read_rt_dose` gives
            it.
        map: A label map on the grid of the dose, such as
            `structure_labels` fills on it.
        label: The label. Not the background.

    Returns:
        The histogram of the doses of the label's voxels.

    Raises:
        Error: If the label is not valid, is the background or has no
            voxel, or the map is on another grid.
    """
    require_label(label)
    if label == BACKGROUND:
        raise Error("A dose-volume histogram needs a label, not background")
    require_same_grid(map, dose)
    var mark = UInt8(label.value)
    var doses = List[Float64]()
    for at in range(map.count()):  # pragma: no branch
        if map.labels[at] == mark:
            doses.append(Float64(dose.values[at]))
    var voxel = (
        dose.spacing_x.to(METER)
        * dose.spacing_y.to(METER)
        * dose.spacing_z.to(METER)
    )
    return DoseVolumeHistogram(doses^, Volume64(voxel, CUBIC_METER))
