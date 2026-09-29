# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Joint tissues and ligaments of the shoulder, the elbow and the forearm.

The set is the glenoid labrum around the socket's rim; the articular
cartilage on the humeral head, the glenoid, the trochlea, the
capitulum and the radial head; the coracohumeral and glenohumeral
ligaments that thicken the shoulder's capsule; the ulnar and radial
collateral ligaments of the elbow; the annular ligament around the
radial neck; and the interosseous membrane between the radius and the
ulna.

A cartilage is a thin pad on its bone's joint face. The membrane is a
thin sheet. Their meshes widen the thinnest radii; see
`extensions.humanoid.skeleton.arm.ligaments.geometry`. Radii are
authored in template centimeters. They are not a cited width table.

    var dims = arm_dimensions(Length(6.0, FOOT), MALE)
    var d = arm_ligament_distance(dims, ANNULAR_LIGAMENT, RIGHT, p)
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.arm.frame import ArmDimensions
from extensions.humanoid.skeleton.field import reject
from extensions.humanoid.skeleton.soft_tissue import (
    SoftTissue,
    cartilage_tissue,
    ligament_tissue,
    meniscus_tissue,
)
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    shoulder_girdle,
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
struct ArmLigament(Equatable, ImplicitlyCopyable, Writable):
    """Which joint tissue or ligament of the arm a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named part."""
        if self.value < 0:
            return False
        return self.value <= INTEROSSEOUS_MEMBRANE.value


comptime GLENOID_LABRUM = ArmLigament(0)
comptime ARTICULAR_CARTILAGE = ArmLigament(1)
comptime CORACOHUMERAL_LIGAMENT = ArmLigament(2)
# The superior, middle and inferior glenohumeral ligaments.
comptime GLENOHUMERAL_LIGAMENTS = ArmLigament(3)
comptime ULNAR_COLLATERAL_LIGAMENT = ArmLigament(4)
comptime RADIAL_COLLATERAL_LIGAMENT = ArmLigament(5)
comptime ANNULAR_LIGAMENT = ArmLigament(6)
comptime INTEROSSEOUS_MEMBRANE = ArmLigament(7)


def arm_ligament_label(part: ArmLigament) -> String:
    """Return the error-text name of `part`.

    Args:
        part: An arm part, named or not.

    Returns:
        A short American English label, or `"arm ligament"` when `part`
        is not named.
    """
    if not part.is_valid():
        return "arm ligament"
    var names = List[String]()
    names.append("glenoid labrum")
    names.append("articular cartilage")
    names.append("coracohumeral ligament")
    names.append("glenohumeral ligaments")
    names.append("ulnar collateral ligament")
    names.append("radial collateral ligament")
    names.append("annular ligament")
    names.append("interosseous membrane")
    return names[part.value]


def named_arm_ligaments() -> List[ArmLigament]:
    """Return every named arm joint tissue and ligament.

    Returns:
        The shoulder's parts, then the elbow's, then the membrane.
    """
    var parts = List[ArmLigament]()
    for index in range(INTEROSSEOUS_MEMBRANE.value + 1):
        parts.append(ArmLigament(index))
    return parts^


