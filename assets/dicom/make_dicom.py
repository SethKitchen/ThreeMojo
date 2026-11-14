# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write compressed DICOM fixtures with pydicom, the reference Python library.

    python3 make_dicom.py > expected.txt

Run it with pydicom 3.0.1 and numpy 2.1.3. The first three files hold one
CT slice each. The two enhanced files hold three frames each, with their
placement in shared and per-frame functional groups. The tests read
them and compare their values with the ones that pydicom prints: every
stored pixel value, frame by frame and row by row.
"""

import numpy
import pydicom
from pydicom.dataset import Dataset, FileMetaDataset
from pydicom.sequence import Sequence
from pydicom.uid import (
    CTImageStorage,
    DeflatedExplicitVRLittleEndian,
    EnhancedCTImageStorage,
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
image.compress(
    RLELossless, encoding_plugin="pydicom", generate_instance_uid=False
)
image.save_as("rle16.dcm", enforce_file_format=True)

small = numpy.array(
    [[0, 0, 0, 0, 0], [1, 2, 3, 4, 5], [255, 255, 7, 7, 7], [9, 8, 7, 6, 5]],
    dtype=numpy.uint8,
)
image = slice_of(small, False)
image.compress(
    RLELossless, encoding_plugin="pydicom", generate_instance_uid=False
)
image.save_as("rle8.dcm", enforce_file_format=True)

image = slice_of(signed, True)
image.file_meta.TransferSyntaxUID = DeflatedExplicitVRLittleEndian
image.save_as("deflated.dcm", enforce_file_format=True)


def enhanced(frames):
    """An enhanced CT of several frames, with functional groups."""
    count, rows, columns = frames.shape
    meta = FileMetaDataset()
    meta.MediaStorageSOPClassUID = EnhancedCTImageStorage
    meta.MediaStorageSOPInstanceUID = "1.2.826.0.1.3680043.2.1125.8"
    meta.TransferSyntaxUID = ExplicitVRLittleEndian
    ds = Dataset()
    ds.file_meta = meta
    ds.SOPClassUID = EnhancedCTImageStorage
    ds.SOPInstanceUID = meta.MediaStorageSOPInstanceUID
    ds.Modality = "CT"
    ds.Rows, ds.Columns = rows, columns
    ds.NumberOfFrames = count
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    ds.BitsAllocated = 16
    ds.BitsStored = 16
    ds.HighBit = 15
    ds.PixelRepresentation = 1
    measures = Dataset()
    measures.PixelSpacing = ["0.5", "0.75"]
    measures.SliceThickness = "2.5"
    orientation = Dataset()
    orientation.ImageOrientationPatient = ["1", "0", "0", "0", "1", "0"]
    transform = Dataset()
    transform.RescaleIntercept = "-1024"
    transform.RescaleSlope = "2"
    transform.RescaleType = "HU"
    shared = Dataset()
    shared.PixelMeasuresSequence = Sequence([measures])
    shared.PlaneOrientationSequence = Sequence([orientation])
    shared.PixelValueTransformationSequence = Sequence([transform])
    ds.SharedFunctionalGroupsSequence = Sequence([shared])
    per_frame = []
    for k in range(count):
        position = Dataset()
        position.ImagePositionPatient = ["-10", "20", str(5 + 2.5 * k)]
        window = Dataset()
        window.WindowCenter = "40"
        window.WindowWidth = str(400 + 100 * k)
        item = Dataset()
        item.PlanePositionSequence = Sequence([position])
        item.FrameVOILUTSequence = Sequence([window])
        per_frame.append(item)
    ds.PerFrameFunctionalGroupsSequence = Sequence(per_frame)
    ds.PixelData = frames.tobytes()
    return ds


stack = (numpy.arange(3 * 4 * 5, dtype=numpy.int16).reshape(3, 4, 5) * 37 - 900)
stack[1, 2, :] = 77
image = enhanced(stack)
image.save_as("enhanced.dcm", enforce_file_format=True)
image = enhanced(stack)
image.compress(
    RLELossless, encoding_plugin="pydicom", generate_instance_uid=False
)
image.save_as("enhanced_rle.dcm", enforce_file_format=True)

for name in ["rle16.dcm", "rle8.dcm", "deflated.dcm"]:
    read = pydicom.dcmread(name)
    values = " ".join(str(int(v)) for v in read.pixel_array.flatten())
    print(name, read.file_meta.TransferSyntaxUID, values)
for name in ["enhanced.dcm", "enhanced_rle.dcm"]:
    read = pydicom.dcmread(name)
    values = " ".join(str(int(v)) for v in read.pixel_array.flatten())
    print(name, read.file_meta.TransferSyntaxUID, values)
