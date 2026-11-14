# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write RT Dose fixtures with pydicom, the reference Python library.

    python3 make_rtdose.py > rtdose_expected.txt

Run it with pydicom 3.0.1 and numpy 2.1.3, beside `rtstruct_expected.txt`.
Both files hold one smooth dose on the grid of the structure fixtures:
24 by 20 by 4 voxels of 2 by 2.5 by 3 mm, slices at z = 0, 3, 6 and 9 mm,
the first voxel at (-23, -24, 0) mm, and the axes of the patient.

`rtdose.dcm` is explicit VR, 32-bit, with relative frame offsets that
rise: 0, 3, 6 and 9 mm. `rtdose_implicit.dcm` is implicit VR, 16-bit,
with the frames from z = 9 mm down to 0 and offsets that are the z of
each frame: 9, 6, 3 and 0 mm.

For each file, the output gives the dose of each voxel in Gy, as 32-bit
floats, with i fastest and k from z = 0. Then it gives the dose-volume
histogram of each region of `rtstruct_expected.txt` on that grid:
the voxel count, the least, mean and largest dose, D98, D95, D50 and
D2, V20 and V40 in cm^3, D for 0.03 and 0.1 cm^3, and the gEUD at
a = -10 and a = 5. A dose at a fraction or a volume is the least dose of the hottest
voxels that reach it, to 1e-9 of a voxel.
"""

import math

import numpy
import pydicom
from pydicom.dataset import Dataset, FileMetaDataset
from pydicom.uid import (
    ExplicitVRLittleEndian,
    ImplicitVRLittleEndian,
    RTDoseStorage,
)

NX, NY, NZ = 24, 20, 4
ORIGIN = (-23.0, -24.0, 0.0)
SPACING = (2.0, 2.5, 3.0)
ROUNDING = 1e-9


def dose_field():
    """Return a smooth dose with noise, in Gy, as [k, j, i]."""
    rng = numpy.random.default_rng(1078)
    k, j, i = numpy.mgrid[0:NZ, 0:NY, 0:NX]
    x = ORIGIN[0] + i * SPACING[0]
    y = ORIGIN[1] + j * SPACING[1]
    z = ORIGIN[2] + k * SPACING[2]
    r2 = ((x - 1.0) ** 2 + (y + 2.0) ** 2) / (2 * 9.0**2) + (z - 4.0) ** 2 / (2 * 7.0**2)
    dose = 62.0 * numpy.exp(-r2) + rng.uniform(0.0, 1.5, size=r2.shape)
    return dose


def dose_file(syntax, bits, scaling, descending):
    meta = FileMetaDataset()
    meta.MediaStorageSOPClassUID = RTDoseStorage
    meta.MediaStorageSOPInstanceUID = f"1.2.826.0.1.3680043.2.1125.{bits}"
    meta.TransferSyntaxUID = syntax
    ds = Dataset()
    ds.file_meta = meta
    ds.SOPClassUID = RTDoseStorage
    ds.SOPInstanceUID = meta.MediaStorageSOPInstanceUID
    ds.Modality = "RTDOSE"
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    ds.Rows = NY
    ds.Columns = NX
    ds.NumberOfFrames = NZ
    ds.FrameIncrementPointer = 0x3004000C
    ds.PixelSpacing = [SPACING[1], SPACING[0]]
    ds.ImageOrientationPatient = [1, 0, 0, 0, 1, 0]
    ds.BitsAllocated = bits
    ds.BitsStored = bits
    ds.HighBit = bits - 1
    ds.PixelRepresentation = 0
    ds.DoseUnits = "GY"
    ds.DoseType = "PHYSICAL"
    ds.DoseSummationType = "PLAN"
    ds.DoseGridScaling = scaling
    zs = [ORIGIN[2] + k * SPACING[2] for k in range(NZ)]
    field = dose_field()
    if descending:
        zs = zs[::-1]
        field = field[::-1]
        ds.GridFrameOffsetVector = [f"{z:g}" for z in zs]
    else:
        ds.GridFrameOffsetVector = [f"{z - zs[0]:g}" for z in zs]
    ds.ImagePositionPatient = [ORIGIN[0], ORIGIN[1], zs[0]]
    kind = numpy.uint32 if bits == 32 else numpy.uint16
    ds.PixelData = numpy.round(field / float(scaling)).astype(kind).tobytes()
    return ds


def masks():
    out = []
    with open("rtstruct_expected.txt") as f:
        for line in f:
            number, name, count, bits = line.split()
            mask = numpy.array([b == "1" for b in bits]).reshape(NZ, NY, NX)
            out.append((name, mask))
    return out


def at_count(doses, count):
    """Return the least dose of the hottest `count` voxels."""
    return doses[min(max(count, 1), len(doses)) - 1]


def report(path):
    read = pydicom.dcmread(path)
    scaling = float(read.DoseGridScaling)
    dose = (read.pixel_array.astype(numpy.float64) * scaling).astype(numpy.float32)
    offsets = [float(v) for v in read.GridFrameOffsetVector]
    if offsets[0] != 0:
        offsets = [v - offsets[0] for v in offsets]
    if offsets[1] < 0:
        dose = dose[::-1]
    print("values", " ".join(repr(float(v)) for v in dose.ravel()))
    voxel = SPACING[0] * SPACING[1] * SPACING[2] / 1000.0
    for name, mask in masks():
        if not mask.any():
            continue
        doses = numpy.sort(dose[mask].astype(numpy.float64))[::-1]
        n = len(doses)
        values = [doses[-1], doses.mean(), doses[0]]
        for fraction in [0.98, 0.95, 0.5, 0.02]:
            values.append(at_count(doses, math.ceil(fraction * n - ROUNDING)))
        for level in [20.0, 40.0]:
            values.append(int(numpy.sum(doses >= level)) * voxel)
        for volume in [0.03, 0.1]:
            values.append(at_count(doses, math.ceil(volume / voxel - ROUNDING)))
        for a in [-10.0, 5.0]:
            values.append(float(numpy.mean(doses**a)) ** (1.0 / a))
        line = [name, str(n)] + [repr(float(v)) for v in values]
        print("dvh", " ".join(line))


dose_file(ExplicitVRLittleEndian, 32, "1.7E-05", False).save_as(
    "rtdose.dcm", enforce_file_format=True
)
dose_file(ImplicitVRLittleEndian, 16, "0.001", True).save_as(
    "rtdose_implicit.dcm", enforce_file_format=True
)
for path in ["rtdose.dcm", "rtdose_implicit.dcm"]:
    print("file", path)
    report(path)
