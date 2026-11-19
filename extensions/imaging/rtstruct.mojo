# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read the regions of a DICOM RT Structure Set, and fill them in a grid.

Radiotherapy plans and many research data sets give their regions, such
as a tumor and the organs at risk, as an RT Structure Set: polygons on
the slices of a CT, in patient space. `parse_rt_structures` reads one:

| Tag | Element | Field |
|---|---|---|
| (3006,0020) | Structure Set ROI Sequence | each region |
| (3006,0022) | ROI Number | `number` |
| (3006,0026) | ROI Name | `name` |
| (3006,0039) | ROI Contour Sequence | the contours of each region |
| (3006,0084) | Referenced ROI Number | the region of the contours |
| (3006,0040) | Contour Sequence | each contour |
| (3006,0042) | Contour Geometric Type | only `CLOSED_PLANAR` is kept |
| (3006,0050) | Contour Data | x, y and z of each point, in mm |

`structure_labels` fills the contours of a region in a label map on a
volume's grid. A contour belongs to the slice nearest its points. A
pixel is inside when its center is inside an odd number of the
region's contours on its slice, so a contour inside another makes a
hole, as most planning systems draw one.
"""

from extensions.imaging.dicom import (
    DicomTree,
    parse_dicom_tree,
    read_dicom_tree,
)
from extensions.imaging.ids import (
    BACKGROUND,
    DATA_SET,
    LabelId,
    require_label,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap
from extensions.sdf.vector import V3, v3
from std.collections import Dict
from std.math import ceil, floor, max, min
from units.si import METER, MILLIMETER64, Length64


struct RtStructure(Copyable, Movable):
    """One region of an RT Structure Set."""

    var number: Int
    """The ROI number."""
    var name: String
    """The ROI name, such as `GTV` or `Heart`."""
    var contours: List[List[V3]]
    """The closed planar contours, each a list of points in patient space,
    in meters. The last point joins the first."""

    def __init__(out self, number: Int, name: String):
        """Create a region without contours.

        Args:
            number: The ROI number.
            name: The ROI name.
        """
        self.number = number
        self.name = name
        self.contours = List[List[V3]]()


def _structures(tree: DicomTree) raises -> List[RtStructure]:
    """Read the regions of a parsed RT Structure Set."""
    if tree.text(DATA_SET, 0x00080060) != "RTSTRUCT":
        raise Error("The file is not an RT Structure Set")
    var out = List[RtStructure]()
    var places = Dict[Int, Int]()
    for item in tree.items(DATA_SET, 0x30060020):
        var numbers = tree.numbers(item, 0x30060022)
        if len(numbers) != 1:
            raise Error("An RT structure needs one ROI number")
        var number = Int(numbers[0])
        places[number] = len(out)
        out.append(RtStructure(number, tree.text(item, 0x30060026)))
    var mm = Length64(1.0, MILLIMETER64).to(METER)
    for item in tree.items(DATA_SET, 0x30060039):
        var reference = tree.numbers(item, 0x30060084)
        if len(reference) != 1 or Int(reference[0]) not in places:
            raise Error("An RT contour refers to no structure")
        var at = places[Int(reference[0])]
        for contour in tree.items(item, 0x30060040):
            if tree.text(contour, 0x30060042) != "CLOSED_PLANAR":
                continue
            var data = tree.numbers(contour, 0x30060050)
            if len(data) < 9 or len(data) % 3 != 0:
                raise Error("A closed RT contour needs three points or more")
            var points = List[V3]()
            for p in range(0, len(data), 3):  # pragma: no branch
                points.append(
                    v3(data[p] * mm, data[p + 1] * mm, data[p + 2] * mm)
                )
            out[at].contours.append(points^)
    return out^


def parse_rt_structures(bytes: Span[UInt8, _]) raises -> List[RtStructure]:
    """Read the regions of an RT Structure Set file.

    Args:
        bytes: The whole Part 10 file.

    Returns:
        The regions, in the order of the Structure Set ROI Sequence.

    Raises:
        Error: If `parse_dicom_tree` refuses the file, its modality is not
            `RTSTRUCT`, a region has not one ROI number, a contour refers
            to no region, or a closed contour has fewer than three points
            or a partial point.
    """
    return _structures(parse_dicom_tree(bytes))


def read_rt_structures(path: String) raises -> List[RtStructure]:
    """Read the regions of an RT Structure Set file from disk.

    Args:
        path: The file.

    Returns:
        The regions, in the order of the Structure Set ROI Sequence.

    Raises:
        Error: If the file cannot be read, or `parse_rt_structures`
            refuses it.
    """
    return _structures(read_dicom_tree(path))


def structure_labels(
    structure: RtStructure, volume: ImageVolume, label: LabelId
) raises -> LabelMap:
    """Return a map that gives a label to the inside of a region.

    Args:
        structure: The region.
        volume: The volume whose grid and placement the map takes, such
            as the CT that the structure set refers to.
        label: The label. Not the background.

    Returns:
        The map. A contour whose nearest slice is outside the volume, or
        of fewer than three points, adds nothing.

    Raises:
        Error: If the label is not valid or is the background.
    """
    require_label(label)
    if label == BACKGROUND:
        raise Error("A structure needs a label other than the background")
    var out = LabelMap(volume)
    var mark = UInt8(label.value)
    # The contours of each slice, in voxel units.
    var slices = Dict[Int, List[Int]]()
    var xs = List[List[Float64]]()
    var ys = List[List[Float64]]()
    for c in range(len(structure.contours)):
        # A contour of fewer than three points closes no area.
        if len(structure.contours[c]) < 3:
            continue
        var px = List[Float64]()
        var py = List[Float64]()
        var depth = 0.0
        for p in structure.contours[c]:  # pragma: no branch
            var q = volume.voxel_point(p)
            px.append(q.x)
            py.append(q.y)
            depth += q.z
        var k = Int(floor(depth / Float64(len(px)) + 0.5))
        if k < 0 or k >= volume.nz:
            continue
        if k not in slices:
            slices[k] = List[Int]()
        slices[k].append(len(xs))
        xs.append(px^)
        ys.append(py^)
    for entry in slices.items():
        var k = entry.key
        ref members = entry.value
        var low_x = Float64(volume.nx)
        var high_x = -1.0
        var low_y = Float64(volume.ny)
        var high_y = -1.0
        for m in members:  # pragma: no branch
            for n in range(len(xs[m])):  # pragma: no branch
                low_x = min(low_x, xs[m][n])
                high_x = max(high_x, xs[m][n])
                low_y = min(low_y, ys[m][n])
                high_y = max(high_y, ys[m][n])
        var i0 = max(0, Int(ceil(low_x)))
        var i1 = min(volume.nx - 1, Int(floor(high_x)))
        var j0 = max(0, Int(ceil(low_y)))
        var j1 = min(volume.ny - 1, Int(floor(high_y)))
        for j in range(j0, j1 + 1):
            var y = Float64(j)
            for i in range(i0, i1 + 1):
                var x = Float64(i)
                var inside = False
                for m in members:  # pragma: no branch
                    var n = len(xs[m])
                    for a in range(n):  # pragma: no branch
                        var b = (a + n - 1) % n
                        var ya = ys[m][a]
                        var yb = ys[m][b]
                        if (ya > y) != (yb > y):
                            var cross = xs[m][a] + (y - ya) * (
                                xs[m][b] - xs[m][a]
                            ) / (yb - ya)
                            if x < cross:
                                inside = not inside
                if inside:
                    out.labels[out.index(i, j, k)] = mark
    return out^
