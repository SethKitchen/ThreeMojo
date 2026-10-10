# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Arteries and veins of the neck and the head, as implicit solids.

The common carotid artery rises from the root of the neck beside the
trachea and forks at the level of the hyoid. The internal carotid runs
on up to the base of the skull; the external carotid gives the facial
artery, which crosses the jaw in front of the masseter, and ends as the
superficial temporal artery in front of the ear. The vertebral artery
climbs through the cervical transverse processes and loops over the
atlas into the skull. The internal jugular vein runs down beside the
carotid to the subclavian vein; the external jugular vein runs down
across the sternocleidomastoid. Every vessel is paired.

Each vessel is a tube along a spline through template points in the
torso's frame, on the right; the left is its mirror image. Radii are
authored in template centimeters. They are not a cited lumen table.

    var dims = head_muscle_dimensions(person)
    var d = head_vessel_distance(dims, COMMON_CAROTID_ARTERY, RIGHT, p)
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.head.frame import HeadMuscleDimensions
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    append_template_tube,
)
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
    floats,
)
from math.vector3 import Vector3


@fieldwise_init
struct HeadVessel(Equatable, ImplicitlyCopyable, Writable):
    """Which artery or vein of the neck and the head a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named vessels is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named vessel."""
        if self.value < 0:
            return False
        return self.value <= VERTEBRAL_ARTERY.value


comptime COMMON_CAROTID_ARTERY = HeadVessel(0)
comptime INTERNAL_CAROTID_ARTERY = HeadVessel(1)
comptime EXTERNAL_CAROTID_ARTERY = HeadVessel(2)
comptime INTERNAL_JUGULAR_VEIN = HeadVessel(3)
comptime EXTERNAL_JUGULAR_VEIN = HeadVessel(4)
comptime VERTEBRAL_ARTERY = HeadVessel(5)


def is_head_artery(part: HeadVessel) raises -> Bool:
    """Return True if `part` carries arterial blood.

    Args:
        part: A named vessel.

    Returns:
        False for the two jugular veins, and True for the rest.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A head vessel must be a named artery or vein")
    return not (part == INTERNAL_JUGULAR_VEIN or part == EXTERNAL_JUGULAR_VEIN)


def head_vessel_label(part: HeadVessel) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A head vessel, named or not.

    Returns:
        A short American English label, or `"head vessel"` when `part`
        is not named.
    """
    var labels: List[String] = [
        "common carotid artery",
        "internal carotid artery",
        "external carotid artery",
        "internal jugular vein",
        "external jugular vein",
        "vertebral artery",
    ]
    if not part.is_valid():
        return "head vessel"
    return labels[part.value]


def named_head_vessels() -> List[HeadVessel]:
    """Return every named head vessel in a stable order.

    Returns:
        The three carotids, the two jugulars and the vertebral artery.
    """
    var parts = List[HeadVessel]()
    for index in range(VERTEBRAL_ARTERY.value + 1):  # pragma: no branch
        parts.append(HeadVessel(index))
    return parts^


def head_vessel_field(
    dimensions: HeadMuscleDimensions, part: HeadVessel, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one head vessel.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        part: A named vessel.
        side: `RIGHT` or `LEFT`.

    Returns:
        The vessel's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A head vessel must be a named artery or vein")
    if not side.is_valid():
        raise Error("A head side must be RIGHT or LEFT")
    var f = dimensions.head.frame
    var sweeps = List[Sweep]()
    # fmt: off
    if part == COMMON_CAROTID_ARTERY:
        append_template_tube(sweeps, f, floats(
            1.5, 48.0, 0.9, 1.9, 52.0, 1.4, 2.2, 56.0, 1.6,
            2.4, 59.5, 1.9,
        ), 0.38, 0.36)
    elif part == INTERNAL_CAROTID_ARTERY:
        append_template_tube(sweeps, f, floats(
            2.4, 59.5, 1.9, 2.5, 63.5, 0.9, 2.6, 66.2, 0.0,
            2.3, 67.6, -0.3,
        ), 0.3, 0.26)
    elif part == EXTERNAL_CAROTID_ARTERY:
        # The trunk up in front of the ear to the temple, and the facial
        # artery across the jaw to the corner of the eye.
        append_template_tube(sweeps, f, floats(
            2.4, 59.5, 2.1, 3.0, 62.5, 2.3, 4.4, 66.5, 0.6,
            5.9, 70.3, -0.4, 7.1, 74.0, -0.3, 7.6, 77.5, 0.2,
        ), 0.26, 0.12)
        append_template_tube(sweeps, f, floats(
            3.0, 62.5, 2.3, 4.2, 61.9, 4.0, 4.1, 63.2, 5.6,
            3.3, 64.8, 7.2, 2.2, 67.0, 8.4, 1.4, 70.0, 9.0,
        ), 0.18, 0.1)
    elif part == INTERNAL_JUGULAR_VEIN:
        append_template_tube(sweeps, f, floats(
            2.2, 67.3, -1.2, 3.0, 63.5, 0.2, 3.1, 59.0, 1.3,
            2.8, 53.0, 1.6, 2.4, 48.2, 1.6,
        ), 0.5, 0.62)
    elif part == EXTERNAL_JUGULAR_VEIN:
        append_template_tube(sweeps, f, floats(
            5.0, 67.2, 0.3, 5.3, 62.0, 1.0, 5.4, 56.0, 1.4,
            5.2, 50.8, 1.6, 4.8, 48.6, 1.9,
        ), 0.2, 0.24)
    else:
        # Up through the transverse processes from C6, then back over
        # the atlas and in through the foramen magnum.
        append_template_tube(sweeps, f, floats(
            2.6, 49.6, 0.3, 2.1, 53.0, -2.4, 2.0, 55.75, -2.8,
            2.0, 59.45, -2.4, 2.1, 63.3, -2.3, 2.8, 65.6, -2.6,
            2.0, 66.3, -3.9, 0.8, 67.2, -2.4,
        ), 0.2, 0.18)
    # fmt: on
    return SweepField(
        sweeps^, List[Dome](), side, f.cm(0.15), f.cm(0.03), f.cm(0.3)
    )


def head_vessel_distance(
    dimensions: HeadMuscleDimensions,
    part: HeadVessel,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        part: Which vessel to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return head_vessel_field(dimensions, part, side).distance(point)
