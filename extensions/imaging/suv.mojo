# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Standardized uptake values of a PET image.

A PET image stores the activity concentration `C` of the tracer, in
Bq/mL. The standardized uptake value (SUV) divides it by the injected
activity per gram of body weight:

    SUV = C W / A

with `W` the body weight in grams and `A` the injected activity at the
time the image is corrected to. A tracer spread evenly through the whole
body gives an SUV of 1 g/mL everywhere.

`suv_factor` reads `W / A` from the `PetDose` of a PET file. The values
must be in `BQML`. With the decay correction `START`, the scanner
corrected the image to the start of the series, so the injected activity
decays from the injection time to the series time:

    A = A0 2^(-(t_series - t_injection) / T_half)

A series time before the injection time means that midnight passed, and
a day is added. With `ADMIN` the image is corrected to the injection, so
`A` is `A0`.

`suv_volume` multiplies a volume of Bq/mL by the factor. `suv_statistics`
gives the largest SUV of a label, its mean, and its SUVpeak: the largest
mean of a sphere of 1 mL centered on a voxel of the label. The sphere
holds every voxel whose center is within its radius, in the label or
not. PERCIST, the PET Response Criteria in Solid Tumors, uses SUVpeak.
"""

from extensions.imaging.dicom import BECQUEREL, PetDose
from extensions.imaging.ids import BACKGROUND, LabelId, require_label
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, require_same_grid
from std.math import ceil, isfinite, pi, sqrt
from units.quantity import Quantity, Unit
from units.si import Density64, GRAM_PER_CUBIC_CENTIMETER, METER, SECOND

# The body weight per injected activity that turns Bq/mL into g/mL.
comptime SuvFactor64 = Quantity[0, 1, 1, 0, 0, DType.float64]
comptime GRAM_PER_BECQUEREL = Unit[0, 1, 1, 0, 0, DType.float64](0.001, "g/Bq")
# The radius of a sphere of 1 mL, in meters: (3 / (4 pi))^(1/3) cm.
comptime PEAK_RADIUS = 0.006203504908994
comptime SECONDS_PER_DAY = 86400.0


def suv_factor(dose: PetDose) raises -> SuvFactor64:
    """Return the factor from Bq/mL to body-weight SUV in g/mL.

    Args:
        dose: The PET elements of the image, from `DicomSlice.pet`.

    Returns:
        The patient's weight over the injected activity at the time the
        image is corrected to.

    Raises:
        Error: If the values are not in `BQML`, the decay correction is
            not `START` or `ADMIN`, the weight or the dose is not positive,
            or, with `START`, the half-life is not positive or a time is
            absent.
    """
    if dose.units != "BQML":
        raise Error("An SUV needs values in BQML")
    var start = dose.decay_correction == "START"
    if not start and dose.decay_correction != "ADMIN":
        raise Error("An SUV needs values decay corrected to START or ADMIN")
    var grams = dose.patient_weight.value * 1000.0
    if not (grams > 0) or not isfinite(grams):
        raise Error("An SUV needs the patient's weight")
    var activity = dose.injected_dose.to(BECQUEREL)
    if not (activity > 0) or not isfinite(activity):
        raise Error("An SUV needs the injected dose")
    if start:
        var half = dose.half_life.to(SECOND)
        if not (half > 0) or not isfinite(half):
            raise Error("An SUV needs the half-life of the radionuclide")
        if not dose.has_series_time or not dose.has_injection_time:
            raise Error("An SUV needs the series time and the injection time")
        var elapsed = dose.series_time.to(SECOND) - dose.injection_time.to(
            SECOND
        )
        if elapsed < 0:
            elapsed += SECONDS_PER_DAY
        activity *= 2.0 ** (-elapsed / half)
    return SuvFactor64(grams / activity, GRAM_PER_BECQUEREL)


def suv_volume(volume: ImageVolume, factor: SuvFactor64) raises -> ImageVolume:
    """Return a volume of Bq/mL as SUV, in g/mL.

    Args:
        volume: The PET volume, in Bq/mL.
        factor: The factor from `suv_factor`.

    Returns:
        A copy with each value times the factor, and its window fitted.

    Raises:
        Error: If the factor is not positive and finite.
    """
    var f = factor.to(GRAM_PER_BECQUEREL)
    if not (f > 0) or not isfinite(f):
        raise Error("An SUV factor must be positive and finite")
    var out = volume.copy()
    for index in range(out.count()):  # pragma: no branch
        out.values[index] = Float32(Float64(volume.values[index]) * f)
    out.fit_window()
    return out^


@fieldwise_init
struct SuvStatistics(Copyable, Movable):
    """The SUV of one label."""

    var maximum: Density64
    """The largest SUV of a voxel of the label."""
    var mean: Density64
    """The mean SUV of the label."""
    var peak: Density64
    """The largest mean of a sphere of 1 mL centered in the label."""
    var peak_voxel: Tuple[Int, Int, Int]
    """The voxel `(i, j, k)` at the center of that sphere."""


def suv_statistics(
    suv: ImageVolume, map: LabelMap, label: LabelId
) raises -> SuvStatistics:
    """Return the largest, the mean and the peak SUV of a label.

    Of two spheres with one mean, the one centered on the voxel with the
    lower index counts.

    Args:
        suv: The volume of SUV, in g/mL, from `suv_volume`.
        map: Its label map.
        label: The label. Not the background.

    Returns:
        The statistics.

    Raises:
        Error: If the grids differ, the label is not valid or is the
            background, or the label has no voxels.
    """
    require_same_grid(map, suv)
    require_label(label)
    if label == BACKGROUND:
        raise Error("SUV statistics need a label other than the background")
    var mark = UInt8(label.value)
    var sx = map.spacing_x.to(METER)
    var sy = map.spacing_y.to(METER)
    var sz = map.spacing_z.to(METER)
    # The voxel offsets of the sphere.
    var reach_i = Int(ceil(PEAK_RADIUS / sx))
    var reach_j = Int(ceil(PEAK_RADIUS / sy))
    var reach_k = Int(ceil(PEAK_RADIUS / sz))
    var offsets = List[Int]()
    for dk in range(-reach_k, reach_k + 1):  # pragma: no branch
        for dj in range(-reach_j, reach_j + 1):  # pragma: no branch
            for di in range(-reach_i, reach_i + 1):  # pragma: no branch
                var d = sqrt(
                    (Float64(di) * sx) ** 2
                    + (Float64(dj) * sy) ** 2
                    + (Float64(dk) * sz) ** 2
                )
                if d <= PEAK_RADIUS:
                    offsets.append(di)
                    offsets.append(dj)
                    offsets.append(dk)
    var count = 0
    var total = 0.0
    var largest = 0.0
    var peak = 0.0
    var center = -1
    for index in range(map.count()):  # pragma: no branch
        if map.labels[index] != mark:
            continue
        var value = Float64(suv.values[index])
        if count == 0 or value > largest:
            largest = value
        count += 1
        total += value
        var i = index % map.nx
        var j = (index // map.nx) % map.ny
        var k = index // (map.nx * map.ny)
        var sum = 0.0
        var held = 0
        for o in range(0, len(offsets), 3):  # pragma: no branch
            var x = i + offsets[o]
            var y = j + offsets[o + 1]
            var z = k + offsets[o + 2]
            if map.contains(x, y, z):
                sum += Float64(suv.values[map.index(x, y, z)])
                held += 1
        var mean = sum / Float64(held)
        if center < 0 or mean > peak:
            peak = mean
            center = index
    if count == 0:
        raise Error("The label has no voxels")
    return SuvStatistics(
        Density64(largest, GRAM_PER_CUBIC_CENTIMETER),
        Density64(total / Float64(count), GRAM_PER_CUBIC_CENTIMETER),
        Density64(peak, GRAM_PER_CUBIC_CENTIMETER),
        (
            center % map.nx,
            (center // map.nx) % map.ny,
            center // (map.nx * map.ny),
        ),
    )
