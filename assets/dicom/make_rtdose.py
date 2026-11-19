# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write RT Dose fixtures with pydicom, the reference Python library.

    mojo run -I . tools/make_rtdose.mojo
    cd assets/dicom && python3 make_rtdose.py > rtdose_expected.txt

Run it with pydicom 3.0.1 and numpy 2.1.3. `tools/make_rtdose.mojo` writes
the synthetic dose, `rtdose_field.txt`. Both files hold that dose on the
grid of the structure fixtures:
24 by 20 by 4 voxels of 2 by 2.5 by 3 mm, slices at z = 0, 3, 6 and 9 mm,
the first voxel at (-23, -24, 0) mm, and the axes of the patient.

`rtdose.dcm` is explicit VR, 32-bit, with relative frame offsets that
rise: 0, 3, 6 and 9 mm. `rtdose_implicit.dcm` is implicit VR, 16-bit,
with the frames from z = 9 mm down to 0 and offsets that are the z of
each frame: 9, 6, 3 and 0 mm.

For each file, the output gives the dose of each voxel in Gy that
pydicom reads, as 32-bit floats, with i fastest and k from z = 0. No
library gives the dose-volume histogram with these definitions, so the
Mojo tests take its measures from these doses and the regions of
`rtstruct_expected.txt` by their closed forms.
"""


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


def dose_field():
    """Return the dose of `tools/make_rtdose.mojo`, in Gy, as [k, j, i]."""
    with open("rtdose_field.txt") as data:
        values = [float(line) for line in data if line.strip()]
    return numpy.array(values).reshape(NZ, NY, NX)


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


dose_file(ExplicitVRLittleEndian, 32, "1.7E-05", False).save_as(
    "rtdose.dcm", enforce_file_format=True
)
dose_file(ImplicitVRLittleEndian, 16, "0.001", True).save_as(
    "rtdose_implicit.dcm", enforce_file_format=True
)
for path in ["rtdose.dcm", "rtdose_implicit.dcm"]:
    print("file", path)
    report(path)
