# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure eye, dental and tissue fit between visual and canonical parts.

Each function samples visual vertices against an authored canonical
field and returns a `FitReport` of signed distances in meters. A
negative distance is inside the field. The checks measure geometry only:

- `eye_bone_fit`: eyeball vertices against a head bone. A negative
  minimum means the eyeball enters the bone.
- `skin_bone_fit`: fitted scanned-skin vertices against a head bone. A
  negative minimum means the bone stands out of the skin.
- `dental_fit`: scanned `MOUTH` teeth vertices against the authored
  `BONES` teeth. A large maximum means the two dentitions do not
  correspond.

`require_clearance` and `require_containment` turn a report into a
refusal. A passing report is a geometric check of these templates. It
does not validate anatomy, tissue thickness or contact.

This is not a three.js port. See Extensions.
"""

from core.buffer_geometry import POSITION, BufferGeometry
from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.head.bones.dimensions import (
    TEETH as AUTHORED_TEETH,
    HeadBone,
    head_bone_field,
)
from extensions.humanoid.skeleton.head.eyes import eyeball_mesh
from extensions.humanoid.skeleton.head.face_model import FACE_AND_HEAD, TEETH
from extensions.humanoid.skeleton.head.frame import HeadMuscleDimensions
from extensions.humanoid.skeleton.head.skin.dimensions import HeadSkinField
from extensions.humanoid.skeleton.head.skin.mouth import mouth_mesh
from extensions.humanoid.skeleton.head.skin.scan import scan_model
from math.vector3 import Vector3
from units.si import Length, METER, MILLIMETER

# The eyeball mesh detail that fit checks sample.
comptime FIT_EYE_DETAIL = 12


@fieldwise_init
struct FitReport(ImplicitlyCopyable):
    """Signed distances of visual samples from a canonical field.

    Args:
        minimum: The smallest signed distance.
        maximum: The largest signed distance.
        inside: How many samples lie inside or on the field.
        samples: How many samples were measured.

    Returns:
        A fit report.

    Raises:
        None: The fields are plain values.
    """

    var minimum: Length
    """The smallest signed distance; negative is inside."""
    var maximum: Length
    """The largest signed distance."""
    var inside: Int
    """How many samples lie inside or on the field."""
    var samples: Int
    """How many samples were measured."""


def _measure(
    dimensions: HeadMuscleDimensions, bone: HeadBone, points: List[Vector3]
) raises -> FitReport:
    """Measure points against one named head bone's field."""
    var field = head_bone_field(dimensions.head, bone)
    var low = Float32(3.0e38)
    var high = Float32(-3.0e38)
    var inside = 0
    for point in points:  # pragma: no branch
        var distance = field.distance(point)
        low = min(low, distance)
        high = max(high, distance)
        if distance <= 0:
            inside += 1
    return FitReport(
        Length(low, METER), Length(high, METER), inside, len(points)
    )


def _positions(mesh: BufferGeometry) raises -> List[Vector3]:
    """Return every position of a mesh."""
    ref positions = mesh.attribute_view(String(POSITION))
    var points = List[Vector3](capacity=positions.count())
    for vertex in range(positions.count()):  # pragma: no branch
        points.append(positions.vector3(vertex))
    return points^


def eye_bone_fit(
    dimensions: HeadMuscleDimensions, side: BodySide, bone: HeadBone
) raises -> FitReport:
    """Measure one eyeball's vertices against an authored head bone.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        side: `RIGHT` or `LEFT`.
        bone: The named bone, usually `SKULL`.

    Returns:
        Signed distances from the bone. A negative minimum means that the
        eyeball enters the bone.

    Raises:
        Error: If the dimensions, side or bone is refused.
    """
    return _measure(
        dimensions,
        bone,
        _positions(eyeball_mesh(dimensions, side, FIT_EYE_DETAIL)),
    )


def skin_bone_fit(
    dimensions: HeadMuscleDimensions, bone: HeadBone
) raises -> FitReport:
    """Measure the fitted scanned skin against an authored head bone.

    The samples are the scan's skin vertices above its floor, after the
    scan is fitted over the vault and neck hull. The hull does not
    contain every bone, so this check is separate from the fit.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        bone: The named bone, such as `SKULL` or `MANDIBLE`.

    Returns:
        Signed distances from the bone. A negative minimum means that the
        bone stands out of the skin.

    Raises:
        Error: If the dimensions or bone is refused, or the face model
            cannot be read.
    """
    var field = HeadSkinField(dimensions)
    var skin = field.scan.skin(scan_model())
    var points = List[Vector3]()
    for vertex in range(FACE_AND_HEAD.end):  # pragma: no branch
        if skin[vertex].y >= field.scan.floor:
            points.append(skin[vertex])
    return _measure(dimensions, bone, points)


def dental_fit(dimensions: HeadMuscleDimensions) raises -> FitReport:
    """Measure the scanned teeth against the authored teeth.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.

    Returns:
        Signed distances of the scanned `MOUTH` teeth from the authored
        `BONES` teeth. A large maximum means that the two dentitions do
        not correspond.

    Raises:
        Error: If the dimensions are refused or the face model cannot be
            read.
    """
    return _measure(
        dimensions, AUTHORED_TEETH, _positions(mouth_mesh(dimensions, TEETH))
    )


def _millimeters(length: Length) -> String:
    """Return a length as text in millimeters."""
    return String(length.to(MILLIMETER)) + " mm"


def require_clearance(report: FitReport, minimum: Length, what: String) raises:
    """Refuse a fit whose samples come nearer than a clearance.

    Args:
        report: A report from a fit check.
        minimum: The smallest accepted signed distance.
        what: The checked pair, for the error text.

    Raises:
        Error: If the report's minimum is less than `minimum`.
    """
    if report.minimum.value < minimum.value:
        raise Error(
            what
            + " clearance fails: "
            + String(report.samples - report.inside)
            + " of "
            + String(report.samples)
            + " samples clear, minimum "
            + _millimeters(report.minimum)
        )


def require_containment(
    report: FitReport, tolerance: Length, what: String
) raises:
    """Refuse a fit whose samples lie farther outside than a tolerance.

    Args:
        report: A report from a fit check.
        tolerance: The largest accepted signed distance.
        what: The checked pair, for the error text.

    Raises:
        Error: If the report's maximum exceeds `tolerance`.
    """
    if report.maximum.value > tolerance.value:
        raise Error(
            what
            + " correspondence fails: "
            + String(report.inside)
            + " of "
            + String(report.samples)
            + " samples inside, farthest "
            + _millimeters(report.maximum)
        )
