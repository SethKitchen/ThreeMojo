# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Nerves of the neck and the head, as implicit solids.

The cervical spinal cord runs up the vertebral canal to the foramen
magnum. The vagus nerve runs down in the carotid sheath, behind and
between the carotid and the jugular vein. The phrenic nerve runs down
the front of the anterior scalene. The cervical plexus's four skin
branches fan out from behind the middle of the sternocleidomastoid: up
to the ear, back to the occiput, forward across the throat and down
over the clavicle. The facial nerve leaves the skull under the ear and
fans forward through the parotid to the temple, the cheek and the jaw.
The spinal cord lies on the midline; the rest are paired.

Each nerve is a tube along a spline through template points in the
torso's frame, on the right; the left is its mirror image. Radii are
authored in template centimeters. They are not a cited fascicle table.

    var dims = head_muscle_dimensions(person)
    var d = head_nerve_distance(dims, VAGUS_NERVE, RIGHT, p)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.head.frame import HeadMuscleDimensions
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    TorsoFrame,
    template_points,
)
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
    floats,
    spline_points,
    tube,
)
from math.vector3 import Vector3


@fieldwise_init
struct HeadNerve(Equatable, ImplicitlyCopyable, Writable):
    """Which nerve of the neck and the head a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named nerves is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named nerve."""
        if self.value < 0:
            return False
        return self.value <= FACIAL_NERVE.value


# On the midline.
comptime CERVICAL_SPINAL_CORD = HeadNerve(0)
comptime VAGUS_NERVE = HeadNerve(1)
comptime PHRENIC_NERVE = HeadNerve(2)
comptime CERVICAL_PLEXUS = HeadNerve(3)
comptime FACIAL_NERVE = HeadNerve(4)


def is_paired_head_nerve(part: HeadNerve) raises -> Bool:
    """Return True if `part` is one of a pair.

    Args:
        part: A named nerve.

    Returns:
        False for the spinal cord, and True for the rest.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A head nerve must be a named nerve")
    return part != CERVICAL_SPINAL_CORD


def head_nerve_label(part: HeadNerve) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A head nerve, named or not.

    Returns:
        A short American English label, or `"head nerve"` when `part`
        is not named.
    """
    var labels: List[String] = [
        "cervical spinal cord",
        "vagus nerve",
        "phrenic nerve",
        "cervical plexus",
        "facial nerve",
    ]
    if not part.is_valid():
        return "head nerve"
    return labels[part.value]


def named_head_nerves() -> List[HeadNerve]:
    """Return every named head nerve in a stable order.

    Returns:
        The spinal cord, the vagus, the phrenic, the cervical plexus and
        the facial nerve.
    """
    var parts = List[HeadNerve]()
    for index in range(FACIAL_NERVE.value + 1):  # pragma: no branch
        parts.append(HeadNerve(index))
    return parts^


def head_nerve_field(
    dimensions: HeadMuscleDimensions, part: HeadNerve, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one head nerve.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        part: A named nerve.
        side: `RIGHT` or `LEFT`. The spinal cord ignores it.

    Returns:
        The nerve's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    var paired = is_paired_head_nerve(part)
    if not side.is_valid():
        raise Error("A head side must be RIGHT or LEFT")
    var h = dimensions.head.copy()
    var f = h.frame
    var sweeps = List[Sweep]()
    var placed = side
    if not paired:
        placed = RIGHT
        # Up the canal behind each body, to the foramen magnum.
        var run = List[Vector3]()
        for index in range(6, -1, -1):  # pragma: no branch
            var c = h.centers[index]
            run.append(Vector3(0, c.y, c.z - h.depths[index] - f.cm(0.85)))
        run.append(f.at(0, 67.6, -2.4))
        sweeps.append(tube(run, f.cm(0.6), f.cm(0.55)))
    # fmt: off
    elif part == VAGUS_NERVE:
        _nerve(sweeps, f, floats(
            2.1, 67.4, -0.9, 2.7, 63.0, 0.4, 2.8, 58.0, 1.0,
            2.4, 53.0, 1.0, 2.0, 48.6, 0.8,
        ), 0.16, 0.14)
    elif part == PHRENIC_NERVE:
        _nerve(sweeps, f, floats(
            3.2, 61.0, -1.4, 3.5, 58.0, -0.9, 3.8, 53.0, -0.3,
            3.4, 48.6, 0.6,
        ), 0.1, 0.1)
    elif part == CERVICAL_PLEXUS:
        # From behind the middle of the sternocleidomastoid.
        _nerve(sweeps, f, floats(
            3.4, 61.5, -1.8, 5.3, 60.5, -0.9, 6.0, 64.5, -0.6,
            6.5, 69.0, -0.5,
        ), 0.12, 0.08)
        _nerve(sweeps, f, floats(
            5.3, 60.5, -0.9, 5.4, 65.0, -3.2, 5.0, 70.5, -5.0,
        ), 0.1, 0.07)
        _nerve(sweeps, f, floats(
            5.3, 60.5, -0.9, 4.6, 59.6, 2.6, 2.0, 59.0, 4.8,
        ), 0.1, 0.07)
        _nerve(sweeps, f, floats(
            5.3, 60.5, -0.9, 5.4, 55.5, 0.4, 6.6, 51.2, 1.0,
        ), 0.1, 0.07)
    else:
        # Out of the skull under the ear, and forward through the
        # parotid to the temple, the cheek and the jaw.
        _nerve(sweeps, f, floats(
            4.9, 69.0, -1.4, 5.8, 68.4, 0.6,
        ), 0.14, 0.13)
        _nerve(sweeps, f, floats(
            5.8, 68.4, 0.6, 6.6, 71.5, 2.2, 6.6, 74.0, 4.0,
        ), 0.09, 0.06)
        _nerve(sweeps, f, floats(
            5.8, 68.4, 0.6, 5.5, 69.6, 4.2, 4.6, 70.2, 6.4,
        ), 0.09, 0.06)
        _nerve(sweeps, f, floats(
            5.8, 68.4, 0.6, 5.4, 67.2, 3.6, 4.2, 66.2, 6.4,
        ), 0.09, 0.06)
        _nerve(sweeps, f, floats(
            5.8, 68.4, 0.6, 5.6, 64.8, 1.8, 4.6, 62.6, 4.6,
        ), 0.09, 0.06)
    # fmt: on
    return SweepField(
        sweeps^, List[Dome](), placed, f.cm(0.1), f.cm(0.02), f.cm(0.3)
    )


def _nerve(
    mut sweeps: List[Sweep],
    f: TorsoFrame,
    coords: List[Float32],
    first: Float32,
    last: Float32,
):
    """Append a tube along a spline through template points.

    Args:
        sweeps: The field's sweeps, appended to.
        f: The torso's frame.
        coords: Template points as flat triples.
        first: The radius at the first point, in template cm.
        last: The radius at the last point, in template cm.
    """
    var run = template_points(f, coords)
    sweeps.append(tube(spline_points(run, 3), f.cm(first), f.cm(last)))


def head_nerve_distance(
    dimensions: HeadMuscleDimensions,
    part: HeadNerve,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        part: Which nerve to sample.
        side: `RIGHT` or `LEFT`. The spinal cord ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return head_nerve_field(dimensions, part, side).distance(point)
