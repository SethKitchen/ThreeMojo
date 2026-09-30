# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The hair of the scalp and the eyebrows, as implicit solids.

A head of hair is drawn as its volume, not as its shafts: a shell about
nine millimeters thick over the cranium's skin, cut back to a hairline
at the forehead and cut away round the ears, down to the nape. Each
eyebrow is a short arc over its orbit. The scalp's hair crosses the
midline; the eyebrows are paired. The shapes are authored in template
centimeters. They are not a cited hair density table; see
`HAIR_PACKING` for the mass.

    var dims = head_muscle_dimensions(person)
    var d = head_hair_distance(dims, SCALP_HAIR, RIGHT, p)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.head.frame import HeadMuscleDimensions
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
)
from math.vector3 import Vector3

# How much of the hair's volume is hair rather than air: an authored
# value for short hair.
comptime HAIR_PACKING = Float32(0.1)


@fieldwise_init
struct HeadHair(Equatable, ImplicitlyCopyable, Writable):
    """Which hair of the head a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named groups is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named group."""
        if self.value < 0:
            return False
        return self.value <= EYEBROWS.value


# Across the midline.
comptime SCALP_HAIR = HeadHair(0)
comptime EYEBROWS = HeadHair(1)


def head_hair_label(part: HeadHair) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A head hair group, named or not.

    Returns:
        `"scalp hair"` or `"eyebrow"`, or `"head hair"` when `part` is
        not named.
    """
    if part == SCALP_HAIR:
        return "scalp hair"
    if part == EYEBROWS:
        return "eyebrow"
    return "head hair"


def named_head_hair() -> List[HeadHair]:
    """Return every named head hair group in a stable order.

    Returns:
        The scalp's hair and the eyebrows.
    """
    var parts = List[HeadHair]()
    for index in range(EYEBROWS.value + 1):  # pragma: no branch
        parts.append(HeadHair(index))
    return parts^


def is_paired_head_hair(part: HeadHair) raises -> Bool:
    """Return True if `part` is one of a pair.

    Args:
        part: A named group.

    Returns:
        True for the eyebrows.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A head hair group must be the scalp's or the eyebrows")
    return part == EYEBROWS


def head_hair_field(
    dimensions: HeadMuscleDimensions, part: HeadHair, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one head hair group.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        part: A named group.
        side: `RIGHT` or `LEFT`. The scalp's hair ignores it.

    Returns:
        The group's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    var paired = is_paired_head_hair(part)
    if not side.is_valid():
        raise Error("A head side must be RIGHT or LEFT")
    var h = dimensions.head.copy()
    var f = h.frame
    var sweeps = List[Sweep]()
    var domes = List[Dome]()
    if paired:
        var brow = Sweep(Vector3(0, 1, 0))
        brow.add(h.at(1.1, 74.6, 9.3), h.cm(0.3), h.cm(0.2))
        brow.add(h.at(2.7, 75.0, 9.1), h.cm(0.32), h.cm(0.2))
        brow.add(h.at(4.6, 74.6, 7.9), h.cm(0.22), h.cm(0.15))
        sweeps.append(brow^)
        return SweepField(
            sweeps^, domes^, side, f.cm(0.1), f.cm(0.03), f.cm(0.2)
        )
    # A shell over the cranium's skin, down to the nape.
    domes.append(
        Dome(
            h.at(0, 75.1, -1.0),
            h.cranium(8.55, 9.75, 11.05),
            h.cm(0.45),
            h.at(0, 67.5, 0).y,
        )
    )
    var field = SweepField(
        sweeps^, domes^, RIGHT, f.cm(0.3), f.cm(0.05), f.cm(0.3)
    )
    # The face below the hairline, and round each ear.
    var face = Sweep(Vector3(1, 0, 0))
    face.add(h.at(0, 70.0, 10.6), h.cm(8.8), h.cm(10.4))
    field.cut(face^)
    for s in range(2):  # pragma: no branch
        var x = Float32(1) - Float32(2 * s)
        var ear = Sweep(Vector3(1, 0, 0))
        ear.add(h.at(x * 8.6, 71.2, -1.2), h.cm(2.2), h.cm(2.8))
        field.cut(ear^)
    return field^


def head_hair_distance(
    dimensions: HeadMuscleDimensions,
    part: HeadHair,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        part: Which group to sample.
        side: `RIGHT` or `LEFT`. The scalp's hair ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return head_hair_field(dimensions, part, side).distance(point)
