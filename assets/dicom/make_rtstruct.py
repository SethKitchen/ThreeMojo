# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write RT Structure Set fixtures with pydicom, the reference Python library.

    python3 make_rtstruct.py > rtstruct_expected.txt

Run it with pydicom 3.0.1, numpy 2.1.3 and scikit-image 0.26.0.
`rtstruct.dcm` is explicit VR with sequences and items of undefined
length. `rtstruct_implicit.dcm` is implicit VR with defined lengths.
Both hold three regions: GTV, with a contour on each of two slices;
Ring, a square with a square hole; and Marker, with a point and a contour
past the last slice. Each line of the output gives a region's number and
name, and its mask on the grid below, voxel by voxel with i fastest:
scikit-image's points_in_poly at each pixel center, joined by XOR on a
slice.

The grid: 24 by 20 by 4 voxels of 2 by 2.5 mm, slices at z = 0, 3, 6 and
9 mm, the first voxel at (-23, -24, 0) mm, and the axes of the patient.
"""

import numpy
import pydicom
from pydicom.dataset import Dataset, FileMetaDataset
from pydicom.sequence import Sequence
from pydicom.uid import (
    ExplicitVRLittleEndian,
    ImplicitVRLittleEndian,
    RTStructureSetStorage,
)
from skimage.measure import points_in_poly

NX, NY, NZ = 24, 20, 4
ORIGIN = (-23.0, -24.0, 0.0)
SPACING = (2.0, 2.5, 3.0)


def polygon(cx, cy, r, sides, z, turn=0.37):
    angles = numpy.arange(sides) * 2 * numpy.pi / sides + turn
    return [(cx + r * numpy.cos(a), cy + r * numpy.sin(a), z) for a in angles]


def square(cx, cy, half, z):
    return [
        (cx - half, cy - half, z),
        (cx + half, cy - half, z),
        (cx + half, cy + half, z),
        (cx - half, cy + half, z),
    ]


REGIONS = [
    (1, "GTV", [polygon(-3.37, 1.13, 9.0, 9, 3.0), polygon(-1.21, 0.41, 5.5, 7, 6.0)], []),
    (2, "Ring", [square(5.37, -4.11, 11.0, 0.0), square(5.37, -4.11, 4.3, 0.0)], []),
    (3, "Marker", [polygon(0.0, 0.0, 6.0, 5, 30.0)], [[(1.13, 2.27, 6.0)]]),
]


def structure_set(syntax, undefined):
    meta = FileMetaDataset()
    meta.MediaStorageSOPClassUID = RTStructureSetStorage
    meta.MediaStorageSOPInstanceUID = "1.2.826.0.1.3680043.2.1125.11"
    meta.TransferSyntaxUID = syntax
    ds = Dataset()
    ds.file_meta = meta
    ds.SOPClassUID = RTStructureSetStorage
    ds.SOPInstanceUID = meta.MediaStorageSOPInstanceUID
    ds.Modality = "RTSTRUCT"
    ds.StructureSetLabel = "Fixture"
    rois = []
    contours = []
    for number, name, closed, points in REGIONS:
        roi = Dataset()
        roi.ROINumber = number
        roi.ROIName = name
        rois.append(roi)
        item = Dataset()
        item.ReferencedROINumber = number
        sequence = []
        for path in closed:
            c = Dataset()
            c.ContourGeometricType = "CLOSED_PLANAR"
            c.NumberOfContourPoints = len(path)
            c.ContourData = [f"{v:.4f}" for p in path for v in p]
            sequence.append(c)
        for path in points:
            c = Dataset()
            c.ContourGeometricType = "POINT"
            c.NumberOfContourPoints = len(path)
            c.ContourData = [f"{v:.4f}" for p in path for v in p]
            sequence.append(c)
        item.ContourSequence = Sequence(sequence)
        contours.append(item)
    ds.StructureSetROISequence = Sequence(rois)
    ds.ROIContourSequence = Sequence(contours)
    if undefined:
        for keyword in ["StructureSetROISequence", "ROIContourSequence"]:
            element = ds[keyword]
            element.is_undefined_length = True
            for item in element.value:
                item.is_undefined_length_sequence_item = True
        for item in ds.ROIContourSequence:
            element = item["ContourSequence"]
            element.is_undefined_length = True
            for inner in element.value:
                inner.is_undefined_length_sequence_item = True
    return ds


structure_set(ExplicitVRLittleEndian, True).save_as(
    "rtstruct.dcm", enforce_file_format=True
)
structure_set(ImplicitVRLittleEndian, False).save_as(
    "rtstruct_implicit.dcm", enforce_file_format=True
)
read = pydicom.dcmread("rtstruct.dcm")
for roi, item in zip(read.StructureSetROISequence, read.ROIContourSequence):
    mask = numpy.zeros((NZ, NY, NX), dtype=bool)
    for contour in item.ContourSequence:
        if contour.ContourGeometricType != "CLOSED_PLANAR":
            continue
        data = numpy.array([float(v) for v in contour.ContourData]).reshape(-1, 3)
        k = int(numpy.floor((data[:, 2].mean() - ORIGIN[2]) / SPACING[2] + 0.5))
        if k < 0 or k >= NZ:
            continue
        xy = numpy.stack(
            [(data[:, 0] - ORIGIN[0]) / SPACING[0], (data[:, 1] - ORIGIN[1]) / SPACING[1]],
            axis=1,
        )
        j, i = numpy.mgrid[0:NY, 0:NX]
        centers = numpy.stack([i.ravel(), j.ravel()], axis=1).astype(float)
        inside = points_in_poly(centers, xy).reshape(NY, NX)
        mask[k] ^= inside
    bits = "".join("1" if v else "0" for v in mask.ravel())
    print(roi.ROINumber, roi.ROIName, int(mask.sum()), bits)