def arm_ligament_tissue(part: ArmLigament) raises -> SoftTissue:
    """Return the tissue `part` is made of.

    Args:
        part: A named part.

    Returns:
        Fibrocartilage for the labrum, hyaline cartilage for the joint
        faces, and ligament for the rest.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("An arm ligament must be a named part")
    if part == GLENOID_LABRUM:
        return meniscus_tissue()
    if part == ARTICULAR_CARTILAGE:
        return cartilage_tissue()
    return ligament_tissue()


def arm_ligament_field(
    dimensions: ArmDimensions, part: ArmLigament, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one arm joint tissue or ligament.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        part: A named part.
        side: `RIGHT` or `LEFT`.

    Returns:
        The part's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    _ = arm_ligament_tissue(part)
    if not side.is_valid():
        raise Error("An arm side must be RIGHT or LEFT")
    var f = dimensions.frame
    var t = dimensions.torso.frame
    var g = shoulder_girdle(dimensions.torso)
    # The glenoid faces out and a little forward; `up` and `across` span
    # its face.
    var face = Vector3(0.958, 0, 0.287)
    var up = Vector3(0, 1, 0)
    var across = Vector3(-0.287, 0, 0.958)
    var sweeps = List[Sweep]()
    if part == GLENOID_LABRUM:
        var ring = List[Vector3]()
        var rim = g.glenoid + face * t.cm(0.25)
        for k in range(13):
            var a = Float32(2) * pi * Float32(k) / Float32(12)
            ring.append(
                rim + up * (t.cm(1.9) * cos(a)) + across * (t.cm(1.4) * sin(a))
            )
        sweeps.append(tube(ring, t.cm(0.3), t.cm(0.3)))
    elif part == ARTICULAR_CARTILAGE:
        var toward = g.glenoid - g.shoulder
        toward.normalize()
        sweeps.append(
            joint_pad(
                g.shoulder + toward * f.cm(2.3), toward, f.cm(0.18), f.cm(1.4)
            )
        )
        sweeps.append(
            joint_pad(g.glenoid + face * t.cm(0.1), face, t.cm(0.15), t.cm(1.2))
        )
        var down = f.fore(0, -1, 0) - f.fore(0, 0, 0)
        down.normalize()
        sweeps.append(
            joint_pad(f.upper(1.6, -33.8, 0.9), down, f.cm(0.15), f.cm(0.75))
        )
        sweeps.append(
            joint_pad(f.upper(-0.6, -33.9, 0.35), down, f.cm(0.15), f.cm(0.9))
        )
        sweeps.append(
            joint_pad(f.fore(1.7, -1.05, 0.5), down, f.cm(0.15), f.cm(0.9))
        )
    elif part == CORACOHUMERAL_LIGAMENT:
        var band = Sweep(Vector3(1, 0, 0))
        band.round(t.at(14.2, 48.4, -2.8), t.cm(0.35))
        band.round(f.upper(1.2, 1.9, 0.8), f.cm(0.4))
        sweeps.append(band^)
    elif part == GLENOHUMERAL_LIGAMENTS:
        var superior = Sweep(Vector3(1, 0, 0))
        superior.round(t.at(16.1, 47.4, -2.0), t.cm(0.22))
        superior.round(f.upper(0.6, 0.9, 2.1), f.cm(0.25))
        sweeps.append(superior^)
        var middle = Sweep(Vector3(1, 0, 0))
        middle.round(t.at(16.3, 46.0, -1.7), t.cm(0.25))
        middle.round(f.upper(0.4, -0.6, 2.2), f.cm(0.28))
        sweeps.append(middle^)
        # The inferior ligament slings under the head.
        var sling = Sweep(Vector3(1, 0, 0))
        sling.round(t.at(16.0, 44.5, -2.2), t.cm(0.25))
        sling.round(f.upper(-0.3, -2.0, 1.4), f.cm(0.3))
        sling.round(f.upper(-0.9, -2.2, -0.8), f.cm(0.25))
        sweeps.append(sling^)
    elif part == ULNAR_COLLATERAL_LIGAMENT:
        # Its anterior band to the coronoid and posterior band to the
        # olecranon.
        var front = Sweep(Vector3(1, 0, 0))
        front.round(f.upper(-2.9, -31.6, 0.1), f.cm(0.3))
        front.round(f.fore(-1.2, -1.5, 0.6), f.cm(0.28))
        sweeps.append(front^)
        var back = Sweep(Vector3(1, 0, 0))
        back.round(f.upper(-2.9, -31.6, -0.4), f.cm(0.28))
        back.round(f.fore(-1.2, 0.2, -1.4), f.cm(0.26))
        sweeps.append(back^)
    elif part == RADIAL_COLLATERAL_LIGAMENT:
        var band = Sweep(Vector3(1, 0, 0))
        band.round(f.upper(3.3, -31.9, 0.0), f.cm(0.28))
        band.round(f.fore(2.9, -1.9, 0.3), f.cm(0.3))
        sweeps.append(band^)
    elif part == ANNULAR_LIGAMENT:
        var ring = List[Vector3]()
        for k in range(13):
            var a = Float32(2) * pi * Float32(k) / Float32(12)
            ring.append(f.fore(1.7 + 1.2 * cos(a), -2.4, 0.5 + 1.2 * sin(a)))
        sweeps.append(tube(ring, f.cm(0.22), f.cm(0.22)))
    else:
        # A thin sheet across the gap between the shafts, thin front to
        # back.
        var sheet = Sweep(Vector3(0, 0, 1))
        sheet.add(f.fore(0.5, -5.0, 0.3), f.cm(0.08), f.cm(0.7))
        sheet.add(f.fore(0.55, -12.0, 0.1), f.cm(0.08), f.cm(1.0))
        sheet.add(f.fore(0.5, -18.0, 0.1), f.cm(0.08), f.cm(1.05))
        sheet.add(f.fore(0.4, -23.0, 0.25), f.cm(0.08), f.cm(0.8))
        sweeps.append(sheet^)
    return SweepField(
        sweeps^, List[Dome](), side, f.cm(0.12), f.cm(0.03), f.cm(0.3)
    )


def joint_pad(
    center: Vector3, normal: Vector3, half: Float32, radius: Float32
) -> Sweep:
    """Return a thin pad on a joint face: a short strip across the face,
    thin along its normal.

    Args:
        center: The pad's center on the face, in meters.
        normal: The face's outward unit direction.
        half: Half the pad's thickness, in meters.
        radius: About the pad's radius, in meters.

    Returns:
        The pad's sweep.
    """
    var within = reject(Vector3(0, 1, 0), normal)
    if within.length() < 0.1:
        within = reject(Vector3(1, 0, 0), normal)
    within.normalize()
    var pad = Sweep(normal)
    pad.add(center - within * (0.5 * radius), half, 0.85 * radius)
    pad.add(center + within * (0.5 * radius), half, 0.85 * radius)
    return pad^


def arm_ligament_distance(
    dimensions: ArmDimensions, part: ArmLigament, side: BodySide, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        part: Which part to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return arm_ligament_field(dimensions, part, side).distance(point)
