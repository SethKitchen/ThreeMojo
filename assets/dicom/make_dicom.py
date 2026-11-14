# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write compressed DICOM fixtures with pydicom, the reference Python library.

    python3 make_dicom.py > expected.txt

Run it with pydicom 3.0.1 and numpy 2.1.3. Each file holds one CT slice.
`tests/test_imaging_dicom.mojo` reads them and compares its values with
the ones that pydicom prints: every stored pixel value, row by row.
"""

import numpy
import pydicom
from pydicom.dataset import Dataset, FileMetaDataset
from pydicom.uid import (
    CTImageStorage,
    DeflatedExplicitVRLittleEndian,
    ExplicitVRLittleEndian,
    RLELossless,
)


def slice_of(pixels, signed):
    meta = FileMetaDataset()
    meta.MediaStorageSOPClassUID = CTImageStorage
    meta.MediaStorageSOPInstanceUID = "1.2.826.0.1.3680043.2.1125.7"
    meta.TransferSyntaxUID = ExplicitVRLittleEndian
    ds = Dataset()
    ds.file_meta = meta
    ds.SOPClassUID = CTImageStorage
    ds.SOPInstanceUID = meta.MediaStorageSOPInstanceUID
    ds.Modality = "CT"
    ds.Rows, ds.Columns = pixels.shape
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    ds.BitsAllocated = pixels.dtype.itemsize * 8
    ds.BitsStored = ds.BitsAllocated
    ds.HighBit = ds.BitsStored - 1
    ds.PixelRepresentation = 1 if signed else 0
    ds.RescaleSlope = "1"
    ds.RescaleIntercept = "0"
    ds.PixelSpacing = ["0.5", "0.75"]
    ds.ImagePositionPatient = ["-10", "20", "5"]
    ds.ImageOrientationPatient = ["1", "0", "0", "0", "1", "0"]
    ds.PixelData = pixels.tobytes()
    return ds


rows = numpy.arange(12, dtype=numpy.int16).reshape(3, 4)
signed = (rows * 997 - 3000).astype(numpy.int16)
# Long runs, to reach the repeat code of the run-length encoding.
signed[2, :] = -2
image = slice_of(signed, True)
image.compress(RLELossless, encoding_plugin="pydicom")
image.save_as("rle16.dcm", enforce_file_format=True)

small = numpy.array(
    [[0, 0, 0, 0, 0], [1, 2, 3, 4, 5], [255, 255, 7, 7, 7], [9, 8, 7, 6, 5]],
    dtype=numpy.uint8,
)
image = slice_of(small, False)
image.compress(RLELossless, encoding_plugin="pydicom")
image.save_as("rle8.dcm", enforce_file_format=True)

image = slice_of(signed, True)
image.file_meta.TransferSyntaxUID = DeflatedExplicitVRLittleEndian
image.save_as("deflated.dcm", enforce_file_format=True)

for name in ["rle16.dcm", "rle8.dcm", "deflated.dcm"]:
    read = pydicom.dcmread(name)
    values = " ".join(str(int(v)) for v in read.pixel_array.flatten())
    print(name, read.file_meta.TransferSyntaxUID, values)
