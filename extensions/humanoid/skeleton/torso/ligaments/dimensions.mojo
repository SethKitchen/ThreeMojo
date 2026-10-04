# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Joint tissues and ligaments of the torso, as implicit solids.

The set is the intervertebral discs from T1 to the sacrum, the costal
cartilages of the first ten ribs, the anterior longitudinal ligament on
the front of the vertebral bodies, the supraspinous ligament along
the spinous tips, and the joints of the shoulder girdle: the
sternoclavicular disc and capsule, the acromioclavicular capsule and
the coracoclavicular ligament. The costal cartilages and the girdle's
tissues are paired; the rest lie on the midline. Radii are authored in template centimeters. They are not a
cited width table.

    var dims = torso_dimensions(Length(6.0, FOOT), MALE)
    var d = torso_ligament_distance(dims, INTERVERTEBRAL_DISCS, RIGHT, p)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.field import mix_point
from extensions.anatomy.soft_tissue import (
    SoftTissue,
    cartilage_tissue,
    ligament_tissue,
    meniscus_tissue,
)
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    VERTEBRAE,
    TorsoDimensions,
    cartilage_end,
    rib_path,
    shoulder_girdle,
    spinous_tip,
)
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
    tube,
)
from math.vector3 import Vector3
from std.math import max


@fieldwise_init
struct TorsoLigament(Equatable, ImplicitlyCopyable, Writable):
    """Which torso joint tissue or ligament a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named part."""
        if self.value < 0:
            return False
        return self.value <= CORACOCLAVICULAR_LIGAMENT.value


comptime INTERVERTEBRAL_DISCS = TorsoLigament(0)
comptime COSTAL_CARTILAGES = TorsoLigament(1)
comptime ANTERIOR_LONGITUDINAL_LIGAMENT = TorsoLigament(2)
comptime SUPRASPINOUS_LIGAMENT = TorsoLigament(3)
# The sternoclavicular joint's disc and capsule.
comptime STERNOCLAVICULAR_JOINT = TorsoLigament(4)
# The acromioclavicular joint's capsule.
comptime ACROMIOCLAVICULAR_JOINT = TorsoLigament(5)
# The conoid and trapezoid ligaments, from the coracoid up to the
# clavicle.
comptime CORACOCLAVICULAR_LIGAMENT = TorsoLigament(6)


