# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Joint tissues, ligaments and cartilages of the neck and the head, as
implicit solids.

The set is the cervical discs from C2 down to T1, the nuchal ligament,
the capsules of the two atlanto-occipital joints, the disc of each jaw
joint, the larynx's thyroid and cricoid cartilages, and the trachea.
The jaw joints are paired; the rest lie on the midline. Radii are
authored in template centimeters. They are not a cited width table.

    var dims = head_dimensions(Length(6.0, FOOT), MALE)
    var d = head_ligament_distance(dims, LARYNX, RIGHT, p)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.head.frame import CERVICAL, HeadDimensions
from extensions.anatomy.soft_tissue import (
    SoftTissue,
    cartilage_tissue,
    ligament_tissue,
    meniscus_tissue,
)
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
    tube,
)
from math.vector3 import Vector3
from std.math import cos, pi, sin


@fieldwise_init
struct HeadLigament(Equatable, ImplicitlyCopyable, Writable):
    """Which joint tissue, ligament or cartilage of the head a caller
    asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named part."""
        if self.value < 0:
            return False
        return self.value <= TRACHEA.value


comptime CERVICAL_DISCS = HeadLigament(0)
comptime NUCHAL_LIGAMENT = HeadLigament(1)
comptime ATLANTO_OCCIPITAL_JOINTS = HeadLigament(2)
# Paired: one side's disc and capsule.
comptime TEMPOROMANDIBULAR_JOINT = HeadLigament(3)
comptime LARYNX = HeadLigament(4)
comptime TRACHEA = HeadLigament(5)


