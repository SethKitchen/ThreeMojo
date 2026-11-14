# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A synthetic PET fused over a CT, with the uptake of a lesion measured.

    mojo run -I . examples/fusion.mojo [out/fusion.png]

The page is Medical imaging. The CT is the head phantom on 128 voxels of
1.56 mm. The PET is synthetic, on a coarser grid of 4 mm voxels that is
placed apart from the CT's: the brain takes up a little tracer, and a
lesion of 8 mm radius takes up five times more. A Gaussian of 3 mm
blurs it, as the resolution of a scanner does. The values are in Bq/mL.

`suv_factor` turns them into SUV, for a patient of 70 kg injected with
370 MBq of fluorine-18 an hour before the scan. `resample_onto` brings
the SUV onto the CT's grid. A threshold at 40 percent of the largest SUV
labels the lesion, and `suv_statistics` measures it.

The left panel is the CT, the middle panel the SUV alone, and the right
panel the SUV fused over the CT with `overlay_values`, from SUV 2 to 8,
with the lesion's outline in green. The brain's own uptake, near SUV
1.7, stays below the overlay.

This is a picture of a synthetic volume, for teaching. It is not a
diagnosis.
"""

from extensions.imaging.contour import draw_outlines, slice_outlines
from extensions.imaging.dicom import MEGABECQUEREL, PetDose
from extensions.imaging.filter import gaussian_filter
from extensions.imaging.fusion import overlay_values
from extensions.imaging.ids import K_AXIS, LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import keep_largest, threshold
from extensions.imaging.overlay import render_slice, zoom_image
from extensions.imaging.phantom import phantom_value, shepp_logan
from extensions.imaging.resample import resample_onto
from extensions.imaging.suv import (
    GRAM_PER_BECQUEREL,
    suv_factor,
    suv_statistics,
    suv_volume,
)
from extensions.imaging.transfer import Rgba
from extensions.sdf.vector import distance, v3
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.pathlib import Path
from tools._example_output import blit, example_destination
from units.si import (
    Duration64,
    GRAM_PER_CUBIC_CENTIMETER,
    KILOGRAM,
    Length64,
    Mass64,
    METER,
    SECOND,
)

comptime DEFAULT_OUTPUT = "out/fusion.png"
comptime SIZE = 128
comptime ZOOM = 3
comptime PANEL = SIZE * ZOOM
comptime PET_SIZE = 52
# The lesion's center, in meters from the patient origin.
comptime LESION_X = 0.045
comptime LESION_Y = -0.04
comptime LESION_Z = 0.0


def _pet() raises -> ImageVolume:
    """Return the synthetic PET in Bq/mL, on its own grid of 4 mm."""
    var step = Length64(4.0, MILLIMETER64)
    var pet = ImageVolume(PET_SIZE, PET_SIZE, PET_SIZE, step, step, step)
    var corner = -0.5 * Float64(PET_SIZE - 1) * 0.004 + 0.0013
    pet.origin = v3(corner, corner - 0.0007, corner)
    var lesion = v3(LESION_X, LESION_Y, LESION_Z)
    for k in range(PET_SIZE):
        for j in range(PET_SIZE):
            for i in range(PET_SIZE):
                var p = pet.patient_point(Float64(i), Float64(j), Float64(k))
                # The phantom spans -1 to 1 over a field of 200 mm.
                var tissue = phantom_value(p.x / 0.1, p.y / 0.1, p.z / 0.1)
                var activity = 0.0
                if tissue > 0.1 and tissue < 0.5:
                    activity = 6000.0
                if distance(p, lesion) <= 0.008:
                    activity = 30000.0
                pet.set(i, j, k, Float32(activity))
    return gaussian_filter(pet, Length64(3.0, MILLIMETER64))


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var ct = shepp_logan(SIZE, Length64(200.0, MILLIMETER64), 2)
    var dose = PetDose()
    dose.units = "BQML"
    dose.decay_correction = "START"
    dose.patient_weight = Mass64(70, KILOGRAM)
    dose.injected_dose = type_of(dose.injected_dose)(370, MEGABECQUEREL)
    dose.half_life = Duration64(6586.2, SECOND)
    dose.injection_time = Duration64(9 * 3600, SECOND)
    dose.series_time = Duration64(10 * 3600, SECOND)
    dose.has_injection_time = True
    dose.has_series_time = True
    var factor = suv_factor(dose)
    var suv = resample_onto(suv_volume(_pet(), factor), ct, 0)
    var top = Float64(suv.value_range()[1])
    var lesion = keep_largest(
        threshold(suv, 0.4 * top, 1.0e9, LabelId(1)), LabelId(1)
    )
    var uptake = suv_statistics(suv, lesion, LabelId(1))
    # The axial slice through the lesion's center.
    var middle = Int(ct.voxel_point(v3(LESION_X, LESION_Y, LESION_Z)).z + 0.5)
    var anatomy = zoom_image(render_slice(ct, K_AXIS, middle), ZOOM)
    suv.window_center = 4
    suv.window_width = 8
    var alone = zoom_image(render_slice(suv, K_AXIS, middle), ZOOM)
    var fused = zoom_image(render_slice(ct, K_AXIS, middle), ZOOM)
    overlay_values(fused, suv, K_AXIS, middle, 2.0, 8.0, 0.75, ZOOM)
    draw_outlines(
        fused,
        K_AXIS,
        slice_outlines(lesion, LabelId(1), K_AXIS, middle),
        ZOOM,
        Rgba(0.3, 1, 0.4, 1),
    )
    var sheet = Framebuffer(3 * PANEL, PANEL, Color(0, 0, 0))
    blit(sheet, anatomy, 0, 0)
    blit(sheet, alone, PANEL, 0)
    blit(sheet, fused, 2 * PANEL, 0)
    Path(destination).write_bytes(encode(sheet))
    print("SUV factor:", factor.to(GRAM_PER_BECQUEREL), "g/Bq")
    print(
        "Lesion:",
        lesion.voxels(LabelId(1)),
        "voxels; SUVmax",
        uptake.maximum.to(GRAM_PER_CUBIC_CENTIMETER),
        "SUVmean",
        uptake.mean.to(GRAM_PER_CUBIC_CENTIMETER),
        "SUVpeak",
        uptake.peak.to(GRAM_PER_CUBIC_CENTIMETER),
    )
    print("Wrote", destination)
