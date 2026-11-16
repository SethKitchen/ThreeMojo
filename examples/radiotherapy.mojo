# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A synthetic radiotherapy dose over a CT, and the DVH of its regions.

    mojo run -I . examples/radiotherapy.mojo [out/radiotherapy.png]

The page is Medical imaging. The CT is the head phantom on 128 voxels of
1.56 mm. Two regions are drawn as contours on its slices, as an RT
Structure Set gives them: a target of 15 mm radius, and an organ at risk
of 10 mm radius, 5 mm from the target.

The dose is synthetic, on a grid of 3 mm voxels placed apart from the
CT's. Five beams in the axial plane cross at the target. Each beam is a
square field 40 mm wide, with an edge of 2.5 mm, and falls off by 0.5
percent a millimeter of depth. The dose is scaled so that the target's
mean is 60 Gy. It is written as an RT Dose file in memory and read back
with `parse_rt_dose`, as from a planning system.

The left panel is the axial slice through the target, with the dose on
the hot scale from 6 to 70 Gy. The white line is the 57 Gy isodose, 95
percent of the prescription, and the pink line is the 30 Gy isodose. The
target is outlined in green and the organ at risk in blue. The right
panel is the DVH of the two regions: dose from 0 to 70 Gy, with a gray
line each 10 Gy, and the part of each region from 0 to 100 percent.

This is a picture of a synthetic plan, for teaching. It is not a
treatment plan.
"""

from extensions.imaging.contour import (
    draw_outlines,
    slice_isolines,
    slice_outlines,
)
from extensions.imaging.dicom_write import DicomWriter
from extensions.imaging.dvh import (
    DoseVolumeHistogram,
    dose_volume_histogram,
    dvh_image,
)
from extensions.imaging.fusion import overlay_values
from extensions.imaging.ids import (
    EXPLICIT_LITTLE,
    K_AXIS,
    LabelId,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap
from extensions.imaging.overlay import render_slice, zoom_image
from extensions.imaging.phantom import phantom_value, shepp_logan
from extensions.imaging.resample import resample_onto
from extensions.imaging.rtdose import AbsorbedDose64, GRAY, parse_rt_dose
from extensions.imaging.rtstruct import RtStructure, structure_labels
from extensions.imaging.transfer import Rgba
from extensions.sdf.vector import V3, dot, v3
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.math import cos, exp, pi, sin, sqrt
from std.pathlib import Path
from tools._example_output import blit, example_destination
from units.si import CUBIC_CENTIMETER64, MILLIMETER64, Length64, Volume64

comptime DEFAULT_OUTPUT = "out/radiotherapy.png"
comptime SIZE = 128
comptime ZOOM = 3
comptime PANEL = SIZE * ZOOM
comptime DOSE_SIZE = 68
comptime BEAMS = 5
comptime PRESCRIPTION = 60.0
# The scale of a stored dose value, in grays.
comptime SCALING = 1.0e-5


def _target_center() -> V3:
    return v3(0.040, -0.035, 0.004)


def _organ_center() -> V3:
    return v3(0.010, -0.044, 0.004)


def _sphere(
    number: Int, name: String, center: V3, radius: Float64, ct: ImageVolume
) -> RtStructure:
    """Return a ball as a structure: a circle of 48 points on each CT
    slice that cuts it."""
    var out = RtStructure(number, name)
    for k in range(ct.nz):
        var z = ct.patient_point(0, 0, Float64(k)).z
        var dz = z - center.z
        if abs(dz) >= radius:
            continue
        var r = sqrt(radius * radius - dz * dz)
        var contour = List[V3]()
        for n in range(48):
            var a = 2.0 * pi * Float64(n) / 48.0
            contour.append(v3(center.x + r * cos(a), center.y + r * sin(a), z))
        out.contours.append(contour^)
    return out^


def _edge(x: Float64) -> Float64:
    """Return the field's edge: 1 inside and 0 outside, over 2.5 mm."""
    return 1.0 / (1.0 + exp(-x / 0.0025))


def _raw_dose() raises -> ImageVolume:
    """Return the unscaled dose of five beams, on its own 3 mm grid."""
    var step = Length64(3.0, MILLIMETER64)
    var dose = ImageVolume(DOSE_SIZE, DOSE_SIZE, DOSE_SIZE, step, step, step)
    var corner = -0.5 * Float64(DOSE_SIZE - 1) * 0.003 + 0.0011
    dose.origin = v3(corner, corner + 0.0007, corner - 0.0004)
    var target = _target_center()
    var directions = List[V3]()
    for b in range(BEAMS):
        var angle = 2.0 * pi * (Float64(b) + 0.05) / Float64(BEAMS)
        directions.append(v3(cos(angle), sin(angle), 0.0))
    for k in range(DOSE_SIZE):
        for j in range(DOSE_SIZE):
            for i in range(DOSE_SIZE):
                var p = dose.patient_point(Float64(i), Float64(j), Float64(k))
                # The phantom spans -1 to 1 over a field of 200 mm.
                if phantom_value(p.x / 0.1, p.y / 0.1, p.z / 0.1) <= 0.05:
                    continue
                var d = p - target
                var sum = 0.0
                for b in range(BEAMS):
                    ref beam = directions[b]
                    var across = v3(-beam.y, beam.x, 0.0)
                    var depth = 0.09 + dot(d, beam)
                    var field = _edge(0.020 - abs(dot(d, across))) * _edge(
                        0.020 - abs(d.z)
                    )
                    sum += field * exp(-5.0 * depth)
                dose.set(i, j, k, Float32(sum))
    return dose^