def torso_ligament_field(
    dimensions: TorsoDimensions, part: TorsoLigament, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one torso joint tissue or ligament.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
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
        raise Error("A torso side must be RIGHT or LEFT")
    var paired = is_paired_ligament(part)
    var f = dimensions.frame
    var sweeps = List[Sweep]()
    var placed = RIGHT
    if part == INTERVERTEBRAL_DISCS:
        _discs(sweeps, dimensions)
    elif part.value >= STERNOCLAVICULAR_JOINT.value:
        placed = side
        _girdle_joint(sweeps, dimensions, part)
    elif paired:
        placed = side
        for rib in range(10):  # pragma: no branch
            var path = rib_path(dimensions, rib)
            var start = path[len(path) - 1]
            var end = cartilage_end(dimensions, rib)
            var points = List[Vector3]()
            points.append(start)
            # The lower cartilages bend up toward the sternum.
            var bend = Vector3(0, f.cm(0.4 * Float32(max(rib - 4, 0))), 0)
            points.append(mix_point(start, end, 0.5) + bend)
            points.append(end)
            var r = f.cm(0.42)
            if rib == 0:
                r = f.cm(0.58)
            sweeps.append(tube(points, r, 0.9 * r))
    elif part == ANTERIOR_LONGITUDINAL_LIGAMENT:
        # A wide thin band down the front of the bodies.
        var band = Sweep(Vector3(1, 0, 0))
        for index in range(VERTEBRAE):  # pragma: no branch
            var c = dimensions.centers[index]
            var front = Vector3(0, c.y, c.z + dimensions.depths[index])
            band.add(front + Vector3(0, 0, f.cm(0.1)), f.cm(0.9), f.cm(0.13))
        sweeps.append(band^)
    else:
        var tips = List[Vector3]()
        for index in range(VERTEBRAE):  # pragma: no branch
            tips.append(
                spinous_tip(dimensions, index) - Vector3(0, 0, f.cm(0.3))
            )
        sweeps.append(tube(tips, f.cm(0.2), f.cm(0.25)))
    return SweepField(
        sweeps^, List[Dome](), placed, f.cm(0.15), f.cm(0.04), 0.004
    )


def _girdle_joint(
    mut sweeps: List[Sweep], dimensions: TorsoDimensions, part: TorsoLigament
):
    """Append one joint tissue of the right shoulder girdle."""
    var f = dimensions.frame
    var g = shoulder_girdle(dimensions)
    if part == STERNOCLAVICULAR_JOINT:
        # The disc and the capsule between the clavicle's end and the
        # manubrium's notch.
        var joint = Sweep(Vector3(1, 0, 0))
        joint.round(f.at(2.0, 48.6, 3.3), f.cm(0.6))
        joint.round(g.sternoclavicular + Vector3(f.cm(0.4), 0, 0), f.cm(0.9))
        sweeps.append(joint^)
    elif part == ACROMIOCLAVICULAR_JOINT:
        var joint = Sweep(Vector3(1, 0, 0))
        joint.round(f.at(17.2, 49.8, -1.5), f.cm(0.42))
        joint.round(f.at(18.3, 49.8, -2.4), f.cm(0.42))
        sweeps.append(joint^)
    else:
        # The conoid, near the coracoid's base, and the trapezoid, in
        # front of it.
        var conoid = Sweep(Vector3(1, 0, 0))
        conoid.round(f.at(14.5, 48.9, -2.5), f.cm(0.3))
        conoid.round(f.at(13.8, 49.4, 0.2), f.cm(0.35))
        sweeps.append(conoid^)
        var trapezoid = Sweep(Vector3(1, 0, 0))
        trapezoid.round(f.at(14.9, 48.7, -1.0), f.cm(0.3))
        trapezoid.round(f.at(15.4, 49.45, -0.4), f.cm(0.38))
        sweeps.append(trapezoid^)


def _discs(mut sweeps: List[Sweep], dimensions: TorsoDimensions):
    """Append the disc between each two bodies, and L5 on the sacrum."""
    var f = dimensions.frame
    for index in range(VERTEBRAE):  # pragma: no branch
        var c = dimensions.centers[index]
        var w = dimensions.widths[index]
        var d = dimensions.depths[index]
        var top = c - Vector3(0, 0.5 * dimensions.heights[index], 0)
        var below: Vector3
        var bw = w
        var bd = d
        if index + 1 < VERTEBRAE:
            var n = dimensions.centers[index + 1]
            below = n + Vector3(0, 0.5 * dimensions.heights[index + 1], 0)
            bw = dimensions.widths[index + 1]
            bd = dimensions.depths[index + 1]
        else:
            # The sacral base, under the fifth lumbar body.
            below = f.at(0, 7.6, -2.4)
        var disc = Sweep(Vector3(1, 0, 0), flat_y=True)
        disc.add(top, 0.5 * (w + bw), 0.5 * (d + bd))
        disc.add(below, 0.5 * (w + bw), 0.5 * (d + bd))
        sweeps.append(disc^)


def torso_ligament_distance(
    dimensions: TorsoDimensions,
    part: TorsoLigament,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
        part: Which part to sample.
        side: `RIGHT` or `LEFT`. A midline part ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return torso_ligament_field(dimensions, part, side).distance(point)


def is_paired_ligament(part: TorsoLigament) raises -> Bool:
    """Return True if `part` is one of a pair.

    Args:
        part: A named part.

    Returns:
        True for the costal cartilages and the shoulder girdle's joint
        tissues.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A torso ligament must be a named part")
    return (
        part == COSTAL_CARTILAGES or part.value >= STERNOCLAVICULAR_JOINT.value
    )


def torso_ligament_tissue(part: TorsoLigament) raises -> SoftTissue:
    """Return the tissue `part` is made of.

    Args:
        part: A named part.

    Returns:
        Fibrocartilage for the intervertebral discs and the
        sternoclavicular disc, hyaline cartilage for the costal
        cartilages, and ligament for the rest.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A torso ligament must be a named part")
    if part == INTERVERTEBRAL_DISCS or part == STERNOCLAVICULAR_JOINT:
        return meniscus_tissue()
    if part == COSTAL_CARTILAGES:
        return cartilage_tissue()
    return ligament_tissue()


def torso_ligament_label(part: TorsoLigament) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A torso part, named or not.

    Returns:
        A short American English label, or `"torso ligament"` when
        `part` is not named.
    """
    if part == INTERVERTEBRAL_DISCS:
        return "intervertebral discs"
    if part == COSTAL_CARTILAGES:
        return "costal cartilages"
    if part == ANTERIOR_LONGITUDINAL_LIGAMENT:
        return "anterior longitudinal ligament"
    if part == SUPRASPINOUS_LIGAMENT:
        return "supraspinous ligament"
    if part == STERNOCLAVICULAR_JOINT:
        return "sternoclavicular joint"
    if part == ACROMIOCLAVICULAR_JOINT:
        return "acromioclavicular joint"
    if part == CORACOCLAVICULAR_LIGAMENT:
        return "coracoclavicular ligament"
    return "torso ligament"


def named_torso_ligaments() -> List[TorsoLigament]:
    """Return every named torso joint tissue and ligament.

    Returns:
        The discs, the costal cartilages, the two spinal bands and the
        shoulder girdle's three joint tissues.
    """
    var parts = List[TorsoLigament]()
    for index in range(
        CORACOCLAVICULAR_LIGAMENT.value + 1
    ):  # pragma: no branch
        parts.append(TorsoLigament(index))
    return parts^
