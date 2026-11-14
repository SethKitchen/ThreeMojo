# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the regions of label maps as a DICOM RT Structure Set.

Planning systems, 3D Slicer and DVH tools read regions as an RT Structure
Set. `label_structure(map, volume, label, number, name)` turns a label
into closed planar contours: its outlines on each slice of `k`, as
`slice_outlines` traces them, in patient space. A point on the straight
run between its two neighbors is left out, so the contours keep their
shape with fewer points. `encode_rt_structures` writes regions as a
Part 10 file:

| Tag | Element | Value |
|---|---|---|
| (0008,0016) and (0008,0018) | SOP Class and SOP Instance UID | RT Structure Set Storage, and `root.3` |
| (0008,0060) | Modality | `RTSTRUCT` |
| (0020,000D) and (0020,000E) | Study and Series Instance UID | `root.1` and `root.2` |
| (3006,0002) | Structure Set Label | `label` |
| (3006,0010) | Referenced Frame of Reference Sequence | the frame of reference |
| (3006,0020) | Structure Set ROI Sequence | each region's number, frame of reference and name |
| (3006,0039) | ROI Contour Sequence | each region's contours, `CLOSED_PLANAR`, in mm |
| (3006,0080) | RT ROI Observations Sequence | one observation of each region |

The patient's name and ID, the date, the time, the generation algorithm
and the interpreted type are empty. `structure_labels` fills each region
of the file back on the volume's grid, voxel for voxel.
"""

from extensions.imaging.contour import slice_outlines
from extensions.imaging.dicom_write import DicomWriter, ds_text
from extensions.imaging.ids import (
    EXPLICIT_LITTLE,
    IMPLICIT_LITTLE,
    K_AXIS,
    LabelId,
    TransferSyntax,
)
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap, require_same_grid
from extensions.imaging.rtstruct import RtStructure
from extensions.sdf.vector import V3
from units.si import Length64, METER

comptime RT_STRUCTURE_SET_STORAGE = "1.2.840.10008.5.1.4.1.1.481.3"
# The longest value of an explicit VR text element, in bytes.
comptime LONGEST_SHORT_VALUE = 65534


def _straight(before: V3, point: V3, after: V3) -> Bool:
    """Return whether a point is on the straight run between two others."""
    var ax = point.x - before.x
    var ay = point.y - before.y
    var bx = after.x - point.x
    var by = after.y - point.y
    return ax * by - ay * bx == 0 and ax * bx + ay * by > 0


def label_structure(
    map: LabelMap,
    volume: ImageVolume,
    label: LabelId,
    number: Int,
    name: String,
) raises -> RtStructure:
    """Return the outlines of a label on each slice as a region.

    Args:
        map: The label map.
        volume: The volume that places the map in patient space, on the
            same grid.
        label: The label. Not the background.
        number: The ROI number of the region.
        name: The ROI name, such as `GTV`.

    Returns:
        The region, with one closed contour for each outline and each
        hole, from the first slice to the last.

    Raises:
        Error: If the map and the volume differ in grid, or
            `slice_outlines` refuses the label.
    """
    require_same_grid(map, volume)
    var out = RtStructure(number, name)
    for k in range(map.nz):  # pragma: no branch
        for outline in slice_outlines(map, label, K_AXIS, k):
            var points = List[V3]()
            var n = len(outline.points)
            # An outline closes around a pixel, so it has four points.
            for a in range(n):  # pragma: no branch
                ref p = outline.points[a]
                if _straight(
                    outline.points[(a + n - 1) % n],
                    p,
                    outline.points[(a + 1) % n],
                ):
                    continue
                points.append(volume.patient_point(p.x, p.y, p.z))
            out.contours.append(points^)
    return out^


def _require_uid(uid: String, most: Int, name: String) raises:
    """Refuse a UID that is empty, too long or not digits and dots."""
    var bytes = uid.as_bytes()
    if len(bytes) == 0 or len(bytes) > most:
        raise Error(
            "A " + name + " UID has 1 to " + String(most) + " characters"
        )
    var start = 0
    for at in range(len(bytes) + 1):  # pragma: no branch
        if at == len(bytes) or bytes[at] == 46:
            var size = at - start
            if size == 0 or (size > 1 and bytes[start] == 48):
                raise Error(
                    "A " + name + " UID has an empty part or a leading zero"
                )
            start = at + 1
        elif bytes[at] < 48 or bytes[at] > 57:
            raise Error("A " + name + " UID holds digits and dots only")


def _contour_text(contour: List[V3]) raises -> String:
    """Return the x, y and z of each point in mm, split by backslashes."""
    var mm = Length64(1.0, MILLIMETER64).to(METER)
    var text = String("")
    for p in range(len(contour)):  # pragma: no branch
        if p > 0:
            text += "\\"
        ref point = contour[p]
        text += ds_text(point.x / mm) + "\\" + ds_text(point.y / mm)
        text += "\\" + ds_text(point.z / mm)
    return text^


def encode_rt_structures(
    structures: List[RtStructure],
    root: String,
    frame_of_reference: String,
    label: String,
    syntax: TransferSyntax = IMPLICIT_LITTLE,
) raises -> List[UInt8]:
    """Write regions as an RT Structure Set file.

    Args:
        structures: The regions, one or more, each with its own ROI
            number.
        root: The UID root of the file, such as `2.25.` and a number. The
            study, the series and the instance are `root.1`, `root.2`
            and `root.3`. At most 62 characters.
        frame_of_reference: The Frame of Reference UID of the CT that
            the regions are on.
        label: The Structure Set Label, from 1 to 16 characters.
        syntax: Implicit VR little endian, the default, or explicit VR
            little endian. Explicit VR holds at most 65534 bytes of
            contour text in one contour.

    Returns:
        The whole Part 10 file.

    Raises:
        Error: If there is no region, two regions share a number, a name
            or the label is too long or holds a backslash, a UID or the
            syntax is not valid, a contour has fewer than three points or
            a point that `ds_text` refuses, or a contour is too long for
            explicit VR.
    """
    if len(structures) == 0:
        raise Error("An RT Structure Set needs one region or more")
    _require_uid(root, 62, "root")
    _require_uid(frame_of_reference, 64, "frame of reference")
    if len(label.as_bytes()) == 0 or len(label.as_bytes()) > 16:
        raise Error("A structure set label has 1 to 16 characters")
    if syntax != IMPLICIT_LITTLE and syntax != EXPLICIT_LITTLE:
        raise Error("An RT Structure Set is written in implicit or explicit VR")
    var names = List[String]()
    names.append(label)
    for a in range(len(structures)):  # pragma: no branch
        if len(structures[a].name.as_bytes()) > 64:
            raise Error("An ROI name has at most 64 characters")
        names.append(structures[a].name)
        for b in range(a):
            if structures[b].number == structures[a].number:
                raise Error("Two regions share one ROI number")
    for n in names:  # pragma: no branch
        if "\\" in n:
            raise Error("A structure set label or name holds no backslash")
    # The text of each contour, checked before the file is begun.
    var texts = List[List[String]]()
    for s in structures:  # pragma: no branch
        var contours = List[String]()
        for c in s.contours:
            if len(c) < 3:
                raise Error("A closed contour needs three points or more")
            var text = _contour_text(c)
            if (
                syntax == EXPLICIT_LITTLE
                and len(text.as_bytes()) > LONGEST_SHORT_VALUE
            ):
                raise Error("A contour is too long for explicit VR")
            contours.append(text^)
        texts.append(contours^)
    var instance = root + ".3"
    var w = DicomWriter(syntax, RT_STRUCTURE_SET_STORAGE, instance)
    w.uid(0x0008, 0x0016, RT_STRUCTURE_SET_STORAGE)
    w.uid(0x0008, 0x0018, instance)
    w.text(0x0008, 0x0060, "CS", "RTSTRUCT")
    w.text(0x0008, 0x0070, "LO", "ThreeMojo")
    w.text(0x0010, 0x0010, "PN", "")
    w.text(0x0010, 0x0020, "LO", "")
    w.uid(0x0020, 0x000D, root + ".1")
    w.uid(0x0020, 0x000E, root + ".2")
    w.text(0x0020, 0x0011, "IS", "1")
    w.text(0x3006, 0x0002, "SH", label)
    w.text(0x3006, 0x0008, "DA", "")
    w.text(0x3006, 0x0009, "TM", "")
    w.open_sequence(0x3006, 0x0010)
    w.open_item()
    w.uid(0x0020, 0x0052, frame_of_reference)
    w.close_item()
    w.close_sequence()
    w.open_sequence(0x3006, 0x0020)
    for s in structures:  # pragma: no branch
        w.open_item()
        w.text(0x3006, 0x0022, "IS", String(s.number))
        w.uid(0x3006, 0x0024, frame_of_reference)
        w.text(0x3006, 0x0026, "LO", s.name)
        w.text(0x3006, 0x0036, "CS", "")
        w.close_item()
    w.close_sequence()
    w.open_sequence(0x3006, 0x0039)
    for r in range(len(structures)):  # pragma: no branch
        w.open_item()
        w.open_sequence(0x3006, 0x0040)
        for c in range(len(texts[r])):
            w.open_item()
            w.text(0x3006, 0x0042, "CS", "CLOSED_PLANAR")
            w.text(0x3006, 0x0046, "IS", String(len(structures[r].contours[c])))
            w.text(0x3006, 0x0050, "DS", texts[r][c])
            w.close_item()
        w.close_sequence()
        w.text(0x3006, 0x0084, "IS", String(structures[r].number))
        w.close_item()
    w.close_sequence()
    w.open_sequence(0x3006, 0x0080)
    for r in range(len(structures)):  # pragma: no branch
        w.open_item()
        w.text(0x3006, 0x0082, "IS", String(r + 1))
        w.text(0x3006, 0x0084, "IS", String(structures[r].number))
        w.text(0x3006, 0x00A4, "CS", "")
        w.text(0x3006, 0x00A6, "PN", "")
        w.close_item()
    w.close_sequence()
    return w^.finish()
