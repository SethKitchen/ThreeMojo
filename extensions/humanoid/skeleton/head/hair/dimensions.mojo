# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The hair of the scalp and the eyebrows, as implicit solids.

A head of hair is drawn as its volume, not as its shafts: a shell about
nine millimeters thick over the cranium's skin, cut back to a hairline
at the forehead and cut away round the ears, down to the nape. Each
eyebrow is an arc laid on the skin over its orbit, thick at its head
and thin at its tail; `BROW_THICKNESS` makes it fuller or finer, and
the brow's genes that move the skin move it with the skin. The scalp's hair crosses the
midline; the eyebrows are paired. The shapes are authored in template
centimeters. They are not a cited hair density table; see
`HAIR_PACKING` for the mass.

    var dims = head_muscle_dimensions(person)
    var d = head_hair_distance(dims, SCALP_HAIR, RIGHT, p)
"""

from extensions.humanoid.genome import BROW_THICKNESS
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.head.frame import HeadMuscleDimensions
from extensions.humanoid.skeleton.head.skin.dimensions import HeadSkinField
from extensions.humanoid.skeleton.field import DistanceField, smax
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
)
from math.vector3 import Vector3
from std.math import max, min

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
        # Each station of the brow is laid on the skin: authored in
        # front of the face, then walked back onto it.
        var skin = HeadSkinField(dimensions)
        var full = max(
            Float32(0.45),
            1 + Float32(0.45) * h.torso.genome.get(BROW_THICKNESS),
        )
        var rows: List[Float32] = [
            1.2,
            74.15,
            0.3,
            2.2,
            74.45,
            0.3,
            3.4,
            74.6,
            0.25,
            4.5,
            74.35,
            0.17,
            5.4,
            73.85,
            0.1,
        ]
        var points = List[Vector3]()
        for index in range(len(rows) // 3):  # pragma: no branch
            points.append(
                _on_skin(skin, h.at(rows[index * 3], rows[index * 3 + 1], 12.0))
            )
        # The brow's height runs up the skin, not straight up: the brow
        # ridge leans back, and a band held upright would stand off it.
        var n = skin.gradient(points[2])
        var up = Vector3(0, 1, 0) - n * n.y
        up.normalize()
        var brow = Sweep(up)
        for index in range(len(points)):  # pragma: no branch
            brow.add(
                points[index],
                h.cm(rows[index * 3 + 2]) * full,
                h.cm(0.035) * full,
            )
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
    # A soft blend, so the hair thins to nothing at the hairline
    # instead of ending in a cliff.
    var field = SweepField(
        sweeps^, domes^, RIGHT, f.cm(0.8), f.cm(0.05), f.cm(0.3)
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


struct HairShape(Copyable, DistanceField, Movable):
    """The solid a head hair group is drawn as.

    The scalp's hair is a shell over the skin itself, so it fits every
    head a genome makes: about seven millimeters deep at the sides and
    a centimeter on the crown, cut back to a hairline over the forehead,
    away round each ear and off above the nape. An eyebrow is its
    `head_hair_field`.
    """

    var scalp: Bool
    var skin: HeadSkinField
    var group: SweepField
    var cuts: List[Sweep]
    var soft: Float32
    var side_depth: Float32
    var crown_depth: Float32
    var ears: Float32
    var crown: Float32
    var nape: Float32
    var sideburn: Float32
    var ear_line: Float32
    var bury: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self,
        dimensions: HeadMuscleDimensions,
        part: HeadHair,
        side: BodySide,
    ) raises:
        """Shape one head hair group.

        Args:
            dimensions: Landmarks from `head_muscle_dimensions`.
            part: A named group.
            side: `RIGHT` or `LEFT`. The scalp's hair ignores it.

        Raises:
            Error: If `dimensions.validate` refuses the copy, if `part`
                is not named, or if `side` is not valid.
        """
        self.group = head_hair_field(dimensions, part, side)
        self.scalp = not is_paired_head_hair(part)
        self.skin = HeadSkinField(dimensions)
        var h = dimensions.head.copy()
        self.soft = h.cm(0.8)
        self.side_depth = h.cm(0.55)
        self.crown_depth = h.cm(1.0)
        self.ears = h.at(0, 75.0, 0).y
        self.crown = h.at(0, 82.0, 0).y
        self.nape = h.at(0, 66.8, 0).y
        # In front of the ears the hair stops at the sideburns.
        self.sideburn = h.at(0, 71.0, 0).y
        self.ear_line = h.at(0, 0, -2.2).z
        self.bury = h.cm(0.08)
        self.cuts = List[Sweep]()
        # The face below the hairline, and round each ear.
        var face = Sweep(Vector3(1, 0, 0))
        face.add(h.at(0, 70.0, 10.6), h.cm(8.8), h.cm(10.4))
        self.cuts.append(face^)
        for s in range(2):  # pragma: no branch
            var x = Float32(1) - Float32(2 * s)
            var ear = Sweep(Vector3(1, 0, 0))
            ear.add(h.at(x * 8.3, 71.1, -1.5), h.cm(2.8), h.cm(3.3))
            self.cuts.append(ear^)
        self.low = self.group.low
        self.high = self.group.high
        if self.scalp:
            # The shell follows the skin, which a genome can widen past
            # the dome the mass is taken from.
            var reach = self.crown_depth + self.soft
            self.low = Vector3(
                self.skin.low.x - reach,
                self.nape - self.soft,
                self.skin.low.z - reach,
            )
            self.high = Vector3(
                self.skin.high.x + reach,
                self.skin.high.y + reach,
                self.skin.high.z + reach,
            )

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the hair, in meters.

        Negative is inside.
        """
        if not self.scalp:
            return self.group.distance(point)
        var up = (point.y - self.ears) / (self.crown - self.ears)
        up = max(Float32(0), min(Float32(1), up))
        var depth = self.side_depth + (self.crown_depth - self.side_depth) * up
        var skin = self.skin.distance(point)
        var d = max(skin - depth, -skin - self.bury)
        d = smax(d, self.nape - point.y, self.soft)
        var cheek = max(point.y - self.sideburn, self.ear_line - point.z)
        d = smax(d, -cheek, self.soft)
        for index in range(len(self.cuts)):  # pragma: no branch
            d = smax(d, -self.cuts[index].distance(point, self.soft), self.soft)
        return d


def _on_skin(skin: HeadSkinField, start: Vector3) -> Vector3:
    """Return where a line from `start` straight back meets the skin.

    The walk keeps `start`'s height and its side, so a brow authored at
    a height lands at that height.
    """
    var p = start
    for _ in range(40):  # pragma: no branch
        p.z -= skin.distance(p)
    return p


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
    return HairShape(dimensions, part, side).distance(point)