def _rt_dose_file(dose: ImageVolume) raises -> List[UInt8]:
    """Return a dose in grays as a 32-bit RT Dose file, in memory."""
    var w = DicomWriter(EXPLICIT_LITTLE)
    w.text(0x0008, 0x0060, "CS", "RTDOSE")
    var mm = 1000.0
    w.numbers(
        0x0020,
        0x0032,
        [dose.origin.x * mm, dose.origin.y * mm, dose.origin.z * mm],
    )
    w.numbers(0x0020, 0x0037, [1.0, 0.0, 0.0, 0.0, 1.0, 0.0])
    w.text(0x0028, 0x0008, "IS", String(dose.nz))
    w.short(0x0028, 0x0010, dose.ny)
    w.short(0x0028, 0x0011, dose.nx)
    w.numbers(0x0028, 0x0030, [3.0, 3.0])
    w.short(0x0028, 0x0100, 32)
    w.short(0x0028, 0x0101, 32)
    w.short(0x0028, 0x0103, 0)
    w.text(0x3004, 0x0002, "CS", "GY")
    w.text(0x3004, 0x0004, "CS", "PHYSICAL")
    w.text(0x3004, 0x000A, "CS", "PLAN")
    var offsets = List[Float64]()
    for k in range(dose.nz):
        offsets.append(3.0 * Float64(k))
    w.numbers(0x3004, 0x000C, offsets)
    w.text(0x3004, 0x000E, "DS", "1E-05")
    var data = List[UInt8]()
    for value in dose.values:
        var stored = Int(Float64(value) / SCALING + 0.5)
        for b in range(4):
            data.append(UInt8((stored >> (8 * b)) & 0xFF))
    w.binary(0x7FE0, 0x0010, "OW", data)
    return w^.finish()


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var ct = shepp_logan(SIZE, Length64(200.0, MILLIMETER64), 2)
    var target = structure_labels(
        _sphere(1, "Target", _target_center(), 0.015, ct), ct, LabelId(1)
    )
    var organ = structure_labels(
        _sphere(2, "Organ", _organ_center(), 0.010, ct), ct, LabelId(1)
    )
    # Scale the dose so that the target's mean is the prescription.
    var raw = _raw_dose()
    var first = dose_volume_histogram(
        resample_onto(raw, ct, 0), target, LabelId(1)
    )
    var scale = PRESCRIPTION / first.mean().to(GRAY)
    for v in range(raw.count()):
        raw.values[v] = Float32(Float64(raw.values[v]) * scale)
    var plan = parse_rt_dose(_rt_dose_file(raw))
    var dose = resample_onto(plan.dose, ct, 0)
    var tumor = dose_volume_histogram(dose, target, LabelId(1))
    var risk = dose_volume_histogram(dose, organ, LabelId(1))
    # The axial slice through the target's center.
    var middle = Int(ct.voxel_point(_target_center()).z + 0.5)
    var green = Rgba(0.15, 0.75, 0.25, 1)
    var blue = Rgba(0.2, 0.55, 1.0, 1)
    var wash = zoom_image(render_slice(ct, K_AXIS, middle), ZOOM)
    overlay_values(wash, dose, K_AXIS, middle, 6.0, 70.0, 0.6, ZOOM)
    draw_outlines(
        wash,
        K_AXIS,
        slice_isolines(dose, K_AXIS, middle, 0.95 * PRESCRIPTION),
        ZOOM,
        Rgba(1, 1, 1, 1),
    )
    draw_outlines(
        wash,
        K_AXIS,
        slice_isolines(dose, K_AXIS, middle, 30.0),
        ZOOM,
        Rgba(1, 0.45, 0.85, 1),
    )
    draw_outlines(
        wash,
        K_AXIS,
        slice_outlines(target, LabelId(1), K_AXIS, middle),
        ZOOM,
        green,
    )
    draw_outlines(
        wash,
        K_AXIS,
        slice_outlines(organ, LabelId(1), K_AXIS, middle),
        ZOOM,
        blue,
    )
    var histograms = List[DoseVolumeHistogram]()
    histograms.append(tumor.copy())
    histograms.append(risk.copy())
    var plot = dvh_image(
        histograms,
        [green, blue],
        AbsorbedDose64(70, GRAY),
        AbsorbedDose64(10, GRAY),
        PANEL,
        PANEL,
    )
    var sheet = Framebuffer(2 * PANEL, PANEL, Color(0, 0, 0))
    blit(sheet, wash, 0, 0)
    blit(sheet, plot, PANEL, 0)
    Path(destination).write_bytes(encode(sheet))
    print(
        "Target:",
        tumor.count(),
        "voxels,",
        tumor.volume().to(CUBIC_CENTIMETER64),
        "cm^3; D95",
        tumor.dose_at_fraction(0.95).to(GRAY),
        "Gy, D2",
        tumor.dose_at_fraction(0.02).to(GRAY),
        "Gy, gEUD(-10)",
        tumor.equivalent_uniform_dose(-10.0).to(GRAY),
        "Gy",
    )
    print(
        "Organ at risk:",
        risk.count(),
        "voxels; mean",
        risk.mean().to(GRAY),
        "Gy, D0.03cc",
        risk.dose_at_volume(Volume64(0.03, CUBIC_CENTIMETER64)).to(GRAY),
        "Gy, V30",
        risk.volume_at_dose(AbsorbedDose64(30, GRAY)).to(CUBIC_CENTIMETER64),
        "cm^3, gEUD(8)",
        risk.equivalent_uniform_dose(8.0).to(GRAY),
        "Gy",
    )
    print("Wrote", destination)
