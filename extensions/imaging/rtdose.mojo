# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read a DICOM RT Dose file into a volume of absorbed dose, in grays.

A radiotherapy plan gives its dose as an RT Dose file: a grid of frames,
one plane each. A stored value times the dose grid scaling is a dose in
grays. `parse_rt_dose` reads the file into an `ImageVolume` whose values
are grays:

| Tag | Element | Use |
|---|---|---|
| (0008,0060) | Modality | must be `RTDOSE` |
| (3004,0002) | Dose Units | must be `GY` |
| (0028,0010) and (0028,0011) | Rows and Columns | the plane |
| (0028,0008) | Number of Frames | the planes, one when absent |
| (0028,0100) and (0028,0101) | Bits Allocated and Bits Stored | 16 or 32, the same |
| (0028,0103) | Pixel Representation | unsigned or signed |
| (0020,0032) | Image Position (Patient) | the first voxel, in mm |
| (0020,0037) | Image Orientation (Patient) | the row and column directions |
| (0028,0030) | Pixel Spacing | between rows, then between columns, in mm |
| (3004,000C) | Grid Frame Offset Vector | the place of each frame, in mm |
| (3004,000E) | Dose Grid Scaling | grays per stored value |
| (3004,0004) | Dose Type | `dose_type`, such as `PHYSICAL` |
| (3004,000A) | Dose Summation Type | `summation`, such as `PLAN` |
| (7FE0,0010) | Pixel Data | native, little endian |