def head_ligament_field(
    dimensions: HeadDimensions, part: HeadLigament, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one head joint tissue or cartilage.

    Args:
        dimensions: Landmarks from `head_dimensions`.
        part: A named part.
        side: `RIGHT` or `LEFT`. A midline part ignores it.

    Returns:
        The part's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    if not side.is_valid():
        raise Error("A head side must be RIGHT or LEFT")
    if not part.is_valid():
        raise Error("A head ligament must be a named part")
    var h = dimensions.copy()
    var sweeps = List[Sweep]()
    var placed = RIGHT
    if part == CERVICAL_DISCS:
        _discs(sweeps, h)
    elif part == NUCHAL_LIGAMENT:
        # A thin sheet in the midline, from the occipital protuberance
        # down the backs of the spines to C7.
        var points = List[Vector3]()
        points.append(h.at(0, 72.0, -9.6))
        points.append(h.at(0, 67.0, -7.6))
        points.append(h.at(0, 62.4, -6.3))
        points.append(h.at(0, 58.5, -6.6))
        points.append(h.at(0, 53.0, -8.4))
        var sheet = Sweep(Vector3(1, 0, 0))
        for index in range(len(points)):  # pragma: no branch
            sheet.add(points[index], h.cm(0.18), h.cm(0.9))
        sweeps.append(sheet^)
    elif part == ATLANTO_OCCIPITAL_JOINTS:
        for s in range(2):  # pragma: no branch
            var x = Float32(1) - Float32(2 * s)
            var joint = Sweep(Vector3(1, 0, 0))
            joint.round(h.at(x * 1.55, 66.2, -2.1), h.cm(0.75))
            joint.round(h.at(x * 1.35, 66.8, -2.2), h.cm(0.7))
            sweeps.append(joint^)
    elif part == TEMPOROMANDIBULAR_JOINT:
        placed = side
        var disc = Sweep(Vector3(1, 0, 0))
        disc.add(h.at(5.0, 71.4, 0.2), h.cm(0.95), h.cm(0.35))
        disc.add(h.at(5.0, 71.5, -0.4), h.cm(0.9), h.cm(0.3))
        sweeps.append(disc^)
    elif part == LARYNX:
        _larynx(sweeps, h)
    else:
        var windpipe = List[Vector3]()
        windpipe.append(h.at(0, 55.3, 1.4))
        windpipe.append(h.at(0, 52.0, 1.5))
        windpipe.append(h.at(0, 48.6, 1.4))
        sweeps.append(tube(windpipe, h.cm(0.95), h.cm(0.95)))
    return SweepField(
        sweeps^, List[Dome](), placed, h.cm(0.15), h.cm(0.04), h.cm(0.3)
    )


def _discs(mut sweeps: List[Sweep], h: HeadDimensions):
    """Append the disc under each body from C2 down, the last on T1."""
    for index in range(1, CERVICAL):  # pragma: no branch
        var c = h.centers[index]
        var w = h.widths[index]
        var d = h.depths[index]
        var top = c - Vector3(0, 0.5 * h.heights[index], 0)
        var below: Vector3
        var bw: Float32
        var bd: Float32
        if index + 1 < CERVICAL:
            var n = h.centers[index + 1]
            below = n + Vector3(0, 0.5 * h.heights[index + 1], 0)
            bw = h.widths[index + 1]
            bd = h.depths[index + 1]
        else:
            # The torso's first thoracic body.
            var t = h.torso.centers[0]
            below = t + Vector3(0, 0.5 * h.torso.heights[0], 0)
            bw = h.torso.widths[0]
            bd = h.torso.depths[0]
        var disc = Sweep(Vector3(1, 0, 0), flat_y=True)
        disc.add(top, 0.5 * (w + bw), 0.5 * (d + bd))
        disc.add(below, 0.5 * (w + bw), 0.5 * (d + bd))
        sweeps.append(disc^)


def _larynx(mut sweeps: List[Sweep], h: HeadDimensions):
    """Append the thyroid cartilage's two plates, which meet in front at
    the laryngeal prominence, and the cricoid's ring below them."""
    for s in range(2):  # pragma: no branch
        var x = Float32(1) - Float32(2 * s)
        var plate = Sweep(Vector3(0, 1, 0))
        plate.add(h.at(x * 2.0, 57.7, 0.8), h.cm(1.1), h.cm(0.18))
        plate.add(h.at(x * 0.1, 57.9, 3.3), h.cm(1.2), h.cm(0.2))
        sweeps.append(plate^)
    var ring = List[Vector3]()
    for step in range(13):  # pragma: no branch
        var turn = Float32(2) * pi * Float32(step) / Float32(12)
        ring.append(h.at(1.25 * sin(turn), 55.9, 1.5 + 1.25 * cos(turn)))
    sweeps.append(tube(ring, h.cm(0.32), h.cm(0.32)))


def head_ligament_distance(
    dimensions: HeadDimensions,
    part: HeadLigament,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `head_dimensions`.
        part: Which part to sample.
        side: `RIGHT` or `LEFT`. A midline part ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return head_ligament_field(dimensions, part, side).distance(point)


def is_paired_head_ligament(part: HeadLigament) raises -> Bool:
    """Return True if `part` is one of a pair.

    Args:
        part: A named part.

    Returns:
        True for the jaw joint.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A head ligament must be a named part")
    return part == TEMPOROMANDIBULAR_JOINT


def is_head_cartilage(part: HeadLigament) raises -> Bool:
    """Return True if `part` takes a cartilage look.

    Args:
        part: A named part.

    Returns:
        True for the discs, the jaw joint, the larynx and the trachea.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A head ligament must be a named part")
    return not (part == NUCHAL_LIGAMENT or part == ATLANTO_OCCIPITAL_JOINTS)


def head_ligament_tissue(part: HeadLigament) raises -> SoftTissue:
    """Return the tissue `part` is made of.

    Args:
        part: A named part.

    Returns:
        Fibrocartilage for the discs and the jaw joint, hyaline
        cartilage for the larynx and the trachea, and ligament for the
        rest.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A head ligament must be a named part")
    if part == CERVICAL_DISCS or part == TEMPOROMANDIBULAR_JOINT:
        return meniscus_tissue()
    if part == LARYNX or part == TRACHEA:
        return cartilage_tissue()
    return ligament_tissue()


def head_ligament_label(part: HeadLigament) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A head part, named or not.

    Returns:
        A short American English label, or `"head ligament"` when
        `part` is not named.
    """
    if part == CERVICAL_DISCS:
        return "cervical discs"
    if part == NUCHAL_LIGAMENT:
        return "nuchal ligament"
    if part == ATLANTO_OCCIPITAL_JOINTS:
        return "atlanto-occipital joints"
    if part == TEMPOROMANDIBULAR_JOINT:
        return "temporomandibular joint"
    if part == LARYNX:
        return "larynx"
    if part == TRACHEA:
        return "trachea"
    return "head ligament"


def named_head_ligaments() -> List[HeadLigament]:
    """Return every named head joint tissue, ligament and cartilage.

    Returns:
        The discs, the nuchal ligament, the atlanto-occipital joints,
        the jaw joint, the larynx and the trachea.
    """
    var parts = List[HeadLigament]()
    for index in range(TRACHEA.value + 1):  # pragma: no branch
        parts.append(HeadLigament(index))
    return parts^
