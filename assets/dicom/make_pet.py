# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write PET DICOM fixtures with pydicom, the reference Python library.

    python3 make_pet.py > pet_expected.txt

Run it with pydicom 3.0.1 and numpy 2.1.3. Each file holds one PET slice
with the elements that standardized uptake values need. `pet.dcm` is
explicit VR, with the Radiopharmaceutical Information Sequence of
undefined length. `pet_implicit.dcm` is implicit VR, with the sequence of
defined length. Each line of the output gives a file, the elements as
pydicom reads them, the SUV factor in g/Bq, and the rescaled values.

The factor is the body-weight SUV of the decay-corrected image:
    weight in grams / (dose * 2 ** (-(series - injection) / half-life))
"""

import numpy
import pydicom
from pydicom.dataset import Dataset, FileMetaDataset
from pydicom.sequence import Sequence
from pydicom.uid import (
    ExplicitVRLittleEndian,
    ImplicitVRLittleEndian,
    PositronEmissionTomographyImageStorage,
)


def seconds(tm):
    """Return the seconds after midnight of a DICOM time."""
    whole, _, fraction = tm.partition(".")
    value = int(whole[0:2]) * 3600 + int(whole[2:4]) * 60 + int(whole[4:6])
    return value + (float("0." + fraction) if fraction else 0.0)


def pet_slice(syntax, defined):
    meta = FileMetaDataset()
    meta.MediaStorageSOPClassUID = PositronEmissionTomographyImageStorage
    meta.MediaStorageSOPInstanceUID = "1.2.826.0.1.3680043.2.1125.9"
    meta.TransferSyntaxUID = syntax
    ds = Dataset()
    ds.file_meta = meta
    ds.SOPClassUID = PositronEmissionTomographyImageStorage
    ds.SOPInstanceUID = meta.MediaStorageSOPInstanceUID
    ds.Modality = "PT"
    ds.PatientWeight = "72.5"
    ds.SeriesTime = "101500.25"
    ds.Units = "BQML"
    ds.DecayCorrection = "START"
    code = Dataset()
    code.CodeValue = "C-111A1"
    code.CodingSchemeDesignator = "SRT"
    code.CodeMeaning = "^18^Fluorine"
    item = Dataset()
    item.Radiopharmaceutical = "Fluorodeoxyglucose"
    item.RadionuclideCodeSequence = Sequence([code])
    item.RadiopharmaceuticalStartTime = "091200"
    item.RadionuclideTotalDose = "370000000"
    item.RadionuclideHalfLife = "6586.2"
    ds.RadiopharmaceuticalInformationSequence = Sequence([item])
    if not defined:
        sequence = ds["RadiopharmaceuticalInformationSequence"]
        sequence.is_undefined_length = True
        sequence.value[0].is_undefined_length_sequence_item = True
    pixels = (numpy.arange(12, dtype=numpy.uint16).reshape(3, 4) * 1000 + 7)
    ds.Rows, ds.Columns = pixels.shape
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    ds.BitsAllocated = 16
    ds.BitsStored = 16
    ds.HighBit = 15
    ds.PixelRepresentation = 0
    ds.RescaleSlope = "2.5"
    ds.RescaleIntercept = "0"
    ds.PixelSpacing = ["4.0", "4.0"]
    ds.SliceThickness = "3.0"
    ds.ImagePositionPatient = ["-300", "-300", "-120"]
    ds.ImageOrientationPatient = ["1", "0", "0", "0", "1", "0"]
    ds.PixelData = pixels.tobytes()
    return ds


pet_slice(ExplicitVRLittleEndian, False).save_as(
    "pet.dcm", enforce_file_format=True
)
pet_slice(ImplicitVRLittleEndian, True).save_as(
    "pet_implicit.dcm", enforce_file_format=True
)
for name in ["pet.dcm", "pet_implicit.dcm"]:
    read = pydicom.dcmread(name)
    item = read.RadiopharmaceuticalInformationSequence[0]
    elapsed = seconds(read.SeriesTime) - seconds(item.RadiopharmaceuticalStartTime)
    dose = float(item.RadionuclideTotalDose)
    half = float(item.RadionuclideHalfLife)
    decayed = dose * 2.0 ** (-elapsed / half)
    factor = float(read.PatientWeight) * 1000.0 / decayed
    values = read.pixel_array.astype(float) * float(read.RescaleSlope)
    print(
        name,
        read.Units,
        read.DecayCorrection,
        float(read.PatientWeight),
        seconds(read.SeriesTime),
        seconds(item.RadiopharmaceuticalStartTime),
        dose,
        half,
        repr(factor),
        " ".join(repr(float(v)) for v in values.flatten()),
    )