The frames are along the normal of the rows and columns. When the first
offset is 0, each offset is the distance of its frame from the image
position. When it is not 0, each offset is the z of its frame. Then the
first offset must be the z of the image position, and the frames must
be axial. The frames must be evenly spaced. When they go down along the
normal, the reader turns them over, so that `k` rises along it.
"""

from extensions.imaging.dicom import (
    DicomTree,
    parse_dicom_tree,
    read_dicom_tree,
    unit_direction,
)
from extensions.imaging.ids import DATA_SET
from extensions.imaging.image_volume import ImageVolume
from extensions.sdf.vector import V3, cross, dot, length, v3
from std.math import floor
from units.quantity import Quantity, Unit
from units.si import METER, MILLIMETER64, Length64

# An absorbed dose: energy per mass. The gray is one joule per kilogram.
comptime AbsorbedDose64 = Quantity[2, 0, -2, 0, 0, DType.float64]
comptime GRAY = Unit[2, 0, -2, 0, 0, DType.float64](1.0, "Gy")
comptime CENTIGRAY = Unit[2, 0, -2, 0, 0, DType.float64](0.01, "cGy")
# Directions are units, square and axial, and a first offset is the z of
# the position, to this much.
comptime TOLERANCE = 1.0e-3
# The gaps between frames agree when they differ by less than this
# fraction.
comptime SPACING_TOLERANCE = 0.01


struct RtDose(Copyable, Movable):
    """The dose of an RT Dose file, and how it was summed."""

    var dose: ImageVolume
    """The dose of each voxel, in grays, placed in patient space."""
    var dose_type: String
    """The Dose Type, such as `PHYSICAL` or `EFFECTIVE`."""
    var summation: String
    """The Dose Summation Type, such as `PLAN`, `FRACTION` or `BEAM`."""

    def __init__(
        out self, var dose: ImageVolume, dose_type: String, summation: String
    ):
        """Create a dose.

        Args:
            dose: The dose of each voxel, in grays.
            dose_type: The Dose Type.
            summation: The Dose Summation Type.
        """
        self.dose = dose^
        self.dose_type = dose_type
        self.summation = summation


def _short(tree: DicomTree, tag: Int, name: String) raises -> Int:
    """Read one unsigned 16-bit value of the data set."""
    var data = tree.data(DATA_SET, tag)
    if len(data) != 2:
        raise Error("An RT dose needs one value of its " + name)
    return Int(data[0]) | (Int(data[1]) << 8)


def _values(
    tree: DicomTree, tag: Int, count: Int, name: String
) raises -> List[Float64]:
    """Read the decimal values of an element of the data set."""
    var values = tree.numbers(DATA_SET, tag)
    if len(values) != count:
        raise Error(
            "An RT dose needs " + String(count) + " values of its " + name
        )
    return values^


def _rt_dose(tree: DicomTree) raises -> RtDose:
    """Read the dose of a parsed RT Dose file."""
    if tree.text(DATA_SET, 0x00080060) != "RTDOSE":
        raise Error("The file is not an RT Dose")
    if tree.text(DATA_SET, 0x30040002) != "GY":
        raise Error("An RT dose must be in GY, not relative")
    var rows = _short(tree, 0x00280010, "rows")
    var columns = _short(tree, 0x00280011, "columns")
    var bits = _short(tree, 0x00280100, "bits allocated")
    if bits != 16 and bits != 32:
        raise Error("An RT dose stores 16 or 32 bits a value")
    if _short(tree, 0x00280101, "bits stored") != bits:
        raise Error("An RT dose stores every bit that it allocates")
    var signed = _short(tree, 0x00280103, "pixel representation")
    if signed > 1:
        raise Error("An RT dose pixel representation is 0 or 1")
    var frames = 1
    if tree.has(DATA_SET, 0x00280008):
        var n = _values(tree, 0x00280008, 1, "number of frames")[0]
        if not (n >= 1) or n != floor(n):
            raise Error("An RT dose needs a whole number of frames")
        frames = Int(n)
    var scaling = _values(tree, 0x3004000E, 1, "dose grid scaling")[0]
    if not (scaling > 0):
        raise Error("An RT dose grid scaling must be positive")
    var position = _values(tree, 0x00200032, 3, "image position")
    var orientation = _values(tree, 0x00200037, 6, "image orientation")
    var spacing = _values(tree, 0x00280030, 2, "pixel spacing")
    if not (spacing[0] > 0) or not (spacing[1] > 0):
        raise Error("An RT dose pixel spacing must be positive")
    var row = unit_direction(orientation, 0, "An RT dose orientation")
    var column = unit_direction(orientation, 3, "An RT dose orientation")
    if abs(dot(row, column)) > TOLERANCE:
        raise Error("An RT dose orientation needs square directions")
    var normal = cross(row, column)
    var mm = Length64(1.0, MILLIMETER64).to(METER)
    var origin = v3(position[0] * mm, position[1] * mm, position[2] * mm)
    # One frame takes the gap between columns as its depth.
    var gap = spacing[1]
    var turn = False
    if frames > 1:
        var offsets = _values(tree, 0x3004000C, frames, "grid frame offsets")
        var first = offsets[0]
        if first != 0:
            # The offsets are the z of the frames.
            if (
                abs(first - position[2]) > TOLERANCE
                or length(row - v3(1, 0, 0)) > TOLERANCE
                or length(column - v3(0, 1, 0)) > TOLERANCE
            ):
                raise Error(
                    "RT dose offsets that do not start at 0 need axial frames"
                    " that start at the z of the position"
                )
        gap = offsets[1] - first
        if not (abs(gap) > 0):
            raise Error("Two frames of an RT dose share one place")
        for k in range(1, frames):  # pragma: no branch
            var step = offsets[k] - offsets[k - 1]
            if abs(step - gap) > SPACING_TOLERANCE * abs(gap):
                raise Error("The frames of an RT dose are not evenly spaced")
        if gap < 0:
            turn = True
            origin = origin + normal * ((offsets[frames - 1] - first) * mm)
            gap = -gap
    var pixels = tree.data(DATA_SET, 0x7FE00010)
    var plane = rows * columns
    var size = bits // 8
    if len(pixels) != plane * frames * size:
        raise Error("The pixel data of an RT dose does not fill its grid")
    var volume = ImageVolume(
        columns,
        rows,
        frames,
        Length64(spacing[1], MILLIMETER64),
        Length64(spacing[0], MILLIMETER64),
        Length64(gap, MILLIMETER64),
    )
    volume.origin = origin
    volume.axis_x = row
    volume.axis_y = column
    volume.axis_z = normal
    var half = 1 << (bits - 1)
    # The volume refuses an empty grid, so each loop runs.
    for f in range(frames):  # pragma: no branch
        var k = f
        if turn:
            k = frames - 1 - f
        for index in range(plane):  # pragma: no branch
            var at = (f * plane + index) * size
            var value = Int(pixels[at]) | (Int(pixels[at + 1]) << 8)
            if bits == 32:
                value |= (Int(pixels[at + 2]) << 16) | (
                    Int(pixels[at + 3]) << 24
                )
            if signed == 1 and value >= half:
                value -= 2 * half
            volume.values[k * plane + index] = Float32(Float64(value) * scaling)
    volume.fit_window()
    return RtDose(
        volume^,
        tree.text(DATA_SET, 0x30040004),
        tree.text(DATA_SET, 0x3004000A),
    )


def parse_rt_dose(bytes: Span[UInt8, _]) raises -> RtDose:
    """Read the dose of an RT Dose file.

    Args:
        bytes: The whole Part 10 file.

    Returns:
        The dose in grays, with `k` rising along the normal of the
        frames.

    Raises:
        Error: If `parse_dicom_tree` refuses the file, its modality is not
            `RTDOSE`, its dose is not in `GY`, an element is missing or
            out of range, the frames are not evenly spaced, or the pixel
            data does not fill the grid.
    """
    return _rt_dose(parse_dicom_tree(bytes))


def read_rt_dose(path: String) raises -> RtDose:
    """Read the dose of an RT Dose file from disk.

    Args:
        path: The file.

    Returns:
        The dose in grays, with `k` rising along the normal of the
        frames.

    Raises:
        Error: If the file cannot be read, or `parse_rt_dose` refuses it.
    """
    return _rt_dose(read_dicom_tree(path))
